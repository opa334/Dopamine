#ifndef LJB_UTIL_H
#define LJB_UTIL_H

#include "info.h"

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

int exec_cmd(const char *binary, ...);

#define JBRootPath(relativePath) ({ static char outPath[PATH_MAX]; strlcat(outPath, jbinfo(rootPath), PATH_MAX); strlcat(outPath, relativePath, PATH_MAX); outPath; })

#ifdef __OBJC__
NSString *NSJBRootPath(NSString *relativePath);
#endif

#endif