#include "util.h"
#include "primitives.h"
#include "info.h"
#include "kernel.h"
#include "translation.h"
#include <spawn.h>
#include <mach/mach_time.h>
#include <pthread.h>
extern char **environ;

void proc_iterate(void (^itBlock)(uint64_t, bool*))
{
	uint64_t proc = ksymbol(allproc);
	while((proc = kread_ptr(proc + koffsetof(proc, list_next))))
	{
		bool stop = false;
		itBlock(proc, &stop);
		if(stop) return;
	}
}

uint64_t proc_self(void)
{
	static uint64_t gSelfProc = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		bool needsRelease = false;
		gSelfProc = proc_find(getpid());
		// decrement ref count again, we assume proc_self will exist for the whole lifetime of this process
		proc_rele(gSelfProc);
	});
	return gSelfProc;
}

uint64_t task_self(void)
{
	static uint64_t gSelfTask = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		gSelfTask = proc_task(proc_self());
	});
	return gSelfTask;
}

uint64_t vm_map_self(void)
{
	static uint64_t gSelfMap = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		gSelfMap = kread_ptr(task_self() + koffsetof(task, map));
	});
	return gSelfMap;
}

uint64_t pmap_self(void)
{
	static uint64_t gSelfPmap = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		gSelfPmap = kread_ptr(vm_map_self() + koffsetof(vm_map, pmap));
	});
	return gSelfPmap;
}

uint64_t task_get_ipc_port_table_entry(uint64_t task, mach_port_t port)
{
	uint64_t itk_space = kread_ptr(task + koffsetof(task, itk_space));
	return ipc_entry_lookup(itk_space, port);
}

uint64_t task_get_ipc_port_object(uint64_t task, mach_port_t port)
{
	return kread_ptr(task_get_ipc_port_table_entry(task, port) + koffsetof(ipc_entry, object));
}

uint64_t task_get_ipc_port_kobject(uint64_t task, mach_port_t port)
{
	return kread_ptr(task_get_ipc_port_object(task, port) + koffsetof(ipc_port, kobject));
}

uint64_t alloc_page_table_unassigned(void)
{
	thread_caffeinate_start();

	uint64_t pmap = pmap_self();
	uint64_t ttep = kread64(pmap + koffsetof(pmap, ttep));

	// When we allocate the entire address range of an L2 block, we can assume ownership of the backing table
	void *free_lvl2 = NULL;
	if (posix_memalign(&free_lvl2, L2_BLOCK_SIZE, L2_BLOCK_SIZE) != 0) {
		printf("WARNING: Failed to allocate L2 page table address range\n");
		return 0;
	}
	// Now, fault in one page to make the kernel allocate the page table for it
	*(volatile uint64_t *)free_lvl2;

	// Find the newly allocated page table
	uint64_t lvl = PMAP_TT_L2_LEVEL;
	uint64_t tte_lvl2 = 0;
	uint64_t allocatedPT = vtophys_lvl(ttep, (uint64_t)free_lvl2, &lvl, &tte_lvl2);

	// Bump reference count of our allocated page table by one
	uint64_t pvh = pai_to_pvh(pa_index(allocatedPT));
	uint64_t ptdp = pvh_ptd(pvh);
	uint64_t pinfo = kread64(ptdp + koffsetof(pt_desc, ptd_info)); // TODO: Fake 16k devices (4 values)
	uint64_t pinfo_pa = kvtophys(pinfo);
	physwrite16(pinfo_pa, physread16(pinfo_pa)+1);

	// Deallocate address range (our allocated page table will stay because we bumped it's reference count)
	free(free_lvl2);

	// Decrement reference count of our allocated page table again
	physwrite16(pinfo_pa, physread16(pinfo_pa)-1);

	// Remove our allocated page table from it's original location (leak it)
	physwrite64(tte_lvl2, 0);

	// Clear the allocated page table of any entries (there should be one)
	uint8_t empty[PAGE_SIZE];
	memset(empty, 0, PAGE_SIZE);
	physwritebuf(allocatedPT, empty, PAGE_SIZE);

	thread_caffeinate_stop();

	return allocatedPT;
}

uint64_t pmap_alloc_page_table(uint64_t pmap, uint64_t va)
{
	if (!pmap) {
		pmap = pmap_self();
	}

	uint64_t tt_p = alloc_page_table_unassigned();
	if (!tt_p) return 0;

	uint64_t pvh = pai_to_pvh(pa_index(tt_p));
	uint64_t ptdp = pvh_ptd(pvh);

	uint64_t ptdp_pa = kvtophys(ptdp);

	// At this point the allocated page table is associated
	// to the pmap of this process alongside the address it was allocated on
	// We now need to replace the association with the context in which it will be used
	physwrite64(ptdp_pa + koffsetof(pt_desc, pmap), pmap);

	// On A14+ PT_INDEX_MAX is 4, for whatever reason
	// However in practice, only the first slot is used...
	// TODO: On devices where kernel page size != userland page size, populate all 4 values
	physwrite64(ptdp_pa + koffsetof(pt_desc, va), va);

	return tt_p;
}

int exec_cmd(const char *binary, ...)
{
	int argc = 1;
	va_list args;
    va_start(args, binary);
	while (va_arg(args, const char *)) argc++;
	va_end(args);

	va_start(args, binary);
	const char *argv[argc+1];
	argv[0] = binary;
	for (int i = 1; i < argc; i++) {
		argv[i] = va_arg(args, const char *);
	}
	argv[argc] = NULL;

	pid_t spawnedPid = 0;
	int spawnError = posix_spawn(&spawnedPid, binary, NULL, NULL, (char *const *)argv, environ);
	if (spawnError != 0) return spawnError;

	int status = 0;
	do {
		if (waitpid(spawnedPid, &status, 0) == -1) {
			return -1;
		}
	} while (!WIFEXITED(status) && !WIFSIGNALED(status));

	return status;
}

// code from ktrw by Brandon Azad : https://github.com/googleprojectzero/ktrw
// A worker thread for activity_thread that just spins.
static void* worker_thread(void *arg)
{
	uint64_t end = *(uint64_t *)arg;
	for (;;) {
		close(-1);
		uint64_t now = mach_absolute_time();
		if (now >= end) {
			break;
		}
	}
	return NULL;
}

// A thread to alternately spin and sleep.
static void* activity_thread(void *arg)
{
	volatile uint64_t *runCount = arg;
	struct mach_timebase_info tb;
	mach_timebase_info(&tb);
	const unsigned milliseconds = 40;
	const unsigned worker_count = 10;
	while (*runCount != 0) {
		// Spin for one period on multiple threads.
		uint64_t start = mach_absolute_time();
		uint64_t end = start + milliseconds * 1000 * 1000 * tb.denom / tb.numer;
		pthread_t worker[worker_count];
		for (unsigned i = 0; i < worker_count; i++) {
			pthread_create(&worker[i], NULL, worker_thread, &end);
		}
		worker_thread(&end);
		for (unsigned i = 0; i < worker_count; i++) {
			pthread_join(worker[i], NULL);
		}
		// Sleep for one period.
		usleep(milliseconds * 1000);
	}
	return NULL;
}

static uint64_t gCaffeinateThreadRunCount = 0;
static pthread_t gCaffeinateThread = NULL;

void thread_caffeinate_start(void)
{
	if (gCaffeinateThreadRunCount == UINT64_MAX) return;
	gCaffeinateThreadRunCount++;
	if (gCaffeinateThreadRunCount == 1) {
		pthread_create(&gCaffeinateThread, NULL, activity_thread, &gCaffeinateThreadRunCount);
	}
}

void thread_caffeinate_stop(void)
{
	if (gCaffeinateThreadRunCount == 0) return;
	gCaffeinateThreadRunCount--;
	if (gCaffeinateThreadRunCount) {
		pthread_join(gCaffeinateThread, NULL);
	}
}