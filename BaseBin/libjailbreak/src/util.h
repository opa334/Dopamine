#ifndef LJB_UTIL_H
#define LJB_UTIL_H

#include "info.h"

void proc_iterate(void (^itBlock)(uint64_t, bool*));

uint64_t proc_self(void);
uint64_t task_self(void);
uint64_t vm_map_self(void);
uint64_t pmap_self(void);

uint64_t task_get_ipc_port_table_entry(uint64_t task, mach_port_t port);
uint64_t task_get_ipc_port_object(uint64_t task, mach_port_t port);
uint64_t task_get_ipc_port_kobject(uint64_t task, mach_port_t port);

#define JBRootPath(relativePath) ({ static char outPath[PATH_MAX]; strlcpy(outPath, jbinfo(rootPath), PATH_MAX); strlcpy(outPath, relativePath, PATH_MAX); outPath; })

#ifdef __OBJC__
NSString *NSJBRootPath(NSString *relativePath);
#endif

#endif