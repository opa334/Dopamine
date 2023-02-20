#import <Foundation/Foundation.h>

uint64_t kalloc(uint64_t size);
uint64_t kfree(uint64_t addr, uint64_t size);

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

uint64_t proc_get_ucred(uint64_t proc_ptr);
uint64_t proc_get_proc_ro(uint64_t proc_ptr);
uint64_t proc_ro_get_ucred(uint64_t proc_ro_ptr);

uint64_t ucred_get_cr_label(uint64_t ucred_ptr);
uint64_t cr_label_get_OSEntitlements(uint64_t cr_label_ptr);
NSData *OSEntitlements_get_cdhash(uint64_t OSEntitlements_ptr);

NSMutableDictionary *OSEntitlements_dump_entitlements(uint64_t OSEntitlements_ptr);
void OSEntitlements_replace_entitlements(uint64_t OSEntitlements_ptr, NSDictionary *newEntitlements);

NSMutableDictionary *proc_dump_entitlements(uint64_t proc_ptr);
void proc_replace_entitlements(uint64_t proc_ptr, NSDictionary *entitlements);