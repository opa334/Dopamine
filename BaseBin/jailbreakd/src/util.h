#import <Foundation/Foundation.h>

uint64_t proc_get_task(uint64_t proc_ptr);
pid_t proc_get_pid(uint64_t proc_ptr);
void proc_iterate(void (^itBlock)(uint64_t, BOOL*));
uint64_t proc_for_pid(pid_t pidToFind);
uint64_t task_get_first_thread(uint64_t task_ptr);
uint64_t thread_get_act_context(uint64_t thread_ptr);
uint64_t task_get_vm_map(uint64_t task_ptr);
uint64_t vm_map_get_pmap(uint64_t vm_map_ptr);
void pmap_set_type(uint64_t pmap_ptr, uint8_t type);
uint64_t pmap_lv2(uint64_t pmap_ptr, uint64_t virt);
uint64_t get_cspr_kern_intr_en(void);
uint64_t get_cspr_kern_intr_dis(void);