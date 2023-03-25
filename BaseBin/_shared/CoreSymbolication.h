//
//  CoreSymbolication.h
//
//  Created by R J Cooper on 05/06/2012.
//  This file: Copyright (c) 2012 Mountainstorm
//  API: Copyright (c) 2008 Apple Inc. All rights reserved.
//  
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//  
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//  
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

//
// Derived by looking at use within the dtrace source and a little bit of IDA work
//
// See the unit testcases for examples of how to use the API; its a really nice symbol
// api, a real shame Apple dont make it a public framework. 
//
// Things you might want to know;
//  - a Symbolicator is a top level object representing the kernel/process etc
//  - a Symbolicator contains multiple SymbolOwners
// 
//  - a SymbolOwner represents a blob which owns symbols e.g. executable, library
//  - a SymbolOwner contains multiple regions and contains multiple symbols
//
//  - a Region represents a continuous block of memory within a symbol owner e.g. the  __TEXT __objc_classname section
//  - a Region contains multiple symbols ... not it doesn't own them, just contains them
//
//  - a Symbol represents a symbol e.g. function, variable
//

#if !defined(__CORESYMBOLICATION_CORESYMBOLICATION__)
#define __CORESYMBOLICATION_CORESYMBOLICATION__ 1
#define __CORESYMBOLICATION__ 1

#ifdef __cplusplus
extern "C" {
#endif

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>


/*
 * Types
 */
// Under the hood the framework basically just calls through to a set of C++ libraries
struct sCSTypeRef {
	void* csCppData;	// typically retrieved using CSCppSymbol...::data(csData & 0xFFFFFFF8)
	void* csCppObj;		// a pointer to the actual CSCppObject
};
typedef struct sCSTypeRef CSTypeRef;


typedef CSTypeRef CSSymbolicatorRef;
typedef CSTypeRef CSSourceInfoRef;
typedef CSTypeRef CSSymbolOwnerRef;
typedef CSTypeRef CSSectionRef;
typedef CSTypeRef CSSegmentRef;
typedef CSTypeRef CSSymbolRef;
typedef CSTypeRef CSRegionRef;
typedef CSTypeRef CSUUIDRef;


struct sCSRange {
   unsigned long long location;
   unsigned long long length;
};
typedef struct sCSRange CSRange;


// Note: this structure may well be wrong
typedef struct sCSNotificationData {
	CSSymbolicatorRef symbolicator;
	union {
		struct {
			long value;
		} ping;
		
		struct {
			CSSymbolOwnerRef symbolOwner;
		} dyldLoad;
	} u;
} CSNotificationData;


typedef void* CSDictionaryKeyCallBacks;
typedef void* CSDictionaryValueCallBacks;
typedef void* CSSetCallBacks;


typedef int (^CSNotification)(uint32_t notification_type, CSNotificationData data);
typedef int (^CSRegionIterator)(CSRegionRef region);
typedef int (^CSSymbolOwnerIterator)(CSSymbolOwnerRef owner);
typedef int (^CSSectionIterator)(CSSectionRef section);
typedef int (^CSSourceInfoIterator)(CSSourceInfoRef sourceInfo);
typedef int (^CSSymbolIterator)(CSSymbolRef symbol);
typedef int (^CSSegmentIterator)(CSSegmentRef segment);


/*
 * Defines
 */
#define kCSNull								((CSTypeRef) {NULL, NULL})
#define kCSNow								0x8000000000000000ull
// we've no idea what value kCSSymbolOwnerDataFoundDsym has; its only use in dtrace has been optimised out
#define kCSSymbolOwnerDataFoundDsym			0
#define kCSSymbolOwnerIsAOut				0
#define kCSSymbolicatorTrackDyldActivity	1

#define kCSNotificationPing					1
#define kCSNotificationInitialized			0x0010
#define kCSNotificationDyldLoad				0x0100
#define kCSNotificationDyldUnload			0x0101
// kCSNotificationTimeout must be a value greater than 0x1001
#define kCSNotificationTimeout				0x1002
#define kCSNotificationTaskExit				0x1000
#define kCSNotificationFini					0x80000000


/*
 * External symbols
 */

extern const char* kCSRegionMachHeaderName;
extern const CSDictionaryKeyCallBacks kCSTypeDictionaryKeyCallBacks;
extern const CSDictionaryValueCallBacks kCSTypeDictionaryValueCallBacks;
extern const CSDictionaryKeyCallBacks kCSTypeDictionaryWeakKeyCallBacks;
extern const CSDictionaryValueCallBacks kCSTypeDictionaryWeakValueCallBacks;
extern const CSSetCallBacks kCSTypeSetCallBacks;
extern const CSSetCallBacks kCSTypeSetWeakCallBacks;


/*
 * Architecture functions
 */
// Valid names: i386, x86_64, arm, armv4t, armv5tej, armv6, armv7, armv7f, armv7k, ppc, ppc64
cpu_type_t CSArchitectureGetArchitectureForName(const char* arch);
cpu_type_t CSArchitectureGetCurrent();
cpu_type_t CSArchitectureGetFamily(cpu_type_t type);
const char* CSArchitectureGetFamilyName(cpu_type_t type);

Boolean CSArchitectureIs32Bit(cpu_type_t type);
Boolean CSArchitectureIs64Bit(cpu_type_t type);
Boolean CSArchitectureIsArm(cpu_type_t type);
Boolean CSArchitectureIsBigEndian(cpu_type_t type);
Boolean CSArchitectureIsI386(cpu_type_t type);
Boolean CSArchitectureIsLittleEndian(cpu_type_t type);
Boolean CSArchitectureIsPPC(cpu_type_t type);
Boolean CSArchitectureIsPPC64(cpu_type_t type);
Boolean CSArchitectureIsX86_64(cpu_type_t type);

Boolean CSArchitectureMatchesArchitecture(cpu_type_t a, cpu_type_t b);


/*
 * Description functions
 */
CFStringRef CSCopyDescription(CSTypeRef cs);
CFStringRef CSCopyDescriptionWithIndent(CSTypeRef cs, unsigned int indent);


/*
 * General utility functions
 */
Boolean CSEqual(CSTypeRef cs1, CSTypeRef cs2);
//XXX: CSExceptionSafeThreadRunBlock
CFIndex CSGetRetainCount(CSTypeRef cs);
Boolean CSIsNull(CSTypeRef cs);
CSTypeRef CSRetain(CSTypeRef cs);
void CSRelease(CSTypeRef cs);
void CSShow(CSTypeRef cs);


/*
 * Dyld functions
 */
vm_address_t CSGetDyldSharedCacheSlide(mach_port_t port);
CSUUIDRef CSGetDyldSharedCacheUUID(mach_port_t port);


/*
 * XXX: Map functions
 */
//CSMMapArchiveCacheCopyMMapArchive
//CSMMapArchiveCacheReleaseMMapArchive
//CSMMapArchiveCacheSetShouldStoreToDaemon


/*
 * Range functions
 */
Boolean CSRangeContainsRange(CSRange r1, CSRange r2);
Boolean CSRangeIntersectsRange(CSRange r1, CSRange r2);


/*
 * Region functions
 */
CFStringRef CSRegionCopyDescriptionWithIndent(CSRegionRef region, unsigned int indent);
int CSRegionForeachSourceInfo(CSRegionRef region, CSSourceInfoIterator each);
int CSRegionForeachSymbol(CSRegionRef region, CSSymbolIterator each);
const char* CSRegionGetName(CSRegionRef region);
CSRange CSRegionGetRange(CSRegionRef region);
CSSymbolOwnerRef CSRegionGetSymbolOwner(CSRegionRef region);
CSSymbolicatorRef CSRegionGetSymbolicator(CSRegionRef region);


/*
 * XXX: Section/Segment functions
 */
/*
CSSectionGetSegment
CSSegmentForeachSection
*/


/*
 * XXX: Signature functions
 */
/*
CSSignatureAddSegment
CSSignatureAllocateSegments
CSSignatureCopy
CSSignatureEncodeSymbolOwner
CSSignatureEncodeSymbolicator
CSSignatureFreeSegments
*/


/*
 * Source Info functions
 */
CFStringRef CSSourceInfoCopyDescriptionWithIndent(CSSourceInfoRef info, unsigned int indent);
int CSSourceInfoGetColumn(CSSourceInfoRef info);
const char* CSSourceInfoGetFilename(CSSourceInfoRef info);
int CSSourceInfoGetLineNumber(CSSourceInfoRef info);
const char* CSSourceInfoGetPath(CSSourceInfoRef info);
CSRange CSSourceInfoGetRange(CSSourceInfoRef info);
CSRegionRef CSSourceInfoGetRegion(CSSourceInfoRef info);
CSSymbolRef CSSourceInfoGetSymbol(CSSourceInfoRef info);
CSSymbolOwnerRef CSSourceInfoGetSymbolOwner(CSSourceInfoRef info);
CSSymbolicatorRef CSSourceInfoGetSymbolicator(CSSourceInfoRef info);


/*
 * Symbol functions
 */

CFStringRef CSSymbolCopyDescriptionWithIndent(CSSymbolRef sym, unsigned int indent);
int CSSymbolForeachSourceInfo(CSSymbolRef sym, CSSourceInfoIterator);
long CSSymbolGetFlags(CSSymbolRef sym);
CSTypeRef CSSymbolGetInstructionData(CSSymbolRef sym);
const char* CSSymbolGetMangledName(CSSymbolRef sym);
const char* CSSymbolGetName(CSSymbolRef sym);
CSRange CSSymbolGetRange(CSSymbolRef sym);
CSRegionRef CSSymbolGetRegion(CSSymbolRef sym);
CSSectionRef CSSymbolGetSection(CSSymbolRef sym);
CSSegmentRef CSSymbolGetSegment(CSSymbolRef sym);
CSSymbolOwnerRef CSSymbolGetSymbolOwner(CSSymbolRef sym);
CSSymbolicatorRef CSSymbolGetSymbolicator(CSSymbolRef sym);
Boolean CSSymbolIsArm(CSSymbolRef sym);
Boolean CSSymbolIsDebugMap(CSSymbolRef sym);
Boolean CSSymbolIsDwarf(CSSymbolRef sym);
Boolean CSSymbolIsDyldStub(CSSymbolRef sym);
Boolean CSSymbolIsExternal(CSSymbolRef sym);
Boolean CSSymbolIsFunction(CSSymbolRef sym);
Boolean CSSymbolIsFunctionStarts(CSSymbolRef sym);
Boolean CSSymbolIsKnownLength(CSSymbolRef sym);
Boolean CSSymbolIsMangledNameSourceDwarf(CSSymbolRef sym);
Boolean CSSymbolIsMangledNameSourceDwarfMIPSLinkage(CSSymbolRef sym);
Boolean CSSymbolIsMangledNameSourceNList(CSSymbolRef sym);
Boolean CSSymbolIsMerged(CSSymbolRef sym);
Boolean CSSymbolIsNList(CSSymbolRef sym);
Boolean CSSymbolIsNameSourceDwarf(CSSymbolRef sym);
Boolean CSSymbolIsNameSourceDwarfMIPSLinkage(CSSymbolRef sym);
Boolean CSSymbolIsNameSourceNList(CSSymbolRef sym);
Boolean CSSymbolIsObjcMethod(CSSymbolRef sym);
Boolean CSSymbolIsOmitFramePointer(CSSymbolRef sym);
Boolean CSSymbolIsPrivateExternal(CSSymbolRef sym);
Boolean CSSymbolIsThumb(CSSymbolRef sym);
Boolean CSSymbolIsUnnamed(CSSymbolRef sym);


/*
 * XXX: SymbolOwner functions
 */
/*
CSSymbolOwnerAddInContext
CSSymbolOwnerCacheFlush
CSSymbolOwnerCacheGetEntryCount
CSSymbolOwnerCacheGetFlags
CSSymbolOwnerCacheGetMemoryLimit
CSSymbolOwnerCacheGetMemoryUsed
CSSymbolOwnerCachePrintEntries
CSSymbolOwnerCachePrintStats
CSSymbolOwnerCacheResetStats
CSSymbolOwnerCacheSetFlags
CSSymbolOwnerCacheSetMemoryLimit
CSSymbolOwnerCopyDescriptionWithIndent
CSSymbolOwnerCreateSignature
CSSymbolOwnerEditRelocations
CSSymbolOwnerForeachRegion
CSSymbolOwnerForeachRegionWithName
CSSymbolOwnerForeachSection
CSSymbolOwnerForeachSegment
CSSymbolOwnerForeachSourceInfo
CSSymbolOwnerForeachSymbol
CSSymbolOwnerForeachSymbolWithMangledName
CSSymbolOwnerForeachSymbolWithName
CSSymbolOwnerGetArchitecture
CSSymbolOwnerGetBaseAddress
CSSymbolOwnerGetCompatibilityVersion
CSSymbolOwnerGetCurrentVersion
CSSymbolOwnerGetDataFlags
CSSymbolOwnerGetDataTypeID
CSSymbolOwnerGetDsymPath
CSSymbolOwnerGetDsymVersion
CSSymbolOwnerGetFlags
CSSymbolOwnerGetLastModifiedTimestamp
CSSymbolOwnerGetLoadTimestamp
CSSymbolOwnerGetName
CSSymbolOwnerGetPath
CSSymbolOwnerGetRegionCount
CSSymbolOwnerGetRegionWithAddress
CSSymbolOwnerGetRegionWithName
CSSymbolOwnerGetSectionWithAddress
CSSymbolOwnerGetSectionWithName
CSSymbolOwnerGetSegmentWithAddress
CSSymbolOwnerGetSourceInfoCount
CSSymbolOwnerGetSourceInfoWithAddress
CSSymbolOwnerGetSymbolCount
CSSymbolOwnerGetSymbolWithAddress
CSSymbolOwnerGetSymbolWithMangledName
CSSymbolOwnerGetSymbolWithName
CSSymbolOwnerGetSymbolicator
CSSymbolOwnerGetTransientUserData
CSSymbolOwnerGetUUID
CSSymbolOwnerGetUnloadTimestamp
CSSymbolOwnerGetVersion
CSSymbolOwnerIsAOut
CSSymbolOwnerIsBundle
CSSymbolOwnerIsCommpage
CSSymbolOwnerIsDsym
CSSymbolOwnerIsDyld
CSSymbolOwnerIsDyldSharedCache
CSSymbolOwnerIsDylib
CSSymbolOwnerIsDylibStub
CSSymbolOwnerIsKextBundle
CSSymbolOwnerIsMachO
CSSymbolOwnerIsMutable
CSSymbolOwnerIsObjCGCSupported
CSSymbolOwnerIsObjCRetainReleaseSupported
CSSymbolOwnerIsObject
CSSymbolOwnerIsObsolete
CSSymbolOwnerIsPIE
CSSymbolOwnerIsProtected
CSSymbolOwnerIsRestricted
CSSymbolOwnerIsSlid
CSSymbolOwnerIsStaticLibraryArchiveEntry
CSSymbolOwnerMakeMutableInContext
CSSymbolOwnerRemoveInContext
CSSymbolOwnerSetLoadTimestamp
CSSymbolOwnerSetPath
CSSymbolOwnerSetRelocationCount
CSSymbolOwnerSetTransientUserData
CSSymbolOwnerSetUnloadTimestamp
*/


/*
 * XXX: Symbolicator functions
 */
// XXX: CSSymbolicatorAddSymbolOwner
// XXX: CSSymbolicatorApplyMutableContextBlock
CFStringRef CSSymbolicatorCopyDescriptionWithIndent(CSSymbolicatorRef cs, unsigned int indent);
CFDataRef CSSymbolicatorCreateSignature(CSSymbolicatorRef cs);

CSSymbolicatorRef CSSymbolicatorCreateWithMachKernel(void);
CSSymbolicatorRef CSSymbolicatorCreateWithMachKernelFlagsAndNotification(long flags, CSNotification notification);
CSSymbolicatorRef CSSymbolicatorCreateWithPathAndArchitecture(const char* path, cpu_type_t type);
CSSymbolicatorRef CSSymbolicatorCreateWithPathArchitectureFlagsAndNotification(const char* path, cpu_type_t type, long flags, CSNotification notification);
CSSymbolicatorRef CSSymbolicatorCreateWithPid(pid_t pid);
CSSymbolicatorRef CSSymbolicatorCreateWithPidFlagsAndNotification(pid_t pid, long flags, CSNotification notification);
CSSymbolicatorRef CSSymbolicatorCreateWithSignature(CFDataRef sig);
CSSymbolicatorRef CSSymbolicatorCreateWithSignatureAndNotification(CFDataRef sig, CSNotification notification);
CSSymbolicatorRef CSSymbolicatorCreateWithTask(task_t task);
CSSymbolicatorRef CSSymbolicatorCreateWithTaskFlagsAndNotification(task_t task, long flags, CSNotification notification);
CSSymbolicatorRef CSSymbolicatorCreateWithURLAndArchitecture(CFURLRef url, cpu_type_t type);
CSSymbolicatorRef CSSymbolicatorCreateWithURLArchitectureFlagsAndNotification(CFURLRef url, cpu_type_t type, long flags, CSNotification notification);

int CSSymbolicatorForceFullSymbolExtraction(CSSymbolicatorRef cs);
int CSSymbolicatorForeachRegionAtTime(CSSymbolicatorRef cs, uint64_t time, CSRegionIterator it);
int CSSymbolicatorForeachRegionWithNameAtTime(CSSymbolicatorRef cs, const char* name, uint64_t time, CSRegionIterator it);
int CSSymbolicatorForeachSectionAtTime(CSSymbolicatorRef cs, uint64_t time, CSSectionIterator it);
int CSSymbolicatorForeachSegmentAtTime(CSSymbolicatorRef cs, uint64_t time, CSSegmentIterator it);
// XXX: CSSymbolicatorForeachSharedCache
// XXX: CSSymbolicatorForeachSharedCacheSymbolicatorWithFlagsAndNotification
int CSSymbolicatorForeachSourceInfoAtTime(CSSymbolicatorRef cs, uint64_t time, CSSourceInfoIterator it);
int CSSymbolicatorForeachSymbolAtTime(CSSymbolicatorRef cs, uint64_t time, CSSymbolIterator it);
int CSSymbolicatorForeachSymbolOwnerAtTime(CSSymbolicatorRef cs, uint64_t time, CSSymbolOwnerIterator it);

// XXX: CSSymbolicatorForeachSymbolOwnerWithCFUUIDBytesAtTime
int CSSymbolicatorForeachSymbolOwnerWithFlagsAtTime(CSSymbolicatorRef symbolicator, long flags, uint64_t time, CSSymbolOwnerIterator it);
int CSSymbolicatorForeachSymbolOwnerWithNameAtTime(CSSymbolicatorRef cs, const char* name, uint64_t time, CSSymbolOwnerIterator it);
int CSSymbolicatorForeachSymbolOwnerWithPathAtTime(CSSymbolicatorRef cs, const char* name, uint64_t time, CSSymbolOwnerIterator it);
// XXX: CSSymbolicatorForeachSymbolOwnerWithUUIDAtTime
int CSSymbolicatorForeachSymbolWithMangledNameAtTime(CSSymbolicatorRef cs, const char* name, uint64_t time, CSSymbolIterator it);
int CSSymbolicatorForeachSymbolWithNameAtTime(CSSymbolicatorRef cs, const char* name, uint64_t time, CSSymbolIterator it);
// XXX: CSSymbolicatorForeachSymbolicatorWithPath
// XXX: CSSymbolicatorForeachSymbolicatorWithPathFlagsAndNotification
// XXX: CSSymbolicatorForeachSymbolicatorWithURL
// XXX: CSSymbolicatorForeachSymbolicatorWithURLFlagsAndNotification

CSSymbolOwnerRef CSSymbolicatorGetAOutSymbolOwner(CSSymbolicatorRef cs);
cpu_type_t CSSymbolicatorGetArchitecture(CSSymbolicatorRef cs);
vm_address_t CSSymbolicatorGetDyldAllImageInfosAddress(CSSymbolicatorRef cs);

long CSSymbolicatorGetFlagsForDebugMapOnlyData(void);
long CSSymbolicatorGetFlagsForDsymOnlyData(void);
long CSSymbolicatorGetFlagsForDwarfOnlyData(void);
long CSSymbolicatorGetFlagsForFunctionStartsOnlyData(void);
long CSSymbolicatorGetFlagsForNListOnlyData(void);
long CSSymbolicatorGetFlagsForNoSymbolOrSourceInfoData(void);

pid_t CSSymbolicatorGetPid(CSSymbolicatorRef cs);
int CSSymbolicatorGetRegionCountAtTime(CSSymbolicatorRef cs, uint64_t time);
CSRegionRef CSSymbolicatorGetRegionWithAddressAtTime(CSSymbolicatorRef cs, vm_address_t addr, uint64_t time);
CSRegionRef CSSymbolicatorGetRegionWithNameAtTime(CSSymbolicatorRef cs, const char* name, uint64_t time);
CSSectionRef CSSymbolicatorGetSectionWithAddressAtTime(CSSymbolicatorRef cs, vm_address_t addr, uint64_t time);
CSSegmentRef CSSymbolicatorGetSegmentWithAddressAtTime(CSSymbolicatorRef cs, vm_address_t addr, uint64_t time);
vm_address_t CSSymbolicatorGetSharedCacheSlide(CSSymbolicatorRef cs);
CSUUIDRef CSSymbolicatorGetSharedCacheUUID(CSSymbolicatorRef cs);
int CSSymbolicatorGetSourceInfoCountAtTime(CSSymbolicatorRef cs, uint64_t time);
CSSourceInfoRef CSSymbolicatorGetSourceInfoWithAddressAtTime(CSSymbolicatorRef cs, vm_address_t addr, uint64_t time);
int CSSymbolicatorGetSymbolCountAtTime(CSSymbolicatorRef cs, uint64_t time);
CSSymbolOwnerRef CSSymbolicatorGetSymbolOwner(CSSymbolicatorRef cs);
int CSSymbolicatorGetSymbolOwnerCountAtTime(CSSymbolicatorRef cs, uint64_t time);
CSSymbolOwnerRef CSSymbolicatorGetSymbolOwnerWithAddressAtTime(CSSymbolicatorRef cs, vm_address_t addr, uint64_t time);
// XXX: CSSymbolicatorGetSymbolOwnerWithCFUUIDBytesAtTime
CSSymbolOwnerRef CSSymbolicatorGetSymbolOwnerWithNameAtTime(CSSymbolicatorRef cs, const char* name, uint64_t time);
CSSymbolOwnerRef CSSymbolicatorGetSymbolOwnerWithUUIDAtTime(CSSymbolicatorRef symbolicator, CFUUIDRef uuid, uint64_t time);
CSSymbolRef CSSymbolicatorGetSymbolWithAddressAtTime(CSSymbolicatorRef cs, vm_address_t addr, uint64_t time);
CSSymbolRef CSSymbolicatorGetSymbolWithMangledNameAtTime(CSSymbolicatorRef cs, const char* name, uint64_t time);
CSSymbolRef CSSymbolicatorGetSymbolWithMangledNameFromSymbolOwnerWithNameAtTime(CSSymbolicatorRef cs, CSSymbolOwnerRef owner, const char* name, uint64_t time);
CSSymbolRef CSSymbolicatorGetSymbolWithNameAtTime(CSSymbolicatorRef cs, const char* name, uint64_t time);
CSSymbolRef CSSymbolicatorGetSymbolWithNameFromSymbolOwnerWithNameAtTime(CSSymbolicatorRef cs, CSSymbolOwnerRef owner, const char* name, uint64_t time);
mach_port_t CSSymbolicatorGetTask(CSSymbolicatorRef cs);
Boolean CSSymbolicatorIsKernelSymbolicator(CSSymbolicatorRef cs);
Boolean CSSymbolicatorIsTaskTranslated(CSSymbolicatorRef cs);
Boolean CSSymbolicatorIsTaskValid(CSSymbolicatorRef cs);
void CSSymbolicatorResymbolicate(CSSymbolicatorRef cs);
void CSSymbolicatorResymbolicateFail(CSSymbolicatorRef cs);
int CSSymbolicatorSetForceGlobalSafeMachVMReads(CSSymbolicatorRef cs);


/*
 * XXX: CSUUID
 */
 /*
CSUUIDCFUUIDBytesToPath
CSUUIDCFUUIDBytesToString
CSUUIDStringToCFUUIDBytes
*/




/*
 * SymbolOwner functions
 */
const char* CSSymbolOwnerGetPath(CSSymbolOwnerRef symbol);
const char* CSSymbolOwnerGetName(CSSymbolOwnerRef symbol);
vm_address_t CSSymbolOwnerGetBaseAddress(CSSymbolOwnerRef owner);
cpu_type_t CSSymbolOwnerGetArchitecture(CSSymbolOwnerRef owner);
Boolean CSSymbolOwnerIsObject(CSSymbolOwnerRef owner);
long CSSymbolOwnerGetDataFlags(CSSymbolOwnerRef owner);
CSRegionRef CSSymbolOwnerGetRegionWithName(CSSymbolOwnerRef owner, const char* name);
CSSymbolRef CSSymbolOwnerGetSymbolWithName(CSSymbolOwnerRef owner, const char* name);
CSSymbolRef CSSymbolOwnerGetSymbolWithAddress(CSSymbolOwnerRef owner, mach_vm_address_t addr);

long CSSymbolOwnerForeachSymbol(CSSymbolOwnerRef owner, CSSymbolIterator each);

CFUUIDBytes *CSSymbolOwnerGetCFUUIDBytes(CSSymbolOwnerRef owner);

/* Other exports

__crashreporter_info__
clear_mapped_memory
create_mapped_memory_cache_for_task
create_sampling_context_for_task
demangle
destroy_mapped_memory_cache
destroy_sampling_context
dispatch_queue_name_for_serial_number
find_node
fixup_frames
get_remote_thread_dispatch_queue

map_new_node
mapped_memory_read
mapped_memory_read_pointer
next_node
sample_remote_thread
sample_remote_thread_with_dispatch_queue
sampling_context_clear_cache
task_is_64bit
thread_name_for_thread_port
*/

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* ! __CORESYMBOLICATION_CORESYMBOLICATION__ */