#import "util.h"
#import "pplrw.h"
#import "kcall.h"
#import "boot_info.h"
#import "signatures.h"
#import "log.h"
#import <libproc.h>
#import <libproc_private.h>
#import <IOKit/IOKitLib.h>

#define P_SUGID 0x00000100

extern const uint8_t *der_decode_plist(CFAllocatorRef allocator, CFTypeRef* output, CFErrorRef *error, const uint8_t *der_start, const uint8_t *der_end);
extern const uint8_t *der_encode_plist(CFTypeRef input, CFErrorRef *error, const uint8_t *der_start, const uint8_t *der_end);
extern size_t der_sizeof_plist(CFPropertyListRef pl, CFErrorRef *error);

NSString *prebootPath(NSString *path)
{
	static NSString *sPrebootPrefix = nil;
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		NSMutableString* bootManifestHashStr;
		io_registry_entry_t registryEntry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen");
		if (registryEntry) {
			CFDataRef bootManifestHash = (CFDataRef)IORegistryEntryCreateCFProperty(registryEntry, CFSTR("boot-manifest-hash"), kCFAllocatorDefault, 0);
			if (bootManifestHash) {
				const UInt8* buffer = CFDataGetBytePtr(bootManifestHash);
				bootManifestHashStr = [NSMutableString stringWithCapacity:(CFDataGetLength(bootManifestHash) * 2)];
				for (CFIndex i = 0; i < CFDataGetLength(bootManifestHash); i++) {
					[bootManifestHashStr appendFormat:@"%02X", buffer[i]];
				}
				CFRelease(bootManifestHash);
			}
		}

		if (bootManifestHashStr) {
			NSString *activePrebootPath = [@"/private/preboot/" stringByAppendingPathComponent:bootManifestHashStr];
			NSArray *subItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:activePrebootPath error:nil];
			for (NSString *subItem in subItems) {
				if ([subItem hasPrefix:@"jb-"]) {
					sPrebootPrefix = [[activePrebootPath stringByAppendingPathComponent:subItem] stringByAppendingPathComponent:@"procursus"];
					break;
				}
			}
		}
		else {
			sPrebootPrefix = @"/var/jb";
		}
	});

	if (path) {
		return [sPrebootPrefix stringByAppendingPathComponent:path];
	}
	else {
		return sPrebootPrefix;
	}
}

int kalloc(uint64_t *addr, uint64_t size)
{
	uint64_t kalloc_data_external = bootInfo_getSlidUInt64(@"kalloc_data_external");
	uint64_t allocation = kcall(kalloc_data_external, 2, (uint64_t[]){size, 1});
	if (allocation != 0) {
		if (addr) *addr = allocation;
		return 0;
	}
	return 1;
}

int kfree(uint64_t addr, uint64_t size)
{
	uint64_t kfree_data_external = bootInfo_getSlidUInt64(@"kfree_data_external");
	return (int)kcall(kfree_data_external, 3, (uint64_t[]){addr, size});
}

uint64_t stringKalloc(const char *string)
{
	uint64_t stringLen = strlen(string) + 1;
	uint64_t stringInKmem = 0;
	if (kalloc(&stringInKmem, stringLen) == 0) {
		kwritebuf(stringInKmem, string, stringLen);
		return stringInKmem;
	}
	return 0;
}

void stringKFree(const char *string, uint64_t kmem)
{
	kfree(kmem, strlen(string)+1);
}

/*bool cs_allow_invalid(uint64_t proc_ptr)
{
	uint64_t cs_allow_invalid = bootInfo_getSlidUInt64(@"cs_allow_invalid");
	return (bool)kcall(cs_allow_invalid, 1, (uint64_t[]){proc_ptr});
}

uint64_t ptrauth_utils_sign_blob_generic(uint64_t ptr, uint64_t len_bytes, uint64_t salt, uint64_t flags)
{
	uint64_t ptrauth_utils_sign_blob_generic = bootInfo_getSlidUInt64(@"ptrauth_utils_sign_blob_generic");
	return kcall(ptrauth_utils_sign_blob_generic, 4, (uint64_t[]){ptr, len_bytes, salt, flags});
}*/

uint64_t kpacda(uint64_t pointer, uint64_t modifier)
{
	uint64_t pacda_gadget = bootInfo_getSlidUInt64(@"pacda_gadget");
	/*
	|------- GADGET -------|
	| cmp x1, #0		   |
	| pacda x1, x9         |
	| str x9, [x8]         |
	| csel x9, xzr, x1, eq |
	| ret                  |
	|----------------------|
	*/

	uint64_t outputAllocation = 0;
	if (kalloc(&outputAllocation, 0x8) != 0) return 0;
	KcallThreadState threadState = { 0 };
	threadState.pc = pacda_gadget;
	threadState.x[1] = pointer;
	threadState.x[9] = modifier;
	threadState.x[8] = outputAllocation;
	kcall_with_thread_state(threadState);
	uint64_t sign = kread64(outputAllocation);
	kfree(outputAllocation, 0x8);
	return sign;
}

uint64_t kptr_sign(uint64_t kaddr, uint64_t pointer, uint16_t salt)
{
	extern uint64_t xpaci(uint64_t a);
	uint64_t modifier = (kaddr & 0xffffffffffff) | ((uint64_t)salt << 48);
	return kpacda(xpaci(pointer), modifier);
}

void kwrite_ptr(uint64_t kaddr, uint64_t pointer, uint16_t salt)
{
	kwrite64(kaddr, kptr_sign(kaddr, pointer, salt));
}

uint64_t proc_get_task(uint64_t proc_ptr)
{
	return kread_ptr(proc_ptr + 0x10);
}

pid_t proc_get_pid(uint64_t proc_ptr)
{
	return kread32(proc_ptr + 0x68);
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

uint64_t proc_for_pid(pid_t pidToFind, bool *needsRelease)
{
	__block uint64_t foundProc = 0;

	if (gKCallStatus == kKcallStatusFinalized) {
		foundProc = kcall(bootInfo_getSlidUInt64(@"proc_find"), 1, (uint64_t[]){pidToFind});
		if (needsRelease) *needsRelease = foundProc != 0;
	}
	else {
		proc_iterate(^(uint64_t proc, BOOL* stop) {
			pid_t pid = proc_get_pid(proc);
			if(pid == pidToFind)
			{
				foundProc = proc;
				*stop = YES;
			}
		});
		if (needsRelease) *needsRelease = false;
	}

	return foundProc;
}

int proc_rele(uint64_t proc)
{
	if (!proc || gKCallStatus != kKcallStatusFinalized) return -1;
	return kcall(bootInfo_getSlidUInt64(@"proc_rele"), 1, (uint64_t[]){proc});
}

uint64_t proc_get_proc_ro(uint64_t proc_ptr)
{
	return kread_ptr(proc_ptr + 0x20);
}

uint64_t proc_ro_get_ucred(uint64_t proc_ro_ptr)
{
	return kread_ptr(proc_ro_ptr + 0x20);
}

void proc_ro_set_ucred(uint64_t proc_ro_ptr, uint64_t ucred_ptr)
{
	kwrite64(proc_ro_ptr + 0x20, ucred_ptr);
}

uint64_t proc_get_ucred(uint64_t proc_ptr)
{
	if (@available(iOS 15.2, *)) {
		return proc_ro_get_ucred(proc_get_proc_ro(proc_ptr));
	} else {
		return kread_ptr(proc_ptr + 0xD8);
	}
}

void proc_set_ucred(uint64_t proc_ptr, uint64_t ucred_ptr)
{
	if (@available(iOS 15.2, *)) {
		proc_ro_set_ucred(proc_get_proc_ro(proc_ptr), ucred_ptr);
	} else {
		kwrite_ptr(proc_ptr + 0xD8, ucred_ptr, 0x84E8);
	}
}

uint64_t proc_get_text_vnode(uint64_t proc_ptr)
{
	if (@available(iOS 15.4, *)) {
		return kread_ptr(proc_ptr + 0x350);
	}
	if (@available(iOS 15.2, *)) {
		return kread_ptr(proc_ptr + 0x358);
	}
	else {
		return kread_ptr(proc_ptr + 0x2A8);
	}
}

uint64_t proc_get_file_glob_by_file_descriptor(uint64_t proc_ptr, int fd)
{
	uint64_t proc_fd = 0;
	if (@available(iOS 15.2, *)) {
		proc_fd = proc_ptr + 0xD8;
	}
	else {
		proc_fd = proc_ptr + 0xE0;
	}
	uint64_t ofiles_start = kread_ptr(proc_fd + 0x20);
	if (!ofiles_start) return 0;
	uint64_t file_proc_ptr = kread_ptr(ofiles_start + (fd * 8));
	if (!file_proc_ptr) return 0;
	return kread_ptr(file_proc_ptr + 0x10);
}

uint64_t proc_get_vnode_by_file_descriptor(uint64_t proc_ptr, int fd)
{
	uint64_t file_glob_ptr = proc_get_file_glob_by_file_descriptor(proc_ptr, fd);
	if (!file_glob_ptr) return 0;
	return kread_ptr(file_glob_ptr + 0x38);
}

/*uint32_t proc_get_csflags(uint64_t proc)
{
	if (@available(iOS 15.2, *)) {
		uint64_t proc_ro = proc_get_proc_ro(proc);
		return kread32(proc_ro + 0x1C);
	}
	else {
		// TODO
		return 0;
	}
}

void proc_set_csflags(uint64_t proc, uint32_t csflags)
{
	if (@available(iOS 15.2, *)) {
		uint64_t proc_ro = proc_get_proc_ro(proc);
		kwrite32(proc_ro + 0x1C, csflags);
	}
	else {
		// TODO
	}
}*/

uint32_t proc_get_svuid(uint64_t proc_ptr)
{
	if (@available(iOS 15.2, *)) {
		return kread32(proc_ptr + 0x44);
	}
	else {
		return kread32(proc_ptr + 0x3C);
	}
}

void proc_set_svuid(uint64_t proc_ptr, uid_t svuid)
{
	if (@available(iOS 15.2, *)) {
		kwrite32(proc_ptr + 0x44, svuid);
	}
	else {
		kwrite32(proc_ptr + 0x3C, svuid);
	}
}

uint32_t proc_get_svgid(uint64_t proc_ptr)
{
	if (@available(iOS 15.2, *)) {
		return kread32(proc_ptr + 0x48);
	}
	else {
		return kread32(proc_ptr + 0x40);
	}
}

void proc_set_svgid(uint64_t proc_ptr, uid_t svgid)
{
	if (@available(iOS 15.2, *)) {
		kwrite32(proc_ptr + 0x48, svgid);
	}
	else {
		kwrite32(proc_ptr + 0x40, svgid);
	}
}

uint32_t proc_get_p_flag(uint64_t proc_ptr)
{
	if (@available(iOS 15.2, *)) {
		return kread32(proc_ptr + 0x264); // ref to this at the beginning of __mac_mount (& 4)
	}
	else {
		return kread32(proc_ptr + 0x1BC);
	}
}

void proc_set_p_flag(uint64_t proc_ptr, uint32_t p_flag)
{
	if (@available(iOS 15.2, *)) {
		kwrite32(proc_ptr + 0x264, p_flag);
	}
	else {
		kwrite32(proc_ptr + 0x1BC, p_flag);
	}
}

uint64_t self_proc(void)
{
	static uint64_t gSelfProc = 0;
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		bool needsRelease = false;
		gSelfProc = proc_for_pid(getpid(), &needsRelease);
		if (needsRelease) {
			// decrement ref count again, we assume self_proc will exist for the whole lifetime of this process
			proc_rele(gSelfProc);
		}
	});
	return gSelfProc;
}

uint32_t ucred_get_uid(uint64_t ucred_ptr)
{
	uint64_t cr_posix_ptr = ucred_ptr + 0x18;
	return kread32(cr_posix_ptr + 0x0);
}

int ucred_set_uid(uint64_t ucred_ptr, uint32_t uid)
{
	uint64_t cr_posix_ptr = ucred_ptr + 0x18;
	return kwrite32(cr_posix_ptr + 0x0, uid);
}

uint32_t ucred_get_svuid(uint64_t ucred_ptr)
{
	uint64_t cr_posix_ptr = ucred_ptr + 0x18;
	return kread32(cr_posix_ptr + 0x8);
}

int ucred_set_svuid(uint64_t ucred_ptr, uint32_t svuid)
{
	uint64_t cr_posix_ptr = ucred_ptr + 0x18;
	return kwrite32(cr_posix_ptr + 0x8, svuid);
}

uint32_t ucred_get_cr_groups(uint64_t ucred_ptr)
{
	uint64_t cr_posix_ptr = ucred_ptr + 0x18;
	return kread32(cr_posix_ptr + 0x10);
}

int ucred_set_cr_groups(uint64_t ucred_ptr, uint32_t cr_groups)
{
	uint64_t cr_posix_ptr = ucred_ptr + 0x18;
	return kwrite32(cr_posix_ptr + 0x10, cr_groups);
}

uint32_t ucred_get_svgid(uint64_t ucred_ptr)
{
	uint64_t cr_posix_ptr = ucred_ptr + 0x18;
	return kread32(cr_posix_ptr + 0x54);
}

int ucred_set_svgid(uint64_t ucred_ptr, uint32_t svgid)
{
	uint64_t cr_posix_ptr = ucred_ptr + 0x18;
	return kwrite32(cr_posix_ptr + 0x54, svgid);
}

uint64_t ucred_get_cr_label(uint64_t ucred_ptr)
{
	return kread_ptr(ucred_ptr + 0x78);
}

uint64_t task_get_first_thread(uint64_t task_ptr)
{
	return kread_ptr(task_ptr + 0x60);
}

uint64_t thread_get_act_context(uint64_t thread_ptr)
{
	uint64_t actContextOffset = bootInfo_getUInt64(@"ACT_CONTEXT");
	return kread_ptr(thread_ptr + actContextOffset);
}

uint64_t task_get_vm_map(uint64_t task_ptr)
{
	return kread_ptr(task_ptr + 0x28);
}

uint64_t self_task(void)
{
	static uint64_t gSelfTask = 0;
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		gSelfTask = proc_get_task(self_proc());
	});
	return gSelfTask;
}

uint64_t vm_map_get_pmap(uint64_t vm_map_ptr)
{
	return kread_ptr(vm_map_ptr + bootInfo_getUInt64(@"VM_MAP_PMAP"));
}

uint64_t vm_map_get_header(uint64_t vm_map_ptr)
{
	return vm_map_ptr + 0x10;
}

uint64_t vm_map_header_get_first_entry(uint64_t vm_header_ptr)
{
	return kread_ptr(vm_header_ptr + 0x8);
}

uint64_t vm_map_entry_get_next_entry(uint64_t vm_entry_ptr)
{
	return kread_ptr(vm_entry_ptr + 0x8);
}

uint32_t vm_header_get_nentries(uint64_t vm_header_ptr)
{
	return kread32(vm_header_ptr + 0x20);
}

void vm_entry_get_range(uint64_t vm_entry_ptr, uint64_t *start_address_out, uint64_t *end_address_out)
{
	uint64_t range[2];
	kreadbuf(vm_entry_ptr + 0x10, &range[0], sizeof(range));
	if (start_address_out) *start_address_out = range[0];
	if (end_address_out) *end_address_out = range[1];
}

void vm_map_iterate_entries(uint64_t vm_map_ptr, void (^itBlock)(uint64_t start, uint64_t end, uint64_t entry, BOOL *stop))
{
	uint64_t header = vm_map_get_header(vm_map_ptr);
	uint64_t entry = vm_map_header_get_first_entry(header);
	uint64_t numEntries = vm_header_get_nentries(header);

	while (entry != 0 && numEntries > 0) {
		uint64_t start = 0, end = 0;
		vm_entry_get_range(entry, &start, &end);

		BOOL stop = NO;
		itBlock(start, end, entry, &stop);
		if (stop) break;

		entry = vm_map_entry_get_next_entry(entry);
		numEntries--;
	}
}

uint64_t vm_map_find_entry(uint64_t vm_map_ptr, uint64_t address)
{
	__block uint64_t found_entry = 0;
	vm_map_iterate_entries(vm_map_ptr, ^(uint64_t start, uint64_t end, uint64_t entry, BOOL *stop) {
		if (address >= start && address < end) {
			found_entry = entry;
			*stop = YES;
		}
	});
	return found_entry;
}

#define FLAGS_PROT_SHIFT    7
#define FLAGS_MAXPROT_SHIFT 11
//#define FLAGS_PROT_MASK     0xF << FLAGS_PROT_SHIFT
//#define FLAGS_MAXPROT_MASK  0xF << FLAGS_MAXPROT_SHIFT
#define FLAGS_PROT_MASK    0x780
#define FLAGS_MAXPROT_MASK 0x7800

void vm_map_entry_get_prot(uint64_t entry_ptr, vm_prot_t *prot, vm_prot_t *max_prot)
{
	uint64_t flags = kread64(entry_ptr + 0x48);
	if (prot) *prot = (flags >> FLAGS_PROT_SHIFT) & 0xF;
	if (max_prot) *max_prot = (flags >> FLAGS_MAXPROT_SHIFT) & 0xF;
}

void vm_map_entry_set_prot(uint64_t entry_ptr, vm_prot_t prot, vm_prot_t max_prot)
{
	uint64_t flags = kread64(entry_ptr + 0x48);
	uint64_t new_flags = flags;
	new_flags = (new_flags & ~FLAGS_PROT_MASK) | ((uint64_t)prot << FLAGS_PROT_SHIFT);
	new_flags = (new_flags & ~FLAGS_MAXPROT_MASK) | ((uint64_t)max_prot << FLAGS_MAXPROT_SHIFT);
	if (new_flags != flags) {
		kwrite64(entry_ptr + 0x48, new_flags);
	}
}

void pmap_set_wx_allowed(uint64_t pmap_ptr, bool wx_allowed)
{
	uint64_t kernel_el = bootInfo_getUInt64(@"kernel_el");
	uint32_t el2_adjust = (kernel_el == 8) ? 8 : 0;
	kwrite8(pmap_ptr + 0xC2 + el2_adjust, wx_allowed);
}

void pmap_set_type(uint64_t pmap_ptr, uint8_t type)
{
	uint64_t kernel_el = bootInfo_getUInt64(@"kernel_el");
	uint32_t el2_adjust = (kernel_el == 8) ? 8 : 0;
	kwrite8(pmap_ptr + 0xC8 + el2_adjust, type);
}

uint64_t pmap_lv2(uint64_t pmap_ptr, uint64_t virt)
{
	uint64_t ttep = kread64(pmap_ptr + 0x8);
	
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
	if (@available(iOS 15.2, *)) {
		return kread_ptr(csblob_ptr + 0xB0);
	}
	else {
		return kread_ptr(csblob_ptr + 0xC0);
	}
}

/*NSMutableDictionary *DEREntitlementsDecode(uint8_t *start, uint8_t *end)
{
	if (!start || !end) return nil;
	if (start == end) return nil;

	CFTypeRef plist = NULL;
	CFErrorRef err;
	der_decode_plist(NULL, &plist, &err, start, end);

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
			if (!result) {
				JBLogError("Error decoding DER: %s", decodeError.description.UTF8String);
			}
			return result;
		}
	}
	return nil;
}

void DEREntitlementsEncode(NSDictionary *entitlements, uint8_t **startOut, uint8_t **endOut)
{
	size_t der_size = der_sizeof_plist((__bridge CFDictionaryRef)entitlements, NULL);
	uint8_t *der_start = malloc(der_size);
	uint8_t *der_end = der_start + der_size;
	der_encode_plist((__bridge CFDictionaryRef)entitlements, NULL, der_start, der_end);
	if (startOut) *startOut = der_start;
	if (endOut) *endOut = der_end;
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

	NSMutableDictionary *entitlements = DEREntitlementsDecode(us_der_start, us_der_end);
	free(us_der_start);
	return entitlements;
}

NSMutableDictionary *OSEntitlements_dump_entitlements(uint64_t OSEntitlements_ptr)
{
	uint64_t CEQueryContext = OSEntitlements_ptr + 0x28;
	return CEQueryContext_dump_entitlements(CEQueryContext);
}

void copyEntitlementsToKernelMemory(NSDictionary *entitlements, uint64_t *out_kern_der_start, uint64_t *out_kern_der_end)
{
	uint8_t *der_start = NULL, *der_end = NULL;
	DEREntitlementsEncode(entitlements, &der_start, &der_end);
	uint64_t der_size = der_end - der_start;

	uint64_t kern_der_start = kalloc(der_size); // XXX: use proper zone for this allocation
	uint64_t kern_der_end = kern_der_start + der_size;
	kwritebuf(kern_der_start, der_start, der_size);

	if (out_kern_der_start) *out_kern_der_start = kern_der_start;
	if (out_kern_der_end) *out_kern_der_end = kern_der_end;
}

void CEQueryContext_replace_entitlements(uint64_t CEQueryContext_ptr, NSDictionary *newEntitlements)
{
	uint64_t kern_der_start = 0, kern_der_end = 0;
	copyEntitlementsToKernelMemory(newEntitlements, &kern_der_start, &kern_der_end);

	//uint64_t old_kern_der_start = kread_ptr(CEQueryContext_ptr + 0x18);
	//uint64_t old_kern_der_end = kread_ptr(CEQueryContext_ptr + 0x20);
	//uint64_t old_kern_der_size = old_kern_der_end - old_kern_der_start;
	//kfree(old_kern_der_start, old_kern_der_size);

	kwrite64(CEQueryContext_ptr + 0x18, kern_der_start);
	kwrite64(CEQueryContext_ptr + 0x20, kern_der_end);
}

void OSEntitlements_resign(uint64_t OSEntitlements_ptr)
{
	uint64_t signature = ptrauth_utils_sign_blob_generic(OSEntitlements_ptr + 0x10, 0x60, 0xBD9D, 1);
	kwrite64(OSEntitlements_ptr + 0x70, signature);
}

// TODO: Remove??
void cr_label_replace_entitlements(uint64_t cr_label_ptr, NSDictionary *newEntitlements, uint64_t csblob)
{
	uint64_t kern_der_start = 0, kern_der_end = 0;
	copyEntitlementsToKernelMemory(newEntitlements, &kern_der_start, &kern_der_end);

	uint64_t fakeCERValidationResult = kalloc(0x18);
	kwrite64(fakeCERValidationResult + 0x00, 2); // version
	kwrite64(fakeCERValidationResult + 0x08, kern_der_start+0x8); // blob_start
	kwrite64(fakeCERValidationResult + 0x10, kern_der_end); // blob_end
	JBLogDebug("kern_der_start: 0x%llX, kern_der_end: 0x%llX", kern_der_start, kern_der_end);
	JBLogDebug("fakeCERValidationResult: 0x%llX", fakeCERValidationResult);

	// Get current OSEntitlements object
	uint64_t OSEntitlements_ptr = kread64(cr_label_ptr + 0x8);

	// Create new OSEntitlements object
	//uint64_t OSEntitlements_newPtr = kcall(bootInfo_getSlidUInt64(@"OSEntitlements_MetaClass_alloc"), 0, 0, 0, 0, 0, 0, 0, 0);

	uint64_t kslide = bootInfo_getUInt64(@"kernelslide");
	//JBLogDebug("initWithValidationResult(0x%llX, 0x%llX, 0x%llX, 0x%llX, %d)", kslide + 0xFFFFFFF008345CF8, OSEntitlements_newPtr, fakeCERValidationResult, csblob, true);
	//sleep(5);
	//uint64_t ret = kcall(kslide + 0xFFFFFFF008345CF8, OSEntitlements_newPtr, fakeCERValidationResult, csblob, true, 0, 0, 0, 0);
	//JBLogDebug("initWithValidationResult => 0x%llX", ret);

	//JBLogDebug("withValidationResult(0x%llX, 0x%llX, 0x%llX, %d)", kslide + 0xFFFFFFF008345C24, fakeCERValidationResult, csblob, false);
	//sleep(3);
	//return;
	//uint64_t OSEntitlements_newPtr = kcall(kslide + 0xFFFFFFF008345C24, fakeCERValidationResult, csblob, false, 0, 0, 0, 0, 0);

	//JBLogDebug("initWithValidationResult(0x%llX, 0x%llX, 0x%llX, 0x%llX, %d)", kslide + 0xFFFFFFF008345CF8, OSEntitlements_ptr, fakeCERValidationResult, csblob, true);
	//sleep(3);
	//uint64_t ret = kcall(kslide + 0xFFFFFFF008345CF8, OSEntitlements_ptr, fakeCERValidationResult, csblob, true, 0, 0, 0, 0);
	//JBLogDebug("initWithValidationResult => 0x%llX", ret);

	// Copy existing properties from old object ot new object
	//uint8_t *buf = malloc(0x88);
	//kreadbuf(OSEntitlements_ptr + 0x10, buf, 0x88);
	//kwritebuf(OSEntitlements_newPtr + 0x10, buf, 0x88);
	//free(buf);

	// Replace entitlements on CEQueryContext of new object and resign it
	//uint64_t CEQueryContext = OSEntitlements_newPtr + 0x28;
	//CEQueryContext_replace_entitlements(CEQueryContext, newEntitlements);
	//OSEntitlements_resign(OSEntitlements_newPtr);

	// Write new entitlements to label
	///call(bootInfo_getSlidUInt64(@"mac_label_set"), cr_label_ptr, 0, OSEntitlements_newPtr, 0, 0, 0, 0, 0);

	// Deallocate old entitlements object
	//kcall(bootInfo_getSlidUInt64(@"OSEntitlements_Destructor"), OSEntitlements_ptr, 0, 0, 0, 0, 0, 0, 0);
}

void cr_label_update_entitlements(uint64_t cr_label_ptr)
{
	uint64_t OSEntitlements_ptr = kread64(cr_label_ptr + 0x8);
	uint64_t kslide = bootInfo_getUInt64(@"kernelslide");
	kcall(0xFFFFFFF008346184 + kslide, OSEntitlements_ptr, 0, 0, 0, 0, 0, 0, 0);
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
}*/

uint64_t vnode_get_csblob(uint64_t vnode_ptr)
{
	uint64_t ubc_info_ptr = vnode_get_ubcinfo(vnode_ptr);
	if (!ubc_info_ptr) return 0;

	__block uint64_t retCsblob = 0;
	ubcinfo_iterate_csblobs(ubc_info_ptr, ^(uint64_t csblob, BOOL *stop)
	{
		retCsblob = csblob;
	});
	return retCsblob;
}

uint64_t vnode_get_data(uint64_t vnode_ptr)
{
	return kread64(vnode_ptr + 0xE0);
}

void vnode_set_data(uint64_t vnode_ptr, uint64_t data)
{
	kwrite64(vnode_ptr + 0xE0, data);
}

uint16_t vnode_get_type(uint64_t vnode_ptr)
{
	return kread16(vnode_ptr + 0x70);
}

uint32_t vnode_get_id(uint64_t vnode_ptr)
{
	return kread32(vnode_ptr + 0x74);
}

uint64_t vnode_get_mount(uint64_t vnode_ptr)
{
	return kread64(vnode_ptr + 0xD8);
}

/*NSMutableDictionary *proc_dump_entitlements(uint64_t proc_ptr)
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

	// Also apply changes on vnode
	uint64_t text_vnode = proc_get_text_vnode(proc_ptr);
	vnode_replace_entitlements(text_vnode, newEntitlements);

	//cr_label_update_entitlements(cr_label_ptr);

	//cr_label_replace_entitlements(cr_label_ptr, newEntitlements, vnode_get_csblob(text_vnode));
}*/

int proc_set_debugged(pid_t pid)
{
	if (pid > 0) {
		bool proc_needs_release = false;
		uint64_t proc = proc_for_pid(pid, &proc_needs_release);
		if (proc != 0) {
			uint64_t task = proc_get_task(proc);
			uint64_t vm_map = task_get_vm_map(task);
			uint64_t pmap = vm_map_get_pmap(vm_map);

			pmap_set_wx_allowed(pmap, true);

			// --- cs_flags, not needed, wx_allowed is enough
			// uint32_t csflags = proc_get_csflags(proc);
			// uint32_t new_csflags = ((csflags & ~0x703b10) | 0x10000024);
			// proc_set_csflags(proc, new_csflags);

			// --- some vm map crap, not needed
			// uint32_t f1 = kread32(vm_map + 0x94);
			// uint32_t f2 = kread32(vm_map + 0x98);
			// printf("before f1: %X, f2: %X\n", f1, f2);
			// f1 &= ~0x10u;
			// f2++;
			// f1 |= 0x8000;
			// f2++;
			// printf("after f1: %X, f2: %X\n", f1, f2);
			// kwrite32(vm_map + 0x94, f1);
			// kwrite32(vm_map + 0x98, f2);

			if (proc_needs_release) proc_rele(proc);
		}
	}
	return 0;
}

NSString *proc_get_path(pid_t pid)
{
	char pathbuf[4*MAXPATHLEN];
	int ret = proc_pidpath(pid, pathbuf, sizeof(pathbuf));
	if (ret <= 0) return nil;
	return [[[NSString stringWithUTF8String:pathbuf] stringByResolvingSymlinksInPath] stringByStandardizingPath];
}

pid_t proc_get_ppid(pid_t pid)
{
	struct proc_bsdinfo procInfo;
	if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &procInfo, sizeof(procInfo)) <= 0) {
		return -1;
	}
	return procInfo.pbi_ppid;
}

int64_t proc_fix_setuid(pid_t pid)
{
	NSString *procPath = proc_get_path(pid);
	struct stat sb;
	if(stat(procPath.fileSystemRepresentation, &sb) == 0) {
		if (S_ISREG(sb.st_mode) && (sb.st_mode & (S_ISUID | S_ISGID))) {
			bool proc_needs_release = false;
			uint64_t proc = proc_for_pid(pid, &proc_needs_release);
			uint64_t ucred = proc_get_ucred(proc);
			if ((sb.st_mode & (S_ISUID))) {
				proc_set_svuid(proc, sb.st_uid);
				ucred_set_svuid(ucred, sb.st_uid);
				ucred_set_uid(ucred, sb.st_uid);
			}
			if ((sb.st_mode & (S_ISGID))) {
				proc_set_svgid(proc, sb.st_gid);
				ucred_set_svgid(ucred, sb.st_gid);
				ucred_set_cr_groups(ucred, sb.st_gid);
			}
			uint32_t p_flag = proc_get_p_flag(proc);
			if ((p_flag & P_SUGID) != 0) {
				p_flag &= ~P_SUGID;
				proc_set_p_flag(proc, p_flag);
			}
			if (proc_needs_release) proc_rele(proc);
			return 0;
		}
		else {
			return 10;
		}
	}
	else {
		return 5;
	}
}

void run_unsandboxed(void (^block)(void))
{
	uint64_t selfProc = self_proc();
	uint64_t selfUcred = proc_get_ucred(selfProc);
	
	bool kernelProcNeedsFree = NO;
	uint64_t kernelProc = proc_for_pid(0, &kernelProcNeedsFree);
	if (kernelProcNeedsFree) {
		proc_rele(kernelProc);
	}
	uint64_t kernelUcred = proc_get_ucred(kernelProc);

	proc_set_ucred(selfProc, kernelUcred);
	block();
	proc_set_ucred(selfProc, selfUcred);
}