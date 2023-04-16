kern_return_t ffsys_vm_protect(vm_map_t target_task, vm_address_t address, vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection);
pid_t ffsys_fork(void);
void ffsys_kill(pid_t pid, int signal);
pid_t ffsys_getpid(void);