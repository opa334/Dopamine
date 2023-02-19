#import "util.h"
#import "ppl.h"
#import "jailbreakd.h"

uint64_t proc_get_task(uint64_t proc_ptr)
{
	NSLog(@"proc_get_task: 0x%llX", proc_ptr); usleep(1000);
	return kread_ptr(proc_ptr + 0x10ULL);
}

pid_t proc_get_pid(uint64_t proc_ptr)
{
	NSLog(@"proc_get_pid: 0x%llX", proc_ptr); usleep(1000);
	return kread32(proc_ptr + 0x68ULL);
}

void proc_iterate(void (^itBlock)(uint64_t, BOOL*))
{
	uint64_t allproc = bootInfo_getSlidUInt64(@"allproc");
	NSLog(@"allproc: 0x%llX", allproc); usleep(1000);
    uint64_t proc = allproc;
    while((proc = kread_ptr(proc)))
    {
		NSLog(@"proc: 0x%llX", allproc); usleep(1000);
		
        BOOL stop = NO;
        itBlock(proc, &stop);
        if(stop == 1) return;
    }
}

uint64_t proc_for_pid(pid_t pidToFind)
{
    __block uint64_t foundProc = 0;

    proc_iterate(^(uint64_t proc, BOOL* stop) {
        pid_t pid = proc_get_pid(proc);
        if(pid == pidToFind)
        {
            foundProc = proc;
            *stop = YES;
        }
    });
    
    return foundProc;
}

uint64_t task_get_first_thread(uint64_t task_ptr)
{
	return kread_ptr(task_ptr + 0x60ULL);
}

uint64_t thread_get_act_context(uint64_t thread_ptr)
{
	uint64_t actContextOffset = bootInfo_getUInt64(@"ACT_CONTEXT");
	return kread_ptr(thread_ptr + actContextOffset);
}

uint64_t get_cspr_kern_intr_en(void)
{
	uint32_t kernel_el = bootInfo_getUInt64(@"kernel_el");
	return (0x401000 | ((uint32_t)kernel_el));
}

uint64_t get_cspr_kern_intr_dis(void)
{
	uint32_t kernel_el = bootInfo_getUInt64(@"kernel_el");
	return (0x4013c0 | ((uint32_t)kernel_el));
}