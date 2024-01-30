#include "util.h"
#include "primitives.h"
#include "info.h"
#include "kernel.h"
#include "translation.h"
#include <spawn.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <signal.h>
#include <sys/sysctl.h>
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

	void *free_lvl2 = NULL;
	uint64_t tte_lvl2 = 0;
	uint64_t allocatedPT = 0;
	uint64_t pinfo_pa = 0;
	while (true) {
		// When we allocate the entire address range of an L2 block, we can assume ownership of the backing table
		if (posix_memalign(&free_lvl2, L2_BLOCK_SIZE, L2_BLOCK_SIZE) != 0) {
			printf("WARNING: Failed to allocate L2 page table address range\n");
			return 0;
		}
		// Now, fault in one page to make the kernel allocate the page table for it
		*(volatile uint64_t *)free_lvl2;

		// Find the newly allocated page table
		uint64_t lvl = PMAP_TT_L2_LEVEL;
		allocatedPT = vtophys_lvl(ttep, (uint64_t)free_lvl2, &lvl, &tte_lvl2);

		uint64_t pvh = pai_to_pvh(pa_index(allocatedPT));
		uint64_t ptdp = pvh_ptd(pvh);
		uint64_t pinfo = kread64(ptdp + koffsetof(pt_desc, ptd_info)); // TODO: Fake 16k devices (4 values)
		pinfo_pa = kvtophys(pinfo);

		uint16_t refCount = physread16(pinfo_pa);
		if (refCount != 1) {
			// Something is off, retry
			free(free_lvl2);
			continue;
		}

		break;
	}

	// Bump reference count of our allocated page table
	physwrite16(pinfo_pa, 0x1337);

	// Deallocate address range (our allocated page table will stay because we bumped it's reference count)
	free(free_lvl2);

	// Remove our allocated page table from it's original location (leak it)
	physwrite64(tte_lvl2, 0);

	// Ensure there is at least one entry in page table
	// Attempts to prevent "pte is empty" panic
	// Sometimes weird prefetches happen so this has to be a valid physical page to ensure those don't panic
	// Disabled for now cause it causes super weird issues
	//physwrite64(allocatedPT, kconstant(physBase) | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY);

	// Reference count of new page table must be 0!
	// XXX: original ref count is 1 though, why 0?
	physwrite16(pinfo_pa, 0);

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

int pmap_map_in(uint64_t pmap, uint64_t uaStart, uint64_t paStart, uint64_t size)
{
	thread_caffeinate_start();

	uint64_t uaEnd = uaStart + size;
	uint64_t ttep = kread64(pmap + koffsetof(pmap, ttep));

	// Sanity check: Ensure the entire area to be mapped in is not mapped to anything yet
	for(uint64_t ua = uaStart; ua < uaEnd; ua += PAGE_SIZE) {
		if (vtophys(ttep, ua)) { thread_caffeinate_stop(); return -1; }
		// TODO: If all mappings match 1:1, maybe return 0 instead of -1?
	}

	// Allocate all page tables that need to be allocated
	for(uint64_t ua = uaStart; ua < uaEnd; ua += PAGE_SIZE) {
		uint64_t leafLevel;
		do {
			leafLevel = PMAP_TT_L3_LEVEL;
			uint64_t pt = 0;
			vtophys_lvl(ttep, ua, &leafLevel, &pt);
			if (leafLevel != PMAP_TT_L3_LEVEL) {
				uint64_t pt_va = 0;
				switch (leafLevel) {
					case PMAP_TT_L1_LEVEL: {
						pt_va = ua & ~L1_BLOCK_MASK;
						break;
					}
					case PMAP_TT_L2_LEVEL: {
						pt_va = ua & ~L2_BLOCK_MASK;
						break;
					}
				}
				uint64_t newTable = pmap_alloc_page_table(pmap, pt_va);
				if (newTable) {
					physwrite64(pt, newTable | ARM_TTE_VALID | ARM_TTE_TYPE_TABLE);
				}
				else { thread_caffeinate_stop(); return -2; }
			}
		} while (leafLevel < PMAP_TT_L3_LEVEL);
	}

	// Insert entries into L3 pages
	for(uint64_t ua = uaStart; ua < uaEnd; ua += PAGE_SIZE) {
		uint64_t pa = (ua - uaStart) + paStart;
		uint64_t leafLevel = PMAP_TT_L3_LEVEL;
		uint64_t pt = 0;

		vtophys_lvl(ttep, ua, &leafLevel, &pt);
		physwrite64(pt, pa | PERM_TO_PTE(PERM_KRW_URW) | PTE_NON_GLOBAL | PTE_OUTER_SHAREABLE | PTE_LEVEL3_ENTRY);
	}

	thread_caffeinate_stop();
	return 0;
}

int sign_kernel_thread(uint64_t proc, mach_port_t threadPort)
{
	uint64_t threadKobj = task_get_ipc_port_kobject(proc_task(proc), threadPort);
	uint64_t threadContext = kread_ptr(threadKobj + koffsetof(thread, machine_contextData));

	uint64_t pc   = kread64(threadContext + offsetof(kRegisterState, pc));
	uint64_t cpsr = kread64(threadContext + offsetof(kRegisterState, cpsr));
	uint64_t lr   = kread64(threadContext + offsetof(kRegisterState, lr));
	uint64_t x16  = kread64(threadContext + offsetof(kRegisterState, x[16]));
	uint64_t x17  = kread64(threadContext + offsetof(kRegisterState, x[17]));

	return kcall(NULL, ksymbol(ml_sign_thread_state), 6, (uint64_t[]){ threadContext, pc, cpsr, lr, x16, x17 });
}

uint64_t kpacda(uint64_t pointer, uint64_t modifier)
{
	if (gPrimitives.kexec && kgadget(pacda)) {
		// |------- GADGET -------|
		// | cmp x1, #0		      |
		// | pacda x1, x9         |
		// | str x9, [x8]         |
		// | csel x9, xzr, x1, eq |
		// | ret                  |
		// |----------------------|
		uint64_t output = 0;
		uint64_t output_kernelVA = phystokv(vtophys(kread_ptr(pmap_self() + koffsetof(pmap, ttep)), (uint64_t)&output));
		kRegisterState threadState = { 0 };
		threadState.pc = kgadget(pacda);
		threadState.x[1] = pointer;
		threadState.x[9] = modifier;
		threadState.x[8] = output_kernelVA;
		kexec(&threadState);
		return output;
	}
	return 0;
}

uint64_t kptr_sign(uint64_t kaddr, uint64_t pointer, uint16_t salt)
{
	uint64_t modifier = (kaddr & 0xffffffffffff) | ((uint64_t)salt << 48);
	return kpacda(UNSIGN_PTR(pointer), modifier);
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

void killall(const char *executablePathToKill, bool softly)
{
	static int maxArgumentSize = 0;
	if (maxArgumentSize == 0) {
		size_t size = sizeof(maxArgumentSize);
		if (sysctl((int[]){ CTL_KERN, KERN_ARGMAX }, 2, &maxArgumentSize, &size, NULL, 0) == -1) {
			perror("sysctl argument size");
			maxArgumentSize = 4096; // Default
		}
	}
	int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL};
	struct kinfo_proc *info;
	size_t length;
	int count;
	
	if (sysctl(mib, 3, NULL, &length, NULL, 0) < 0)
		return;
	if (!(info = malloc(length)))
		return;
	if (sysctl(mib, 3, info, &length, NULL, 0) < 0) {
		free(info);
		return;
	}
	count = length / sizeof(struct kinfo_proc);
	for (int i = 0; i < count; i++) {
		pid_t pid = info[i].kp_proc.p_pid;
		if (pid == 0) {
			continue;
		}
		size_t size = maxArgumentSize;
		char* buffer = (char *)malloc(length);
		if (sysctl((int[]){ CTL_KERN, KERN_PROCARGS2, pid }, 3, buffer, &size, NULL, 0) == 0) {
			char *executablePath = buffer + sizeof(int);
			if (strcmp(executablePath, executablePathToKill) == 0) {
				if(softly)
				{
					kill(pid, SIGTERM);
				}
				else
				{
					kill(pid, SIGKILL);
				}
			}
		}
		free(buffer);
	}
	free(info);
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
	if (gCaffeinateThreadRunCount == 0) {
		pthread_join(gCaffeinateThread, NULL);
	}
}