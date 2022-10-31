//
//  mach.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include <stdio.h>
#include <mach/mach.h>
#include <mach/machine/ndr_def.h>

#include "generated/device.h"

#undef _mach_host_user_

#include "generated/mach_host.h"

#undef mach_task_self

extern mach_port_t mach_task_self(void);
extern kern_return_t mach_msg_trap(mach_msg_header_t *msg, mach_msg_option_t option, mach_msg_size_t send_size, mach_msg_size_t rcv_size, mach_port_name_t rcv_name, mach_msg_timeout_t timeout, mach_port_name_t notify);
extern kern_return_t mach_msg_overwrite_trap(mach_msg_header_t *msg, mach_msg_option_t option, mach_msg_size_t send_size, mach_msg_size_t rcv_size, mach_port_name_t rcv_name, mach_msg_timeout_t timeout, mach_port_name_t notify, mach_msg_header_t *rcv_msg, mach_msg_size_t rcv_limit);
extern mach_port_t mach_reply_port(void);

mach_port_t mach_task_self_;
mach_port_t ioMasterPort;

void mach_init(void) {
    mach_task_self_ = mach_task_self();
    
    host_get_io_main(mach_host_self(), &ioMasterPort);
}

kern_return_t IOMasterPort(mach_port_t bp, mach_port_t *master) {
    return host_get_io_main(mach_host_self(), master);
}

mach_port_t IORegistryEntryFromPath(mach_port_t master, char *path) {
    mach_port_t entry = 0;
    if (io_registry_entry_from_path(master, path, &entry) == KERN_SUCCESS) {
        return entry;
    }
    
    return 0;
}

kern_return_t IOServiceOpen(mach_port_t service, task_port_t owningTask, uint32_t type, mach_port_t *connect) {
    kern_return_t result = KERN_SUCCESS;
    kern_return_t rpcRes = io_service_open_extended(service, owningTask, type, NDR_record, NULL, 0, &result, connect);
    if (rpcRes != KERN_SUCCESS) {
        return rpcRes;
    }
    
    return result;
}

void IOObjectRelease(mach_port_t obj) {
    mach_port_deallocate(mach_task_self_, obj);
}

mach_port_t IOServiceMatchingDescriptor(const char *descriptor) {
    mach_port_t service = 0;
    kern_return_t result = 0;
    kern_return_t kr = io_service_get_matching_service_ool(ioMasterPort, (io_buf_ptr_t) descriptor, (mach_msg_type_number_t) strlen(descriptor) + 1, &result, &service);
    if (kr == KERN_SUCCESS && result == KERN_SUCCESS) {
        return service;
    }
    
    return MACH_PORT_NULL;
}

kern_return_t IOConnectMapMemory(mach_port_t connect, uint32_t memoryType, task_port_t intoTask, mach_vm_address_t *atAddress, mach_vm_size_t *ofSize, uint32_t options) {
    return io_connect_map_memory_into_task(connect, memoryType, intoTask, atAddress, ofSize, options);
}

kern_return_t mach_msg(mach_msg_header_t *msg, mach_msg_option_t option, mach_msg_size_t send_size, mach_msg_size_t rcv_size, mach_port_name_t rcv_name, mach_msg_timeout_t timeout, mach_port_name_t notify) {
    // Apparently, there are two flags to handle: MACH_SEND_INTERRUPT and MACH_RCV_INTERRUPT
    mach_msg_option_t newOpt = option & ~(MACH_SEND_INTERRUPT | MACH_RCV_INTERRUPT);
    
    while (1) {
        kern_return_t kr = mach_msg_trap(msg, newOpt, send_size, rcv_size, rcv_name, timeout, notify);
        if (kr == MACH_SEND_INTERRUPTED && !(option & MACH_SEND_INTERRUPT)) {
            continue;
        } else if (kr == MACH_RCV_INTERRUPTED && !(option & MACH_RCV_INTERRUPT)) {
            newOpt &= ~(MACH_SEND_MSG);
            continue;
        }
        
        return kr;
    }
}

kern_return_t mach_msg_overwrite(mach_msg_header_t *msg, mach_msg_option_t option, mach_msg_size_t send_size, mach_msg_size_t rcv_size, mach_port_name_t rcv_name, mach_msg_timeout_t timeout, mach_port_name_t notify, mach_msg_header_t *rcv_msg, mach_msg_size_t rcv_limit) {
    // Apparently, there are two flags to handle: MACH_SEND_INTERRUPT and MACH_RCV_INTERRUPT
    mach_msg_option_t newOpt = option & ~(MACH_SEND_INTERRUPT | MACH_RCV_INTERRUPT);
    
    while (1) {
        kern_return_t kr = mach_msg_overwrite_trap(msg, newOpt, send_size, rcv_size, rcv_name, timeout, notify, rcv_msg, rcv_limit);
        if (kr == MACH_SEND_INTERRUPTED && !(option & MACH_SEND_INTERRUPT)) {
            continue;
        } else if (kr == MACH_RCV_INTERRUPTED && !(option & MACH_RCV_INTERRUPT)) {
            newOpt &= ~(MACH_SEND_MSG);
            continue;
        }
        
        return kr;
    }
}

void mach_msg_destroy(mach_msg_header_t *header) {
    return; // Do nothing... Not up to spec...
}

mach_port_t replyPort = 0;

mach_port_t mig_get_reply_port(void) {
    if (!replyPort) {
        replyPort = mach_reply_port();
    }
    
    return replyPort;
}

void mig_put_reply_port(mach_port_t port) {
    return;
}

void mig_dealloc_reply_port(mach_port_t port) {
    mach_port_mod_refs(mach_task_self_, port, MACH_PORT_RIGHT_RECEIVE, -1);
    if (replyPort == port) {
        replyPort = 0;
    }
}

boolean_t voucher_mach_msg_set(mach_msg_header_t *msg) {
    return 0;
}
