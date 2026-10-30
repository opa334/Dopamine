#include "txm.h"

#include "util.h"
#include "hookd.h"

int TXMCodeRegion_comparator(uint64_t regionSearchPtr, uint64_t regionCurPtr)
{
	uint64_t searchStartAddr  = kread64(regionSearchPtr + koffsetof(TXMCodeRegion, startAddr));
	uint64_t curStartAddr     = kread64(regionCurPtr    + koffsetof(TXMCodeRegion, startAddr));

	if (searchStartAddr < curStartAddr) {
		return -1;
	}
	else if (searchStartAddr > curStartAddr) {
		return 1;
	}
	else {
		return 0;
	}
}

RB_GENERATE(TXMCodeRegionRBTree, uint64_t, koffsetof(TXMCodeRegion, RBLink), TXMCodeRegion_comparator)

uint64_t allocateCodeRegionObject(void)
{
	// Here we simulate "allocating" a code region object by creating one in our process it and then removing it from the RB tree again to leak it
	// This works fine because nothing checks / panics if we remove it, just faulting in new code from the region would not work
	// Only works if the process calling this has allowsInvalidCode set to true

	// Allocate
	vm_address_t victimPage = 0;
	if (vm_allocate(mach_task_self_, &victimPage, 0x4000, VM_FLAGS_ANYWHERE) != KERN_SUCCESS) return 0;

	// Make executable
	kern_return_t kr;
	if (__builtin_available(iOS 19.0, *)) {
		kr = hookd_vm_protect(mach_task_self_, victimPage, 0x4000, false, VM_PROT_READ | VM_PROT_EXECUTE | VM_PROT_COPY);
	}
	else {
		kr = vm_protect(mach_task_self_, victimPage, 0x4000, false, VM_PROT_READ | VM_PROT_EXECUTE | VM_PROT_COPY);
	}
	if (kr != KERN_SUCCESS) {
		vm_deallocate(mach_task_self_, victimPage, 0x4000);
		return 0;
	}

	// Fault in
	uint64_t rd = 0;
	vm_size_t rdSz = sizeof(rd);
	if (vm_read_overwrite(mach_task_self_, victimPage, rdSz, (vm_address_t)&rd, &rdSz) != KERN_SUCCESS) {
		vm_deallocate(mach_task_self_, victimPage, 0x4000);
		return 0;
	}

	// At this point there will be an associated code region in the rb tree, find and remove it
	uint64_t txm_address_space = kread_ptr(pmap_self() + koffsetof(pmap, txm_address_space));
	uint64_t head = txm_address_space + koffsetof(TXMAddressSpace, codeRegions);

	uint64_t victimDebugRegion = RB_FIND(TXMCodeRegionRBTree, head, CodeRegionRBTree_KEY(victimPage));
	if (!victimDebugRegion) {
		vm_deallocate(mach_task_self_, victimPage, 0x4000);
		return 0;
	}

	RB_REMOVE(TXMCodeRegionRBTree, head, victimDebugRegion);

	// Now deallocate the victimPage again
	vm_deallocate(mach_task_self_, victimPage, 0x4000);

	// Clear any leftover data
	char buf[0x50];
	memset(buf, 0, sizeof(buf));
	kwritebuf(victimDebugRegion, buf, sizeof(buf));

	// This needs to be true when we return it in order for the object to be usable
	kwrite8(victimDebugRegion + koffsetof(TXMCodeRegion, active), true);

	// Now victimDebugRegion is leaked, return it
	return victimDebugRegion;
}