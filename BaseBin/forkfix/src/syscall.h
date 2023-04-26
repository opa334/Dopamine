kern_return_t ffsys_vm_protect(vm_map_t target_task, vm_address_t address, vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection);
pid_t ffsys_fork(void);
pid_t ffsys_getpid(void);
int ffsys_pid_suspend(pid_t pid);