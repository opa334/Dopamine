#import <Foundation/Foundation.h>

uint64_t proc_get_task(uint64_t proc_ptr);
pid_t proc_get_pid(uint64_t proc_ptr);
void proc_iterate(void (^itBlock)(uint64_t, BOOL*));
uint64_t proc_for_pid(pid_t pidToFind);
uint64_t task_get_first_thread(uint64_t task_ptr);
uint64_t thread_get_act_context(uint64_t thread_ptr);
uint64_t get_cspr_kern_intr_en(void);
uint64_t get_cspr_kern_intr_dis(void);