#import <Foundation/Foundation.h>

#include <stdio.h>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/stat.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <CoreSymbolication.h>

#include "../libjailbreak.h"
#include "common.h"
#include "log.h"

uint64_t show_dyld_regions(mach_port_t task, bool more)
{
    uint64_t dyld_address = 0;
    
    vm_address_t region_base = 0;
    vm_size_t region_size = 0;

    // vm_region_basic_info_data_64_t info;
	// vm_region_flavor_t flavor = VM_REGION_BASIC_INFO_64;
    // mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;

    vm_region_extended_info_data_t info;
	vm_region_flavor_t flavor = VM_REGION_EXTENDED_INFO;
    mach_msg_type_number_t info_count = VM_REGION_EXTENDED_INFO_COUNT;

    while (true) {
        region_base += region_size;

        mach_port_t object_name;
        kern_return_t kr = vm_region_64(task, &region_base, &region_size, flavor, (vm_region_info_t) &info, &info_count, &object_name);
        if (kr != KERN_SUCCESS) break;

        if(dyld_address != 0) {
		    // JBLogDebug("show_dyld_regions: region base=%llx size=%llx prot=%x/%x inhert=%d shared=%d", region_base, region_size, info.protection, info.max_protection, info.inheritance, info.shared);
            JBLogDebug("show_dyld_regions: region base=%llx size=%llx prot=%x/%x inhert=%d share_mode=%d", region_base, region_size, info.protection, -1, -1, info.share_mode);
        }

		if(info.protection==(VM_PROT_READ|VM_PROT_EXECUTE)) {
            // JBLogDebug("show_dyld_regions: region base=%llx size=%llx prot=%x/%x inhert=%d shared=%d", region_base, region_size, info.protection, info.max_protection, info.inheritance, info.shared);
            JBLogDebug("show_dyld_regions: region base=%llx size=%llx prot=%x/%x inhert=%d share_mode=%d", region_base, region_size, info.protection, -1, -1, info.share_mode);
    
			size_t readsize=0;
			struct mach_header_64 header={0};
			kr = vm_read_overwrite(task, (vm_address_t)region_base, sizeof(header), (vm_address_t)&header, &readsize);
			if(kr != KERN_SUCCESS) {
				JBLogDebug("show_dyld_regions: vm_read failed! %d %s", kr, mach_error_string(kr));
				break;
			}
			JBLogDebug("show_dyld_regions: header=%p magic=%08x filetype=%d", region_base, header.magic, header.filetype);
			if(header.magic==MH_MAGIC_64 && header.filetype==MH_DYLINKER) {
                JBLogDebug("show_dyld_regions: dyld found! %p", region_base);
				dyld_address = (uint64_t)region_base;
				if(!more) break;
			}
		}
    }

    return dyld_address;
}

void patchedtest(mach_port_t task, uint64_t remoteLoadAddress)
{
    // show_dyld_regions(task, true);

    uint64_t getAMFI=0;
    if (__builtin_available(iOS 16.0, *)) {
     getAMFI = remoteLoadAddress + 0x197FC;
    }
    else {
     getAMFI = remoteLoadAddress + 0x1C3C0;
    }

    size_t readsize=0;
    uint32_t readdata=0;
    vm_read_overwrite(task, (vm_address_t)getAMFI, sizeof(readdata), (vm_address_t)&readdata, &readsize);

    JBLogDebug("getAMFI=%X", readdata);
#ifdef __arm64e__
    getAMFI = (uint64_t)__builtin_ptrauth_sign_unauthenticated((void*)getAMFI, 0, 0);
#endif

    if(task == mach_task_self()) {
        JBLogDebug("getAMFI=%llX", ((uint64_t(*)())getAMFI)());
    }

    task_dyld_info_data_t dyldInfo;
    uint32_t count = TASK_DYLD_INFO_COUNT;
    task_info(task, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &count);
    JBLogDebug("new all_image_info_addr=%p", (void*)dyldInfo.all_image_info_addr);
    JBLogDebug("new all_image_info_size=%p", (void*)dyldInfo.all_image_info_size);

}

#define DYLD_INFO_MAX_SEARCH_INDEX 200
int task_set_dyld_info(uint64_t task, uint64_t addr, uint64_t size)
{
    static uint32_t all_image_info_addr_offset=0, all_image_info_size_offset=0, info_offset=0;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        task_dyld_info_data_t dyldInfo={0};
        uint32_t count = TASK_DYLD_INFO_COUNT;
        kern_return_t kr = task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&dyldInfo, &count);
        if(kr != KERN_SUCCESS) {
            JBLogError("task_info failed: %d,%s", kr, mach_error_string(kr));
            return;
        }
        JBLogDebug("task_set_dyld_info: all_image_info_addr=%p", (void*)dyldInfo.all_image_info_addr);
        JBLogDebug("task_set_dyld_info: all_image_info_size=%p", (void*)dyldInfo.all_image_info_size);
    
        uint64_t selftask = task_self();
        JBLogDebug("task_set_dyld_info: selftask=%llx", selftask);

        int i=0;
        for(; i<DYLD_INFO_MAX_SEARCH_INDEX; i++) 
        {
            if(kread64(selftask + i*8)==dyldInfo.all_image_info_addr
             && kread64(selftask + (i+1)*8)==dyldInfo.all_image_info_size) {
                JBLogDebug("task_set_dyld_info: all_image_info_addr offset=[%d]0x%x", i, i*8 );
                JBLogDebug("task_set_dyld_info: all_image_info_size offset=[%d]0x%x", i+1, (i+1)*8 );
                
                all_image_info_addr_offset = i*8;
                all_image_info_size_offset = (i+1)*8;

                break;
            }
        }
        for(; i<(DYLD_INFO_MAX_SEARCH_INDEX+0); i++) {
            uint64_t info[6] = {1,0,0,0,1,0};
            uint8_t buffer[sizeof(info)] = {0};
            kreadbuf(task + i*8, buffer, sizeof(buffer));
            if(memcmp(buffer, info, sizeof(info))==0) {
                JBLogDebug("task_set_dyld_info: info offset=[%d]0x%x\n", i, i*8);
                info_offset = i*8;
                break;
            }
        }
    });

    if(all_image_info_addr_offset==0 || all_image_info_size_offset==0) {
        JBLogError("invalid all_image_info_addr/size offset");
        abort();
        return -1;
    }

    if(info_offset) {
        uint64_t info[6] = {0};
        kwritebuf(task + info_offset, info, sizeof(info));
    } else if(task != proc_task(proc_find(1))) {
        JBLogError("invalid info offset");
        abort();
        return -1;
    }

    kwrite64(task + all_image_info_addr_offset, addr);
    kwrite64(task + all_image_info_size_offset, size);
    return 0;
}

void analyzeSegmentsLayout(struct mach_header_64* header, uint64_t* vmSpace, bool* hasZeroFill)
{
    bool     writeExpansion = false;
    uint64_t lowestVmAddr   = 0xFFFFFFFFFFFFFFFFULL;
    uint64_t highestVmAddr  = 0;
    uint64_t sumVmSizes     = 0;

    uint64_t preferredLoadAddress = 0;

    struct load_command* lc = (struct load_command*)((uint64_t)header + sizeof(*header));
    for (int i = 0; i < header->ncmds; i++) {        
        if(lc->cmd == LC_SEGMENT_64)
        {
            struct segment_command_64* seg = (struct segment_command_64*)lc;
            JBLogDebug("[analyzeSegmentsLayout] segment: %s file=%llx:%llx vm=%llx:%llx prot=%x/%x", seg->segname, seg->fileoff, seg->filesize, seg->vmaddr, seg->vmsize, seg->initprot, seg->maxprot);

            if ( strcmp(seg->segname, SEG_PAGEZERO) == 0 )
                continue;
            if ( strcmp(seg->segname, SEG_TEXT) == 0 ) {
                preferredLoadAddress = seg->vmaddr;
            }
            if ( (seg->initprot & VM_PROT_WRITE) && (seg->filesize !=  seg->vmsize) )
                writeExpansion = true; // zerofill at end of __DATA
            if ( seg->vmsize == 0 ) {
                // Always zero fill if we have zero-sized segments
                writeExpansion = true;
            }
            if ( seg->vmaddr < lowestVmAddr )
                lowestVmAddr = seg->vmaddr;
            if ( seg->vmaddr+seg->vmsize > highestVmAddr )
                highestVmAddr = seg->vmaddr+seg->vmsize;
            sumVmSizes += seg->vmsize;
        }
        /////////
        lc = (struct load_command *) ((char *)lc + lc->cmdsize);
    }

    uint64_t totalVmSpace = (highestVmAddr - lowestVmAddr);
    // LINKEDIT vmSize is not required to be a multiple of page size.  Round up if that is the case
    totalVmSpace = (totalVmSpace + (PAGE_SIZE - 1)) & ~(PAGE_SIZE - 1);
    bool hasHole = (totalVmSpace != sumVmSizes); // segments not contiguous

    // The aux KC may have __DATA first, in which case we always want to vm_copy to the right place
    bool hasOutOfOrderSegments = false;
#if BUILDING_APP_CACHE_UTIL
    uint64_t textSegVMAddr = preferredLoadAddress;
    hasOutOfOrderSegments = textSegVMAddr != lowestVmAddr;
#endif

    *vmSpace     = totalVmSpace;
    *hasZeroFill = writeExpansion || hasHole || hasOutOfOrderSegments;
}

int loadSinature(int fd, struct mach_header_64* header)
{
    struct load_command* lc = (struct load_command*)((uint64_t)header + sizeof(*header));
    for (int i = 0; i < header->ncmds; i++) {        
        switch(lc->cmd) {
            case LC_CODE_SIGNATURE: {
                struct linkedit_data_command* codeSignCmd = (struct linkedit_data_command*)lc;
                fsignatures_t siginfo;
                siginfo.fs_file_start = 0; // start of mach-o slice in fat file
                siginfo.fs_blob_start = (void*)(long)codeSignCmd->dataoff; // start of CD in mach-o file
                siginfo.fs_blob_size  = codeSignCmd->datasize; // size of CD
                int result            = fcntl(fd, F_ADDFILESIGS, &siginfo);
                if(result == 0) {
                    JBLogDebug("fcntl add signature success: %d", result);
                    return 0;
                } else {
                    JBLogError("fcntl add signture failed: %d, %s", errno, strerror(errno));
                    return -1;
                }
                break;
            }
        }
        /////////
        lc = (struct load_command *) ((char *)lc + lc->cmdsize);
    }
    return -1;
}

static uint64_t get_symbol(const char* path, const char* name)
{
    void *csHandle = dlopen("/System/Library/PrivateFrameworks/CoreSymbolication.framework/CoreSymbolication", RTLD_NOW);
	CSSymbolicatorRef (*__CSSymbolicatorCreateWithPathAndArchitecture)(const char* path, cpu_type_t type) = dlsym(csHandle, "CSSymbolicatorCreateWithPathAndArchitecture");
	CSSymbolRef (*__CSSymbolicatorGetSymbolWithMangledNameAtTime)(CSSymbolicatorRef cs, const char* name, uint64_t time) = dlsym(csHandle, "CSSymbolicatorGetSymbolWithMangledNameAtTime");
	CSRange (*__CSSymbolGetRange)(CSSymbolRef sym) = dlsym(csHandle, "CSSymbolGetRange");

	CSSymbolicatorRef symbolicator = __CSSymbolicatorCreateWithPathAndArchitecture(path, CPU_TYPE_ARM64);
	CSSymbolRef symbol = __CSSymbolicatorGetSymbolWithMangledNameAtTime(symbolicator, name, 0);
	CSRange range = __CSSymbolGetRange(symbol);
    return range.location;
}

struct DYLDINFO {
    uint64_t entrypoint;
    uint64_t vmSpaceSize;
    void*    imageAddress;
    uint64_t all_image_info_addr;
    uint64_t all_image_info_size;
    uint64_t loadDyldCache_function;
    uint64_t loadDyldCache_trampoline;
};

struct DYLDINFO* loadDyldInfo(const char* path)
{
    JBLogDebug("loadDyldInfo: %s", path);

    int fd = -1;
    kern_return_t kr;
    void* dyld = MAP_FAILED;

    struct DYLDINFO* result = malloc(sizeof(struct DYLDINFO));
    memset(result, 0, sizeof(struct DYLDINFO));

    result->loadDyldCache_function = get_symbol(path, "__ZN5dyld313loadDyldCacheERKNS_18SharedCacheOptionsEPNS_19SharedCacheLoadInfoE");
    JBLogDebug("loadDyldCache function: %llx", result->loadDyldCache_function);
    if(result->loadDyldCache_function == 0) {
        JBLogError("loadDyldInfo: loadDyldCache_function not found in %s", path);
        goto failed;
    }

    result->loadDyldCache_trampoline = get_symbol(path, "_ORIG__ZN5dyld313loadDyldCacheERKNS_18SharedCacheOptionsEPNS_19SharedCacheLoadInfoE");
    JBLogDebug("loadDyldCache orig trampoline: %llx", result->loadDyldCache_trampoline);

    fd = open(path, O_RDONLY);
    if(fd<0) {
        JBLogError("open dyld failed: %d, %s", errno, strerror(errno));
        goto failed;
    }

    struct stat sb;
    if(fstat(fd, &sb)<0) {
        JBLogError("fstat dyld failed: %d, %s", errno, strerror(errno));
        goto failed;
    }

    dyld = mmap(NULL, sb.st_size, PROT_READ, MAP_PRIVATE|MAP_RESILIENT_CODESIGN, fd, 0);
    if(dyld==MAP_FAILED) {
        JBLogError("mmap dyld failed: %d, %s", errno, strerror(errno));
        goto failed;
    }

    JBLogDebug("dyld file map=%p", dyld);

    struct mach_header_64* header = (struct mach_header_64*)dyld;

    // load code signature before mmap text segment
    if(loadSinature(fd, header) != 0) {
        JBLogError("loadSinature failed: %s", path);
        goto failed;
    }

    struct fgetsigsinfo siginfo = {0, GETSIGSINFO_PLATFORM_BINARY, 0};
    JBLogDebug("fcntl F_GETSIGSINFO=%d, %d", fcntl(fd, F_GETSIGSINFO, &siginfo), errno);
    JBLogDebug("siginfo: fg_sig_is_platform=%d", siginfo.fg_sig_is_platform);

    bool hasZeroFill = false;
    analyzeSegmentsLayout(header, &result->vmSpaceSize, &hasZeroFill);
    JBLogDebug("vmSpace=%llx hasZeroFill=%d", result->vmSpaceSize, hasZeroFill);

    // reserve address range
    kr = vm_allocate(mach_task_self(), (vm_address_t*)&result->imageAddress, (vm_size_t)result->vmSpaceSize, VM_FLAGS_ANYWHERE);
    if (kr != KERN_SUCCESS) {
        JBLogError("vm_allocate %d,%s", kr, mach_error_string(kr));
        goto failed;
    }

    JBLogDebug("dyld image address: %p", result->imageAddress);

    int segIndex=0;
    struct load_command* lc = (struct load_command*)((uint64_t)header + sizeof(*header));
    for (int i = 0; i < header->ncmds; i++) {        
        switch(lc->cmd) {
            case LC_SEGMENT_64: {
                struct segment_command_64 * seg = (struct segment_command_64 *) lc;
                
                JBLogDebug("segment: %s file=%llx:%llx vm=%llx:%llx prot=%x/%x", seg->segname, seg->fileoff, seg->filesize, seg->vmaddr, seg->vmsize, seg->initprot, seg->maxprot);

                if (seg->filesize == 0)  {
                    JBLogDebug("skip segment %s", seg->segname);
                    break; //break switch
                }
                if ( (seg->vmaddr == 0) && (segIndex > 0) ) {
                    JBLogDebug("skip segment %s", seg->segname);
                    break; //break switch
                }

                bool hasZeroFill = (seg->initprot == (VM_PROT_READ|VM_PROT_WRITE)) && (seg->filesize < seg->vmsize);
                if ( !hasZeroFill || (seg->filesize != 0) ) {
                    // add region for content that is not wholely zerofill

                    size_t mapSize = seg->filesize;
                    // special case LINKEDIT, the vmsize is often larger than the filesize
                    // but we need to mmap off end of file, otherwise we may have r/w pages at end
                    if (strcmp(seg->segname, SEG_LINKEDIT)==0 && seg->initprot==VM_PROT_READ) {
                        mapSize = (uint32_t)seg->vmsize;
                    }

                    void* segAddress = mmap((void*)((uint64_t)result->imageAddress + seg->vmaddr), mapSize, seg->initprot, MAP_FIXED | MAP_PRIVATE, fd, (size_t)seg->fileoff);
                    if ( segAddress == MAP_FAILED ) {
                        JBLogError("mmap %s failed: %d, %s", seg->segname, errno, strerror(errno));
                        goto failed;
                    }
                    segIndex++;
                } else {
                    // <rdar://problem/32363581> Mapping zero filled regions fails with mmap of size 0
                    uint32_t fileOffset   = 0;
                    uint32_t fileSize     = (uint32_t)(seg->vmsize - seg->filesize);
                    uint64_t vmOffset     = seg->vmaddr + seg->filesize;
                    int32_t  perms        = seg->initprot;
                    JBLogDebug("segment %s has zero fill: %llx:%llx", seg->segname, vmOffset, fileSize);
                }

                struct section_64* sec = (struct section_64*)((uint64_t)seg+sizeof(*seg));
                for(int j=0; j<seg->nsects; j++)
                {
                    JBLogDebug("section[%d] = %.*s/%.*s vm=%llx offset=%x:%llx", j, 
                        sizeof(sec[j].segname),sec[j].segname, 
                        sizeof(sec[j].sectname),sec[j].sectname,
                        sec[j].addr, sec[j].offset, sec[j].size);

                    if(strncmp(sec[j].sectname, "__all_image_info", sizeof(sec[j].sectname)) == 0) {
                        JBLogDebug("all_image_info section: %llx:%llx", sec[j].addr, sec[j].size);
                        result->all_image_info_addr = sec[j].addr;
                        result->all_image_info_size = sec[j].size;
                        break;
                    }
                }
                break;
            }

            case LC_UNIXTHREAD: {

                if(lc->cmdsize != sizeof(*lc) + sizeof(uint32_t)*2 + sizeof(arm_thread_state64_t)) {
                    JBLogError("unexpected dyld thread_command: %x", lc->cmdsize);
                    goto failed;
                }
                
                uint32_t* tcdata = (uint32_t*)((uint64_t)lc + sizeof(struct thread_command));
                
                uint32_t flavor = tcdata[0];
                uint32_t count = tcdata[1];
                if(tcdata[0] != ARM_THREAD_STATE64 || count != ARM_THREAD_STATE64_COUNT) {
                    JBLogError("unexpected dyld thread state: %x", tcdata[0]);
                    goto failed;
                }

                arm_thread_state64_t *threadState = (arm_thread_state64_t*)&tcdata[2];
#ifdef __arm64e__
                uint64_t entry = (uint64_t)threadState->__opaque_pc;
#else
                uint64_t entry = (uint64_t)threadState->__pc;
#endif
                JBLogDebug("dyld entry: %llx", entry);
                result->entrypoint = entry;
                break;
            }
        }
        
        /////////
        lc = (struct load_command *) ((char *)lc + lc->cmdsize);
    }

    if(result->all_image_info_addr == 0 || result->all_image_info_size == 0) {
        JBLogError("dyld all_image_info section not found");
        goto failed;
    }

    if(result->entrypoint == 0) {
        JBLogError("dyld entrypoint not found");
        goto failed;
    }

    goto final;

failed:
    if(result->imageAddress) vm_deallocate(mach_task_self(), (vm_address_t)result->imageAddress, result->vmSpaceSize);
    free(result);
	result = NULL;

final:
    if(fd >= 0) close(fd);
    if(dyld != MAP_FAILED) munmap(dyld, sb.st_size);
    return result;
}

int hook_dyld_entry(mach_port_t task, uint64_t old_header, uint64_t old_entry, uint64_t new_entry)
{
    //Destroy the old dyld header first to avoid double dyld being found via vm_region*
    
    struct mach_header_64 padding = {0};

    kern_return_t kr = vm_protect(task, (vm_address_t)old_header, sizeof(padding), false, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY);
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_protect header failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }

    kr = vm_write(task, (vm_address_t)old_header, (vm_offset_t)&padding, sizeof(padding));
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_write header failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }


    uint32_t codes[] = {
/*
movz x0, 0x0000, lsl 48
movk x0, 0x0000, lsl 32
movk x0, 0x0000, lsl 16
movk x0, 0x0000
br   x0
*/
        0xD2E00000,
        0xF2C00000,
        0xF2A00000,
        0xF2800000,
        0xD61F0000,
    };

    codes[0] |= ((new_entry >> 48) & 0xffff) << 5;
    codes[1] |= ((new_entry >> 32) & 0xffff) << 5;
    codes[2] |= ((new_entry >> 16) & 0xffff) << 5;
    codes[3] |= ((new_entry >>  0) & 0xffff) << 5;

    kr = vm_protect(task, (vm_address_t)old_entry, sizeof(codes), false, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY);
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_protect rw(cpoy) failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }

    kr = vm_write(task, (vm_address_t)old_entry, (vm_offset_t)codes, sizeof(codes));
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_write failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }

    kr = vm_protect(task, (vm_address_t)old_entry, sizeof(void*), false, VM_PROT_READ|VM_PROT_EXECUTE);
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_protect rx failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }

    return 0;
}

int hook_dyld_function(mach_port_t task, uint64_t old_func, uint64_t new_func, uint64_t orig_func)
{
/*
movz x17, 0x0000, lsl 48
movk x17, 0x0000, lsl 32
movk x17, 0x0000, lsl 16
movk x17, 0x0000
br   x17
*/
#define HOOK_CODE_TEMPLATE { \
    0xD2E00011, \
    0xF2C00011, \
    0xF2A00011, \
    0xF2800011, \
    0xD61F0220  \
}

    uint32_t tramp[] = HOOK_CODE_TEMPLATE;
    tramp[0] |= (((old_func+sizeof(tramp)) >> 48) & 0xffff) << 5;
    tramp[1] |= (((old_func+sizeof(tramp)) >> 32) & 0xffff) << 5;
    tramp[2] |= (((old_func+sizeof(tramp)) >> 16) & 0xffff) << 5;
    tramp[3] |= (((old_func+sizeof(tramp)) >>  0) & 0xffff) << 5;

    kern_return_t kr = vm_protect(task, (vm_address_t)orig_func, sizeof(tramp)*2, false, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY);
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_protect rw(cpoy) failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }

    kr = vm_copy(task, (vm_address_t)old_func, sizeof(tramp), (vm_address_t)orig_func);
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_copy failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }

    kr = vm_write(task, (vm_address_t)(orig_func+sizeof(tramp)), (vm_offset_t)tramp, sizeof(tramp));
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_write failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }

    kr = vm_protect(task, (vm_address_t)orig_func, sizeof(tramp)*2, false, VM_PROT_READ|VM_PROT_EXECUTE);
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_protect rx failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }



    uint32_t codes[] = HOOK_CODE_TEMPLATE;

    codes[0] |= ((new_func >> 48) & 0xffff) << 5;
    codes[1] |= ((new_func >> 32) & 0xffff) << 5;
    codes[2] |= ((new_func >> 16) & 0xffff) << 5;
    codes[3] |= ((new_func >>  0) & 0xffff) << 5;

    kr = vm_protect(task, (vm_address_t)old_func, sizeof(codes), false, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY);
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_protect rw(cpoy) failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }

    kr = vm_write(task, (vm_address_t)old_func, (vm_offset_t)codes, sizeof(codes));
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_write failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }

    kr = vm_protect(task, (vm_address_t)old_func, sizeof(void*), false, VM_PROT_READ|VM_PROT_EXECUTE);
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_protect rx failed: %d,%s", kr, mach_error_string(kr));
        return -1;
    }

    return 0;
}

int proc_patch_dyld_internal(pid_t pid, bool spinlockFixOnly)
{
    int ret = 0;

    kern_return_t kr;
    task_port_t task = MACH_PORT_NULL;
    vm_address_t  remoteLoadAddress = 0;

    static struct DYLDINFO* stockDyldInfo = NULL;
    static struct DYLDINFO* patchedDyldInfo = NULL;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        assert((stockDyldInfo=loadDyldInfo("/usr/lib/dyld")) != NULL);
        assert((patchedDyldInfo=loadDyldInfo(JBROOT_PATH("/basebin/.fakelib/dyld"))) != NULL);
    });

    if(stockDyldInfo == NULL || patchedDyldInfo == NULL) {
        JBLogError("load dyld failed");
        return -1;
    }

    kr = task_for_pid(mach_task_self(), pid, &task);
    if(kr != KERN_SUCCESS || !MACH_PORT_VALID(task)) {
        JBLogError("task_for_pid failed: %x,%s task=%x", kr, mach_error_string(kr), task);
        goto failed;
    }

    // show_dyld_regions(task, true);

    task_dyld_info_data_t dyldInfo={0};
    uint32_t count = TASK_DYLD_INFO_COUNT;
    kr = task_info(task, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &count);
    if(kr != KERN_SUCCESS) {
    	JBLogError("task_info failed: %d,%s", kr, mach_error_string(kr));
        goto failed;
    }

    uint64_t dyld_address = dyldInfo.all_image_info_addr - stockDyldInfo->all_image_info_addr;
    uint64_t dyld_entry = dyld_address + stockDyldInfo->entrypoint;
    JBLogDebug("default dyld=%p entry=%p", (void*)dyld_address, (void*)dyld_entry);

    vm_prot_t cur_prot=0, max_prot=0;
    kr = vm_remap(task, &remoteLoadAddress, patchedDyldInfo->vmSpaceSize, 0, VM_FLAGS_ANYWHERE, mach_task_self(), (mach_vm_address_t)patchedDyldInfo->imageAddress, true, &cur_prot, &max_prot, VM_INHERIT_COPY);
    if(kr != KERN_SUCCESS) {
        JBLogError("vm_remap %d,%s", kr, mach_error_string(kr));
        goto failed;
    }

    JBLogDebug("remap dyld=%p prot=%x/%x", remoteLoadAddress, cur_prot, max_prot);

    uint64_t bsd_proc = proc_find(pid);
    if(!bsd_proc) {
        JBLogError("proc_find %d failed", pid);
        goto failed;
    }
    uint64_t mach_task = proc_task(bsd_proc);
    if(!mach_task) {
        JBLogError("proc_task %d failed", pid);
        goto failed;
    }

    if(spinlockFixOnly)
    {
        bool iOS15Arm64e = false;
#ifdef __arm64e__
        if (!__builtin_available(iOS 16.0, *))
        {
            iOS15Arm64e = true;
        }
#endif
        assert(iOS15Arm64e == true);
        assert(dyld_patch_enabled());

        uint64_t loadDyldCache_old = dyld_address + stockDyldInfo->loadDyldCache_function;
        uint64_t loadDyldCache_new = remoteLoadAddress + patchedDyldInfo->loadDyldCache_function;
        uint64_t loadDyldCache_orig = remoteLoadAddress + patchedDyldInfo->loadDyldCache_trampoline;

        cs_allow_invalid(bsd_proc, false);

        if(hook_dyld_function(task, loadDyldCache_old, loadDyldCache_new, loadDyldCache_orig) != 0) {
            JBLogError("hook dyld loadDyldCache failed");
            goto failed;
        }

        if(task_set_dyld_info(mach_task, dyld_address + stockDyldInfo->all_image_info_addr, stockDyldInfo->all_image_info_size) != 0) {
            JBLogError("task_set_dyld_info failed");
            goto failed;
        }

        //destroy macho header
        kr = vm_deallocate(task, remoteLoadAddress, PAGE_SIZE);
        if(kr != KERN_SUCCESS) {
            JBLogError("vm_deallocate failed: %d,%s", kr, mach_error_string(kr));
            goto failed;
        }

        goto final;
    }

    void* new_entry = (void*)(remoteLoadAddress + patchedDyldInfo->entrypoint);

    bool reentry = false;
    
    thread_act_array_t allThreads=NULL;
    mach_msg_type_number_t threadCount = 0;
    kr = task_threads(task, &allThreads, &threadCount);
    if(kr != KERN_SUCCESS) {
        JBLogError("task_threads failed: %d,%s", kr, mach_error_string(kr));
        goto failed;
    }
    if(threadCount == 0) {
        JBLogError("no thread found");
        goto failed;
    }

    for(int i=0; i<threadCount; i++)
    {
        JBLogDebug("allThreads[%d/%d]=%x", i, threadCount, allThreads[i]);

        arm_thread_state64_t threadState={0};
        mach_msg_type_number_t threadStateCount = ARM_THREAD_STATE64_COUNT;
        kr = thread_get_state(allThreads[i], ARM_THREAD_STATE64, (thread_state_t)&threadState, &threadStateCount);
        if(kr != KERN_SUCCESS) {
            JBLogError("thread_get_state %d,%s", kr, mach_error_string(kr));
            goto failed;
        }

        arm_thread_state64_t strippedState = threadState; /* some process such as WebContent used a different pac key
         cause we can't auth-and-resign it with __darwin_arm_thread_state64_get_* in current processs (crash) , so just strip all first */
        __darwin_arm_thread_state64_ptrauth_strip(strippedState);

        uint64_t strippedPC = (uint64_t)__darwin_arm_thread_state64_get_pc(strippedState);
        uint64_t strippedSP = (uint64_t)__darwin_arm_thread_state64_get_sp(strippedState);
        uint64_t strippedFP = (uint64_t)__darwin_arm_thread_state64_get_fp(strippedState);
        uint64_t strippedLR = (uint64_t)__darwin_arm_thread_state64_get_lr(strippedState);
        JBLogDebug("strippedState PC=%llx SP=%llx FP=%llx LR=%llx", strippedPC, strippedSP, strippedFP, strippedLR);

        if(strippedPC == dyld_entry)
        {
            JBLogDebug("dyld entrypoint found in thread[%d]:%x", i, allThreads[i]);

#ifdef __arm64e__
            void* savedPC = threadState.__opaque_pc;
            void* resignedPC = ptrauth_sign_unauthenticated((void*)strippedPC, ptrauth_key_process_independent_code, 0);
            __darwin_arm_thread_state64_set_pc_fptr(threadState, resignedPC);
            if(threadState.__opaque_pc != savedPC) {
                JBLogDebug("target process(%d) used a different pac key, %s", pid, proc_get_path(pid,NULL));

                cs_allow_invalid(bsd_proc, false);

                if(hook_dyld_entry(task, dyld_address, dyld_entry, (uint64_t)new_entry) != 0) {
                    JBLogError("hook_dyld_entry failed");
                    goto reentry_end;
                }

                reentry = true;
                break;
            }
#endif

#ifdef __arm64e__
            new_entry = ptrauth_sign_unauthenticated(new_entry, ptrauth_key_process_independent_code, 0);
#endif
            __darwin_arm_thread_state64_set_pc_fptr(threadState, new_entry);
            kr = thread_set_state(allThreads[i], ARM_THREAD_STATE64, (thread_state_t)&threadState, threadStateCount);
            if(kr != KERN_SUCCESS) {
                JBLogError("thread_set_state failed: %d,%s", kr, mach_error_string(kr));
                goto reentry_end;
            }

            kr = vm_deallocate(task, dyld_address, stockDyldInfo->vmSpaceSize);
            if(kr != KERN_SUCCESS) {
                JBLogError("vm_deallocate old dyld failed: %d,%s", kr, mach_error_string(kr));
                goto reentry_end;
            }

            reentry = true;
            break;
        }
    }

reentry_end:
    for(int i=0; i<threadCount; i++) {
        mach_port_deallocate(mach_task_self(), allThreads[i]);
    }
    vm_deallocate(mach_task_self(), (mach_vm_address_t)allThreads, threadCount*sizeof(allThreads[0]));

    if(!reentry) {
        JBLogError("dyld entrypoint udpate failed");
        goto failed;
    }

    if(task_set_dyld_info(mach_task, remoteLoadAddress + patchedDyldInfo->all_image_info_addr, patchedDyldInfo->all_image_info_size) != 0) {
        JBLogError("task_set_dyld_info failed");
        goto failed;
    }

    JBLogDebug("dyld all_image_info update: %p -> %p", (void*)(dyld_address + stockDyldInfo->all_image_info_addr), (void*)(remoteLoadAddress + patchedDyldInfo->all_image_info_addr));


    //patchedtest(task, remoteLoadAddress);

    JBLogDebug("dyld entrypoint updated: %p -> %p", (void*)dyld_entry, new_entry);
    goto final;

failed:
    ret = -1;
    if(remoteLoadAddress) {
        vm_deallocate(task, remoteLoadAddress, patchedDyldInfo->vmSpaceSize);
    }

final:
    if(MACH_PORT_VALID(task)) mach_port_deallocate(mach_task_self(), task);
    return ret;
}

int proc_patch_dyld(pid_t pid)
{
    return proc_patch_dyld_internal(pid, false);
}

int proc_fix_spinlock(pid_t pid)
{
    return proc_patch_dyld_internal(pid, true);
}
