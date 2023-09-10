#include <stdio.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <objc/objc.h>
#include "common.h"

#if __arm64e__

#define ARM64E_NEW_ABI_FLAG 0x80000000

void sign_data_pointer(uint64_t *location, uint16_t modifier)
{
	uint64_t pointer = *location;
	if (pointer == 0) return;

	uint64_t context = ((uint64_t)location) | ((uint64_t)modifier << 48);
	uint64_t signedPointer = 0;

	asm volatile (
		"ldr x16, %1\n\t"   // Load pointer into x16
		"ldr x17, %2\n\t"   // Load context into x17
		"xpacd x16\n\t"
		"pacda x16, x17\n\t"
		"str x16, %0"
		: "=m" (signedPointer) // Write output x16 to signedPointer
		: "m" (pointer), "m" (context) // Input operands
		: "x16", "x17"       // Clobbered registers
	);

	//printf("sign_data_pointer: %llx -> %llx (at %p)\n", pointer, signedPointer, location);

	*location = signedPointer;
}

void sign_const_pointer(uint64_t *location, uint16_t modifier)
{
	//vm_protect(mach_task_self_, location, 0x8, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
	sign_data_pointer(location, modifier);
	//vm_protect(mach_task_self_, location, 0x8, false, VM_PROT_READ);
}

uint64_t strip_data_pointer(uint64_t pointer)
{
	/*uint64_t strippedPointer = 0;

	asm volatile (
		"ldr x16, %1\n\t"   // Load pointer into x16
		"xpacd x16\n\t"
		"str x16, %0"
		: "=m" (strippedPointer) // Output
		: "m" (pointer) // Input operands
		: "x16"       // Clobbered registers
	);

	return strippedPointer;*/
	return pointer & 0x7fffffffff;
}

void sign_class(uint64_t *class)
{
	sign_data_pointer(&class[0], 0x6AE1);
	sign_data_pointer(&class[1], 0xB5AB);
	uint64_t *someOtherShit = (uint64_t *)strip_data_pointer(class[4]);
	if (someOtherShit) {
		sign_const_pointer(&someOtherShit[4], 0xC310);
	}
}


uint8_t *get_data_section(const struct mach_header_64 *mh, char *sectname, size_t *countOut)
{
	size_t size = 0;
	uint8_t *candidate = getsectiondata(mh, "__DATA", sectname, &size);
	if (!candidate) {
		candidate = getsectiondata(mh, "__DATA_CONST", sectname, &size);
		if (!candidate) {
			candidate = getsectiondata(mh, "__DATA_DIRTY", sectname, &size);
		}
	}
	if (countOut) {
		*countOut = size >> 3;
	}
	return candidate;
}

/*void print_shit(const struct mach_header_64 *mh, const char *sect)
{
	size_t len = 0;

	uint64_t *sectPtr = (uint64_t *)get_data_section(mh, (char *)sect, &len);
	if (sectPtr) {
		printf("- Section %s, Length: %zu -\n", sect, len);
		for (int i = 0; i < len; i++) {
			//printf("%d: %p -> %llx -> %llx\n", i, &sectPtr[i], sectPtr[i], *(uint64_t *)(sectPtr[i]));

			Dl_info in;
			dladdr(&sectPtr[i], &in);

			printf("%d: %p -> %llx (%s)\n", i, &sectPtr[i], sectPtr[i], in.dli_sname);
		}
	}
}*/

/*void print_exported_symbols(const struct mach_header_64* header) {
    const struct segment_command_64* cmd = NULL;
    uintptr_t slide = (uintptr_t)header;

    uint32_t image_count = _dyld_image_count();
    for (uint32_t i = 0; i < image_count; i++) {
        cmd = getsegbynamefromheader_64(header, SEG_TEXT);

        if (!cmd) {
            printf("Segment not found in the library\n");
            return;
        }

        const struct nlist_64* symtab = (struct nlist_64*)((uintptr_t)header + cmd->fileoff - cmd->vmaddr + slide);
        uint32_t symbol_count = cmd->filesize / sizeof(struct nlist_64);

        printf("Exported symbols in the library:\n");

        for (uint32_t j = 0; j < symbol_count; j++) {
            if (symtab[j].n_type & N_EXT) {
                const char* symbol_name = (const char*)((uintptr_t)header + symtab[j].n_un.n_strx);
                printf("%s\n", symbol_name);
            }
        }

        return; // Found the library, no need to continue searching
    }
    printf("Library not found in loaded images.\n");
}*/

bool oldabi_ignore_images = false;
void oldabi_image_added(const struct mach_header *mh, intptr_t vmaddr_slide)
{
	if (oldabi_ignore_images) return;

	const struct mach_header_64 *mh64 = (const struct mach_header_64 *)mh;
	
	if ((mh64->cpusubtype & ~ARM64E_NEW_ABI_FLAG) != CPU_SUBTYPE_ARM64E) return;
	if ((mh64->cpusubtype & ARM64E_NEW_ABI_FLAG) == ARM64E_NEW_ABI_FLAG) return;

	/*Dl_info i;
	dladdr(mh, &i);
	printf("-- %s --\n", i.dli_fname);*/

	// if the image being added is compiled with old ABI, apply fixups
	//print_shit(mh64, "__objc_classlist");
	//print_shit(mh64, "__objc_classrefs");
	//print_shit(mh64, "__cfstring");

	//print_shit(mh64, "__objc_classlist");
	//print_shit(mh64, "__objc_classrefs");
	//print_shit(mh64, "__cfstring");
	//print_shit(mh64, "__objc_data");
	//print_shit(mh64, "__objc_const");

	//print_shit(mh64, "__const");

	//printf("patching __objc_classlist\n");
	// Class list fixup
	size_t classListCount = 0;
	Class *classList = (Class *)get_data_section(mh64, "__objc_classlist", &classListCount);
	if (classList) {
		for (size_t i = 0; i < classListCount; i++) {
			Class class = classList[i];
			sign_class((uint64_t *)class);
			
			uint64_t *nextClass = (uint64_t *)strip_data_pointer(*(uint64_t *)(class));
			if (nextClass) {
				sign_class(nextClass);
			}
		}
	}

	// Class reference fixup
	size_t classRefsListCount = 0;
	Class *classRefsList = (Class *)get_data_section(mh64, "__objc_classrefs", &classRefsListCount);
	if (classRefsList) {
		for (size_t i = 0; i < classRefsListCount; i++) {
			uint64_t *class = classRefsList[i];
			//sign_class((uint64_t *)class);
			sign_data_pointer(&class[0], 0x6AE1);
			//sign_data_pointer(&class[1], 0xB5AB);
			/*uint64_t *nextClass = (uint64_t *)strip_data_pointer(*(uint64_t *)(class));
			if (nextClass) {
				sign_class(nextClass);
			}*/
		}
	}

	//printf("patching __cfstring\n");
	// CFString fixup
	size_t cfStringsCount = 0;
	uint64_t *cfStrings = (uint64_t *)get_data_section(mh64, "__cfstring", &cfStringsCount);
	if (cfStrings) {
		for (size_t i = 0; i < cfStringsCount; i += 4) {
			uint64_t *pacPtrLocation = &cfStrings[i];
			sign_data_pointer(pacPtrLocation, 0x6AE1);
		}
	}

	// Const fixup (very hacky)
	//printf("patching __const\n");
	size_t constEntryCount = 0;
	uint64_t *constEntries = (uint64_t *)get_data_section(mh64, "__const", &constEntryCount);
	for (size_t i = 1; i < constEntryCount; i++) {
		Dl_info entryInfo;
		if (dladdr(&constEntries[i], &entryInfo) != 0) {
			// couldn't find any better way to find block literals...
			if (stringStartsWith(entryInfo.dli_sname, "__block_literal_global")) {
				sign_data_pointer(&constEntries[i], 0x6ae1);
				i += 3;
			}
		}
	}

	//getchar();
}

void enable_arm64e_oldabi_fix(void)
{
	oldabi_ignore_images = true;
	_dyld_register_func_for_add_image(oldabi_image_added);
	oldabi_ignore_images = false;
}

#else
void enable_arm64e_oldabi_fix(void) { }
#endif
