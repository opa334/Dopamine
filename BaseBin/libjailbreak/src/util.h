#import <Foundation/Foundation.h>

NSString *prebootPath(NSString *path);

typedef struct __attribute__((__packed__)) _vm_map_flags {
    unsigned int
        /* boolean_t */ wait_for_space:1,         /* Should callers wait for space? */
        /* boolean_t */ wiring_required:1,        /* All memory wired? */
        /* boolean_t */ no_zero_fill:1,           /* No zero fill absent pages */
        /* boolean_t */ mapped_in_other_pmaps:1,  /* has this submap been mapped in maps that use a different pmap */
        /* boolean_t */ switch_protect:1,         /* Protect map from write faults while switched */
        /* boolean_t */ disable_vmentry_reuse:1,  /* All vm entries should keep using newer and higher addresses in the map */
        /* boolean_t */ map_disallow_data_exec:1, /* Disallow execution from data pages on exec-permissive architectures */
        /* boolean_t */ holelistenabled:1,
        /* boolean_t */ is_nested_map:1,
        /* boolean_t */ map_disallow_new_exec:1, /* Disallow new executable code */
        /* boolean_t */ jit_entry_exists:1,
        /* boolean_t */ has_corpse_footprint:1,
        /* boolean_t */ terminated:1,
        /* boolean_t */ is_alien:1,              /* for platform simulation, i.e. PLATFORM_IOS on OSX */
        /* boolean_t */ cs_enforcement:1,        /* code-signing enforcement */
        /* boolean_t */ cs_debugged:1,           /* code-signed but debugged */
        /* boolean_t */ reserved_regions:1,      /* has reserved regions. The map size that userspace sees should ignore these. */
        /* boolean_t */ single_jit:1,            /* only allow one JIT mapping */
        /* boolean_t */ never_faults : 1,        /* only seen in KDK */
        /* reserved */ pad:13;
} vm_map_flags;

int kalloc(uint64_t *addr, uint64_t size);
int kfree(uint64_t addr, uint64_t size);
uint64_t stringKalloc(const char *string);
void stringKFree(const char *string, uint64_t kmem);

bool cs_allow_invalid(uint64_t proc_ptr);
uint64_t ptrauth_utils_sign_blob_generic(uint64_t ptr, uint64_t len_bytes, uint64_t salt, uint64_t flags);
uint64_t kpacda(uint64_t pointer, uint64_t modifier);
uint64_t kptr_sign(uint64_t kaddr, uint64_t pointer, uint16_t salt);
void kwrite_ptr(uint64_t kaddr, uint64_t pointer, uint16_t salt);

void proc_iterate(void (^itBlock)(uint64_t, BOOL*));
uint64_t proc_for_pid(pid_t pidToFind, bool *needsRelease);
int proc_rele(uint64_t proc);
uint64_t proc_get_task(uint64_t proc_ptr);
uint64_t proc_get_pptr(uint64_t proc_ptr);
pid_t proc_get_pid(uint64_t proc_ptr);
uint64_t proc_get_ucred(uint64_t proc_ptr);
void proc_set_ucred(uint64_t proc_ptr, uint64_t ucred_ptr);
uint64_t proc_get_proc_ro(uint64_t proc_ptr);
uint64_t proc_ro_get_ucred(uint64_t proc_ro_ptr);
uint64_t proc_get_text_vnode(uint64_t proc_ptr);
uint64_t proc_get_file_glob_by_file_descriptor(uint64_t proc_ptr, int fd);
uint64_t proc_get_vnode_by_file_descriptor(uint64_t proc_ptr, int fd);
uint32_t proc_get_csflags(uint64_t proc);
void proc_set_csflags(uint64_t proc, uint32_t csflags);
uint32_t proc_get_svuid(uint64_t proc_ptr);
void proc_set_svuid(uint64_t proc_ptr, uid_t svuid);
uint32_t proc_get_svgid(uint64_t proc_ptr);
void proc_set_svgid(uint64_t proc_ptr, uid_t svgid);
uint32_t proc_get_p_flag(uint64_t proc_ptr);
void proc_set_p_flag(uint64_t proc_ptr, uint32_t p_flag);
int proc_set_debugged(uint64_t proc_ptr, bool fully_debugged);
uint64_t self_proc(void);

uint32_t ucred_get_uid(uint64_t ucred_ptr);
int ucred_set_uid(uint64_t ucred_ptr, uint32_t uid);
uint32_t ucred_get_svuid(uint64_t ucred_ptr);
int ucred_set_svuid(uint64_t ucred_ptr, uint32_t svuid);
uint32_t ucred_get_cr_groups(uint64_t ucred_ptr);
int ucred_set_cr_groups(uint64_t ucred_ptr, uint32_t cr_groups);
uint32_t ucred_get_svgid(uint64_t ucred_ptr);
int ucred_set_svgid(uint64_t ucred_ptr, uint32_t svgid);
uint64_t ucred_get_cr_label(uint64_t ucred_ptr);

uint64_t task_get_first_thread(uint64_t task_ptr);
//uint64_t task_get_thread(uint64_t task_ptr, thread_act_t thread);
uint64_t self_thread(void);
uint64_t thread_get_id(uint64_t thread_ptr);
uint64_t thread_get_act_context(uint64_t thread_ptr);
uint64_t task_get_vm_map(uint64_t task_ptr);
void task_set_memory_ownership_transfer(uint64_t task_ptr, uint8_t enabled);
uint64_t self_task(void);

uint64_t vm_map_get_pmap(uint64_t vm_map_ptr);
uint64_t vm_map_get_header(uint64_t vm_map_ptr);
uint64_t vm_map_header_get_first_entry(uint64_t vm_header_ptr);
uint64_t vm_map_entry_get_next_entry(uint64_t vm_entry_ptr);
uint32_t vm_header_get_nentries(uint64_t vm_header_ptr);
void vm_entry_get_range(uint64_t vm_entry_ptr, uint64_t *start_address_out, uint64_t *end_address_out);
void vm_map_iterate_entries(uint64_t vm_map_ptr, void (^itBlock)(uint64_t start, uint64_t end, uint64_t entry, BOOL* stop));
uint64_t vm_map_find_entry(uint64_t vm_map_ptr, uint64_t map_start);
vm_map_flags vm_map_get_flags(uint64_t vm_map_ptr);
void vm_map_set_flags(uint64_t vm_map_ptr, vm_map_flags new_flags);

void vm_map_entry_get_prot(uint64_t entry_ptr, vm_prot_t *prot, vm_prot_t *max_prot);
void vm_map_entry_set_prot(uint64_t entry_ptr, vm_prot_t prot, vm_prot_t max_prot);

void pmap_set_wx_allowed(uint64_t pmap_ptr, bool wx_allowed);
void pmap_set_type(uint64_t pmap_ptr, uint8_t type);
uint64_t pmap_lv2(uint64_t pmap_ptr, uint64_t virt);
uint64_t get_cspr_kern_intr_en(void);
uint64_t get_cspr_kern_intr_dis(void);

uint64_t vnode_get_ubcinfo(uint64_t vnode_ptr);
void ubcinfo_iterate_csblobs(uint64_t ubc_info_ptr, void (^itBlock)(uint64_t, BOOL*));
uint64_t vnode_get_csblob(uint64_t vnode_ptr);
uint64_t vnode_get_data(uint64_t vnode_ptr);
void vnode_set_data(uint64_t vnode_ptr, uint64_t data);
uint16_t vnode_get_type(uint64_t vnode_ptr);
uint32_t vnode_get_id(uint64_t vnode_ptr);
uint64_t vnode_get_mount(uint64_t vnode_ptr);

uint64_t csblob_get_pmap_cs_entry(uint64_t csblob_ptr);

NSMutableDictionary *DEREntitlementsDecode(uint8_t *start, uint8_t *end);
void DEREntitlementsEncode(NSDictionary *entitlements, uint8_t **startOut, uint8_t **endOut);

void OSEntitlements_resign(uint64_t OSEntitlements_ptr);
uint64_t cr_label_get_OSEntitlements(uint64_t cr_label_ptr);
NSData *OSEntitlements_get_cdhash(uint64_t OSEntitlements_ptr);

NSMutableDictionary *OSEntitlements_dump_entitlements(uint64_t OSEntitlements_ptr);
void OSEntitlements_replace_entitlements(uint64_t OSEntitlements_ptr, NSDictionary *newEntitlements);

NSMutableDictionary *vnode_dump_entitlements(uint64_t vnode_ptr);
void vnode_replace_entitlements(uint64_t vnode_ptr, NSDictionary *newEntitlements);
NSMutableDictionary *proc_dump_entitlements(uint64_t proc_ptr);
void proc_replace_entitlements(uint64_t proc_ptr, NSDictionary *entitlements);

int proc_set_debugged_pid(pid_t pid, bool fully_debugged);
pid_t proc_get_ppid(pid_t pid);
NSString *proc_get_path(pid_t pid);
int64_t proc_fix_setuid(pid_t pid);

void run_unsandboxed(void (^block)(void));