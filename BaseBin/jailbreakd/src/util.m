#import "util.h"
#import "ppl.h"
#import "pac.h"
#import "jailbreakd.h"

extern const uint8_t *der_decode_plist(CFAllocatorRef allocator, CFTypeRef* output, CFErrorRef *error, const uint8_t *der_start, const uint8_t *der_end);
extern const uint8_t *der_encode_plist(CFTypeRef input, CFErrorRef *error, const uint8_t *der_start, const uint8_t *der_end);
extern size_t der_sizeof_plist(CFPropertyListRef pl, CFErrorRef *error);

uint64_t kalloc(uint64_t size)
{
	uint64_t kalloc_data_external = bootInfo_getSlidUInt64(@"kalloc_data_external");
	return kcall(kalloc_data_external, size, 1, 0, 0, 0, 0, 0, 0);
}

uint64_t kfree(uint64_t addr, uint64_t size)
{
	uint64_t kfree_data_external = bootInfo_getSlidUInt64(@"kfree_data_external");
	return kcall(kfree_data_external, addr, size, 0, 0, 0, 0, 0, 0);
}

bool cs_allow_invalid(uint64_t proc_ptr)
{
    uint64_t cs_allow_invalid = bootInfo_getSlidUInt64(@"cs_allow_invalid");
    return (bool)kcall(cs_allow_invalid, proc_ptr, 0, 0, 0, 0, 0, 0, 0);
}

uint64_t ptrauth_utils_sign_blob_generic(uint64_t ptr, uint64_t len_bytes, uint64_t salt, uint64_t flags)
{
    uint64_t ptrauth_utils_sign_blob_generic = bootInfo_getSlidUInt64(@"ptrauth_utils_sign_blob_generic");
    return kcall(ptrauth_utils_sign_blob_generic, ptr, len_bytes, salt, flags, 0, 0, 0, 0);
}

uint64_t proc_get_task(uint64_t proc_ptr)
{
	return kread_ptr(proc_ptr + 0x10ULL);
}

pid_t proc_get_pid(uint64_t proc_ptr)
{
	return kread32(proc_ptr + 0x68ULL);
}

void proc_iterate(void (^itBlock)(uint64_t, BOOL*))
{
	uint64_t allproc = bootInfo_getSlidUInt64(@"allproc");
    uint64_t proc = allproc;
    while((proc = kread_ptr(proc)))
    {
        BOOL stop = NO;
        itBlock(proc, &stop);
        if(stop == 1) return;
    }
}

uint64_t proc_for_pid(pid_t pidToFind)
{
    __block uint64_t foundProc = 0;

    proc_iterate(^(uint64_t proc, BOOL* stop) {
        pid_t pid = proc_get_pid(proc);
        if(pid == pidToFind)
        {
            foundProc = proc;
            *stop = YES;
        }
    });
    
    return foundProc;
}

uint64_t proc_get_proc_ro(uint64_t proc_ptr)
{
    return kread_ptr(proc_ptr + 0x20);
}

uint64_t proc_ro_get_ucred(uint64_t proc_ro_ptr)
{
    return kread_ptr(proc_ro_ptr + 0x20);
}

uint64_t proc_get_ucred(uint64_t proc_ptr)
{
    if (@available(iOS 15.2, *)) {
        return proc_ro_get_ucred(proc_get_proc_ro(proc_ptr));
    } else {
        return kread_ptr(proc_ptr + 0xD8);
    }
}

uint64_t proc_get_text_vnode(uint64_t proc_ptr)
{
    if (@available(iOS 15.4, *)) {
        return kread_ptr(proc_ptr + 0x350);
    } else {
        return kread_ptr(proc_ptr + 0x358);
    }
}

uint64_t proc_get_vnode_by_file_descriptor(uint64_t proc_ptr, int fd)
{
    uint64_t ofiles_start = kread_ptr(proc_ptr + 0xD8 + 0x20);
    if (!ofiles_start) return 0;
    uint64_t file_proc_ptr = kread_ptr(ofiles_start + (fd * 8));
    if (!file_proc_ptr) return 0;
    uint64_t file_glob_ptr = kread_ptr(file_proc_ptr + 0x10);
    if (!file_glob_ptr) return 0;
    return kread_ptr(file_glob_ptr + 0x38);
}

uint64_t task_get_first_thread(uint64_t task_ptr)
{
	return kread_ptr(task_ptr + 0x60ULL);
}

uint64_t thread_get_act_context(uint64_t thread_ptr)
{
	uint64_t actContextOffset = bootInfo_getUInt64(@"ACT_CONTEXT");
	return kread_ptr(thread_ptr + actContextOffset);
}

uint64_t task_get_vm_map(uint64_t task_ptr)
{
    return kread_ptr(task_ptr + 0x28ULL);
}

uint64_t vm_map_get_pmap(uint64_t vm_map_ptr)
{
    return kread_ptr(vm_map_ptr + bootInfo_getUInt64(@"VM_MAP_PMAP"));
}

void pmap_set_type(uint64_t pmap_ptr, uint8_t type)
{
    uint64_t kernel_el = bootInfo_getUInt64(@"kernel_el");
    uint32_t el2_adjust = (kernel_el == 8) ? 8 : 0;
    kwrite8(pmap_ptr + 0xC8ULL + el2_adjust, type);
}

uint64_t pmap_lv2(uint64_t pmap_ptr, uint64_t virt)
{
    uint64_t ttep = kread64(pmap_ptr + 0x8ULL);
    
    uint64_t table1Off   = (virt >> 36ULL) & 0x7ULL;
    uint64_t table1Entry = physread64(ttep + (8ULL * table1Off));
    if ((table1Entry & 0x3) != 3) {
        return 0;
    }
    
    uint64_t table2 = table1Entry & 0xFFFFFFFFC000ULL;
    uint64_t table2Off = (virt >> 25ULL) & 0x7FFULL;
    uint64_t table2Entry = physread64(table2 + (8ULL * table2Off));
    
    return table2Entry;
}

uint64_t get_cspr_kern_intr_en(void)
{
	uint32_t kernel_el = bootInfo_getUInt64(@"kernel_el");
	return (0x401000 | ((uint32_t)kernel_el));
}

uint64_t get_cspr_kern_intr_dis(void)
{
	uint32_t kernel_el = bootInfo_getUInt64(@"kernel_el");
	return (0x4013c0 | ((uint32_t)kernel_el));
}

uint64_t vnode_get_ubcinfo(uint64_t vnode_ptr)
{
    return kread_ptr(vnode_ptr + 0x78);
}

void ubcinfo_iterate_csblobs(uint64_t ubc_info_ptr, void (^itBlock)(uint64_t, BOOL*))
{
    uint64_t csblobs = kread_ptr(ubc_info_ptr + 0x50);
    while(csblobs != 0)
    {
        BOOL stop = NO;
        itBlock(csblobs, &stop);
        if(stop) return;
        csblobs = kread_ptr(csblobs);
    }
}

uint64_t csblob_get_pmap_cs_entry(uint64_t csblob_ptr)
{
    return kread_ptr(csblob_ptr + 0xB0);
}

uint64_t ucred_get_cr_label(uint64_t ucred_ptr)
{
    return kread_ptr(ucred_ptr + 0x78);
}

uint64_t cr_label_get_OSEntitlements(uint64_t cr_label_ptr)
{
    return kread_ptr(cr_label_ptr + 0x8);
}

NSData *OSEntitlements_get_cdhash(uint64_t OSEntitlements_ptr)
{
    uint8_t cdhash[20];
    kreadbuf(OSEntitlements_ptr + 0x10, cdhash, 20);
    NSData* cdHashData = [NSData dataWithBytes:cdhash length:20];
    return cdHashData;
}

NSMutableDictionary *CEQueryContext_dump_entitlements(uint64_t CEQueryContext_ptr)
{
    uint64_t der_start = kread_ptr(CEQueryContext_ptr + 0x18);
    uint64_t der_end = kread_ptr(CEQueryContext_ptr + 0x20);

    uint64_t der_len = der_end - der_start;
    uint8_t *us_der_start = malloc(der_len);
    kreadbuf(der_start, us_der_start, der_len);
    uint8_t *us_der_end = us_der_start + der_len;

    CFTypeRef plist = NULL;
    CFErrorRef err;
    der_decode_plist(NULL, &plist, &err, us_der_start, us_der_end);
    free(us_der_start);

    if (plist) {
        if (CFGetTypeID(plist) == CFDictionaryGetTypeID()) {
            NSMutableDictionary *plistDict = (__bridge_transfer id)plist;
            return plistDict;
        }
        else if (CFGetTypeID(plist) == CFDataGetTypeID()) {
            // This code path is probably never used, but I decided to implement it anyways
            // Because I saw in disassembly that there is a possibility for this to return data
            NSData *plistData = (__bridge_transfer id)plist;
            NSPropertyListFormat format;
            NSError *decodeError;
            NSMutableDictionary *result = ((NSDictionary *)[NSPropertyListSerialization propertyListWithData:plistData options:0 format:&format error:&decodeError]).mutableCopy;
            if (result) {
                return result;
            }
            else {
                NSLog(@"decode error: %@\n", decodeError);
            }
        }
    }

    return nil;
}

NSMutableDictionary *OSEntitlements_dump_entitlements(uint64_t OSEntitlements_ptr)
{
    uint64_t CEQueryContext = OSEntitlements_ptr + 0x28;
    return CEQueryContext_dump_entitlements(CEQueryContext);
}

void CEQueryContext_replace_entitlements(uint64_t CEQueryContext_ptr, NSDictionary *newEntitlements)
{
    size_t der_size = der_sizeof_plist((__bridge CFDictionaryRef)newEntitlements, NULL);
    uint8_t *der_start = malloc(der_size);
    uint8_t *der_end = der_start + der_size;
    der_encode_plist((__bridge CFDictionaryRef)newEntitlements, NULL, der_start, der_end);

    uint64_t old_kern_der_start = kread_ptr(CEQueryContext_ptr + 0x18);
    uint64_t old_kern_der_end = kread_ptr(CEQueryContext_ptr + 0x20);
    uint64_t old_kern_der_size = old_kern_der_end - old_kern_der_start;
    kfree(old_kern_der_start, old_kern_der_size);

    uint64_t kern_der_start = kalloc(der_size);
    uint64_t kern_der_end = kern_der_start + der_size;
    kwritebuf(kern_der_start, der_start, der_size);

    kwrite64(CEQueryContext_ptr + 0x18, kern_der_start);
    kwrite64(CEQueryContext_ptr + 0x20, kern_der_end);
}

void resign_OSEntitlements(uint64_t OSEntitlements_ptr)
{
    uint64_t signature = ptrauth_utils_sign_blob_generic(OSEntitlements_ptr + 0x10, 0x60, 0xBD9D, 1);
    kwrite64(OSEntitlements_ptr + 0x70, signature);
}

void OSEntitlements_replace_entitlements(uint64_t OSEntitlements_ptr, NSDictionary *newEntitlements)
{
    uint64_t CEQueryContext = OSEntitlements_ptr + 0x28;
    CEQueryContext_replace_entitlements(CEQueryContext, newEntitlements);
    resign_OSEntitlements(OSEntitlements_ptr);
}

NSMutableDictionary *pmap_cs_entry_dump_entitlements(uint64_t pmap_cs_entry_ptr)
{
    uint64_t CEQueryContext = kread_ptr(pmap_cs_entry_ptr + 0x88);
    return CEQueryContext_dump_entitlements(CEQueryContext);
}

void pmap_cs_entry_replace_entitlements(uint64_t pmap_cs_entry_ptr, NSDictionary *newEntitlements)
{
    uint64_t CEQueryContext = kread_ptr(pmap_cs_entry_ptr + 0x88);
    CEQueryContext_replace_entitlements(CEQueryContext, newEntitlements);
}

NSMutableDictionary *vnode_dump_entitlements(uint64_t vnode_ptr)
{
    uint64_t ubc_info_ptr = vnode_get_ubcinfo(vnode_ptr);
    if (!ubc_info_ptr) return nil;
    
   __block NSMutableDictionary *outDict = nil;
    ubcinfo_iterate_csblobs(ubc_info_ptr, ^(uint64_t csblob, BOOL *stop)
    {
        uint64_t pmap_cs_entry_ptr = csblob_get_pmap_cs_entry(csblob);
        if (!pmap_cs_entry_ptr) return;
        outDict = pmap_cs_entry_dump_entitlements(pmap_cs_entry_ptr);
        if (outDict) *stop = YES;
    });
    return outDict;
}

void vnode_replace_entitlements(uint64_t vnode_ptr, NSDictionary *newEntitlements)
{
    uint64_t ubc_info_ptr = vnode_get_ubcinfo(vnode_ptr);
    if (!ubc_info_ptr) return;
    ubcinfo_iterate_csblobs(ubc_info_ptr, ^(uint64_t csblob, BOOL *stop)
    {
        uint64_t pmap_cs_entry_ptr = csblob_get_pmap_cs_entry(csblob);
        if (!pmap_cs_entry_ptr) return;
        pmap_cs_entry_replace_entitlements(pmap_cs_entry_ptr, newEntitlements);
        *stop = YES;
    });
}

NSMutableDictionary *proc_dump_entitlements(uint64_t proc_ptr)
{
    uint64_t ucred_ptr = proc_get_ucred(proc_ptr);
    uint64_t cr_label_ptr = ucred_get_cr_label(ucred_ptr);
    uint64_t OSEntitlements_ptr = cr_label_get_OSEntitlements(cr_label_ptr);
    return OSEntitlements_dump_entitlements(OSEntitlements_ptr);
}

void proc_replace_entitlements(uint64_t proc_ptr, NSDictionary *newEntitlements)
{
    uint64_t ucred_ptr = proc_get_ucred(proc_ptr);
    uint64_t cr_label_ptr = ucred_get_cr_label(ucred_ptr);
    uint64_t OSEntitlements_ptr = cr_label_get_OSEntitlements(cr_label_ptr);

    // Also apply changes on vnode
    uint64_t text_vnode = proc_get_text_vnode(proc_ptr);
    vnode_replace_entitlements(text_vnode, newEntitlements);

    OSEntitlements_replace_entitlements(OSEntitlements_ptr, newEntitlements);
}