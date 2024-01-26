#ifndef LJB_UTIL_H
#define LJB_UTIL_H

#include "info.h"
#include "jbclient_xpc.h"

#define min(a, b) (((a) < (b)) ? (a) : (b))
#define max(a, b) (((a) > (b)) ? (a) : (b))

#define L1_BLOCK_SIZE 0x1000000000
#define L1_BLOCK_MASK (L1_BLOCK_SIZE-1)
#define L2_BLOCK_SIZE 0x2000000
#define L2_BLOCK_PAGECOUNT (L2_BLOCK_SIZE / PAGE_SIZE)
#define L2_BLOCK_MASK (L2_BLOCK_SIZE-1)

void proc_iterate(void (^itBlock)(uint64_t, bool*));

uint64_t proc_self(void);
uint64_t task_self(void);
uint64_t vm_map_self(void);
uint64_t pmap_self(void);

uint64_t task_get_ipc_port_table_entry(uint64_t task, mach_port_t port);
uint64_t task_get_ipc_port_object(uint64_t task, mach_port_t port);
uint64_t task_get_ipc_port_kobject(uint64_t task, mach_port_t port);

uint64_t alloc_page_table_unassigned(void);
uint64_t pmap_alloc_page_table(uint64_t pmap, uint64_t va);

void thread_caffeinate_start(void);
void thread_caffeinate_stop(void);

int exec_cmd(const char *binary, ...);
#define exec_cmd_trusted(x, args ...) ({ \
    jbclient_trust_binary(x); \
    int retval; \
    retval = exec_cmd(x, args); \
    retval; \
})

#define JBRootPath(path) ({ \
	static char outPath[PATH_MAX]; \
	strlcpy(outPath, jbinfo(rootPath), PATH_MAX); \
	strlcat(outPath, path, PATH_MAX); \
	(outPath); \
})


#define VM_FLAGS_GET_PROT(x)    ((x >>  7) & 0xFULL)
#define VM_FLAGS_GET_MAXPROT(x) ((x >> 11) & 0xFULL);
#define VM_FLAGS_SET_PROT(x, p)    x = ((x & ~(0xFULL <<  7)) | (((uint64_t)p) <<  7))
#define VM_FLAGS_SET_MAXPROT(x, p) x = ((x & ~(0xFULL << 11)) | (((uint64_t)p) << 11))

#ifdef __OBJC__
NSString *NSJBRootPath(NSString *relativePath);
#endif

#endif