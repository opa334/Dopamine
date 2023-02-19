//
//  includeme.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef includeme_h
#define includeme_h

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>
#include <ptrauth.h>

// SpawnDrv/kexploitd helper functions
#define DBG_DK_FUNC(id)      ptrauth_sign_unauthenticated((void*)(0x4142434400ULL + (id * 4ULL)), ptrauth_key_function_pointer, 0)
#define DBG_EXPLOIT_FUNC(id) ptrauth_sign_unauthenticated((void*)(0x4841585800ULL + (id * 4ULL)), ptrauth_key_function_pointer, 0)

#define DBG_DK_FUNC_CHECKIN       DBG_DK_FUNC(0)
#define DBG_DK_FUNC_NOTIFY        DBG_DK_FUNC(1)
#define DBG_DK_FUNC_GET_PCI_SIZE  DBG_DK_FUNC(2)

#define DBG_GETOFFSETS_FUNC         DBG_EXPLOIT_FUNC(0)
#define DBG_KRW_READY_FUNC          DBG_EXPLOIT_FUNC(1)
#define DBG_SET_FAULT_HNDLR         DBG_EXPLOIT_FUNC(2)
#define DBG_GET_REQUEST             DBG_EXPLOIT_FUNC(3)
#define DBG_SEND_REPLY              DBG_EXPLOIT_FUNC(4)
// #define DBG_COPYOUT_PORTS        DBG_EXPLOIT_FUNC(5)
#define DBG_WRITE_BOOT_INFO_UINT64  DBG_EXPLOIT_FUNC(6)
#define DBG_WRITE_BOOT_INFO_DATA    DBG_EXPLOIT_FUNC(7)

// Debug stuff
#define DBGPRINT_ADDRVAR(var) printf("[DBG] %s: %s @ %p\n", __func__, #var, (void*) var)
#define DBGPRINT_VAR(var)     printf("[DBG] %s: %s: %p\n", __func__, #var, (void*) (uint64_t) var)

// Did I mention that I love Swift?
#define guard(cond) if (__builtin_expect(!!(cond), 1)) {}

#define MEMORY_BARRIER asm volatile("dmb sy");

extern void status_update(const char *status);

#endif /* includeme_h */
