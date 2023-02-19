#import "util.h"
#import "ppl.h"
#import "jailbreakd.h"

uint64_t proc_get_task(uint64_t proc_ptr)
{
	return kread_ptr(proc_ptr + 0x10ULL);
}

pid_t proc_get_pid(uint64_t proc_ptr)
{
	return kread32(proc_ptr + 0x68ULL);
}

void proc_iterate(void (^itBlock)(uint64_t, BOOL*))
{
	uint64_t allproc = bootInfo_getSlidUInt64(@"allproc");
    uint64_t proc = allproc;
    while((proc = kread_ptr(proc)))
    {
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

uint64_t task_get_vm_map(uint64_t task_ptr)
{
    return kread_ptr(task_ptr + 0x28ULL);
}

uint64_t vm_map_get_pmap(uint64_t vm_map_ptr)
{
    return kread_ptr(vm_map_ptr + bootInfo_getUInt64(@"VM_MAP_PMAP"));
}

void pmap_set_type(uint64_t pmap_ptr, uint8_t type)
{
    uint64_t kernel_el = bootInfo_getUInt64(@"kernel_el");
    uint32_t el2_adjust = (kernel_el == 8) ? 8 : 0;
    kwrite8(pmap_ptr + 0xC8ULL + el2_adjust, type);
}

uint64_t pmap_lv2(uint64_t pmap_ptr, uint64_t virt)
{
    uint64_t ttep = kread64(pmap_ptr + 0x8ULL);
    
    uint64_t table1Off   = (virt >> 36ULL) & 0x7ULL;
    uint64_t table1Entry = physread64(ttep + (8ULL * table1Off));
    if ((table1Entry & 0x3) != 3) {
        return 0;
    }
    
    uint64_t table2 = table1Entry & 0xFFFFFFFFC000ULL;
    uint64_t table2Off = (virt >> 25ULL) & 0x7FFULL;
    uint64_t table2Entry = physread64(table2 + (8ULL * table2Off));
    
    return table2Entry;
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