#ifndef LJB_UTIL_H
#define LJB_UTIL_H

#include <libroothider/libroothider.h>

#include "info.h"
#include "jbclient_xpc.h"
#include "jbroot.h"
#include <spawn.h>
#include <libunwind.h>

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);
extern int posix_spawnattr_set_uid_np(const posix_spawnattr_t * __restrict, uid_t);
extern int posix_spawnattr_set_gid_np(const posix_spawnattr_t * __restrict, gid_t);

#define min(a, b) (((a) < (b)) ? (a) : (b))
#define max(a, b) (((a) > (b)) ? (a) : (b))

const struct mach_header *get_mach_header(const char *name);
uintptr_t get_mach_vmaddr_slide(const char *name);
bool host_is_arm64e(void);
void proc_iterate(void (^itBlock)(uint64_t, bool*));

uint64_t proc_self(void);
uint64_t task_self(void);
uint64_t vm_map_self(void);
uint64_t pmap_self(void);
uint64_t ttep_self(void);
uint64_t tte_self(void);

uint64_t task_get_ipc_port_table_entry(uint64_t task, mach_port_t port);
uint64_t task_get_ipc_port_object(uint64_t task, mach_port_t port);
uint64_t task_get_ipc_port_kobject(uint64_t task, mach_port_t port);

uint64_t alloc_page_table_unassigned(void);
uint64_t pmap_alloc_page_table(uint64_t pmap, uint8_t level, uint64_t va_start);
int pmap_expand_range(uint64_t pmap, uint64_t vaStart, uint64_t size);
int pmap_map_in_with_flags(uint64_t pmap, uint64_t uaStart, uint64_t paStart, uint64_t size, uint64_t flags);
int pmap_map_in(uint64_t pmap, uint64_t uaStart, uint64_t paStart, uint64_t size);

uint64_t pmap_find_main_binary_code_dir(uint64_t pmap);
uint64_t proc_find_main_binary_code_dir(uint64_t proc);
uint32_t pmap_cs_trust_string_to_int(const char *trustString);

int sign_kernel_thread(uint64_t proc, mach_port_t threadPort);
uint64_t kpacda(uint64_t pointer, uint64_t modifier);
uint64_t kptr_sign(uint64_t kaddr, uint64_t pointer, uint16_t salt);

void proc_allow_all_syscalls(uint64_t proc);
void proc_remove_msg_filter(uint64_t proc);
uint64_t proc_get_vnode_for_fd(uint64_t proc, int fd);
int fd_attach_signature(int fd, fsignatures_t *signature);
void proc_ucred_update(uint64_t proc, uint64_t newUcred);
int proc_ucred_update_content(uint64_t proc, const char *procPath, uid_t uid, gid_t gid, uid_t ruid, gid_t rgid, gid_t groups[NGROUPS_MAX]);

uint64_t vm_page_for_pnum(uint64_t pnum);
uint64_t vm_page_for_pai(uint64_t pai);
uint64_t vm_page_for_pa(uint64_t pa);

void killall(const char *executablePath, int signal);
int libarchive_unarchive(const char *fileToExtract, const char *extractionPath);

void thread_caffeinate_start(void);
void thread_caffeinate_stop(void);

void convert_data_to_hex_string(const void *data, size_t size, char *outBuf);
int convert_hex_string_to_data(const char *string, void *outBuf);

int cmd_wait_for_exit(pid_t pid);
int exec_cmd(const char *binary, ...);
int exec_cmd_nowait(pid_t *pidOut, const char *binary, ...);
int exec_cmd_suspended(pid_t *pidOut, const char *binary, ...);
int exec_cmd_root(const char *binary, ...);
int exec_cmd_env(char **envp, const char *binary, ...);

int jbctl_earlyboot(mach_port_t earlyBootServer, ...);

void walk_backtrace(bool (^block)(int frame_index, unw_word_t pc, unw_word_t offset, const char *symbol_name));

#define exec_cmd_trusted(x, args ...) ({ \
    jbclient_trust_file_by_path(x); \
    int retval; \
    retval = exec_cmd(x, args); \
    retval; \
})

char *boot_manifest_hash(void);

#define prebootUUIDPath(path) ({ \
	static char outPath[PATH_MAX]; \
	strlcpy(outPath, "/private/preboot/", PATH_MAX); \
	strlcat(outPath, boot_manifest_hash(), PATH_MAX); \
	strlcat(outPath, path, PATH_MAX); \
	(outPath); \
})

#define VM_FLAGS_GET_PROT(x)    ((x >> koffsetof(vm_map_entry, flags_prot))    & 0xFULL)
#define VM_FLAGS_GET_MAXPROT(x) ((x >> koffsetof(vm_map_entry, flags_maxprot)) & 0xFULL);
#define VM_FLAGS_SET_PROT(x, p)    x = ((x & ~(0xFULL <<    koffsetof(vm_map_entry, flags_prot))) | (((uint64_t)p) <<    koffsetof(vm_map_entry, flags_prot)))
#define VM_FLAGS_SET_MAXPROT(x, p) x = ((x & ~(0xFULL << koffsetof(vm_map_entry, flags_maxprot))) | (((uint64_t)p) << koffsetof(vm_map_entry, flags_maxprot)))
#define VM_FLAGS_GET_XNU_USER_DEBUG(x) ((bool)((x >> koffsetof(vm_map_entry, flags_xnu_user_debug)) & 0x1))
#define VM_FLAGS_SET_XNU_USER_DEBUG(x, b) x = (x & ~(0x1 << koffsetof(vm_map_entry, flags_xnu_user_debug))) | (((uint64_t)b) << koffsetof(vm_map_entry, flags_xnu_user_debug))


#ifdef __OBJC__
NSString *NSPrebootUUIDPath(NSString *relativePath);
#endif

void JBFixMobilePermissions(void);
bool is_dopamine_app(const char *pathC);

#endif