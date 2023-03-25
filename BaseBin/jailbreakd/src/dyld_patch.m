#import <CoreSymbolication.h>
#import "codesign.h"
#import <dlfcn.h>

int applyDyldPatches(NSString *dyldPath)
{
	// Find offsets by abusing CoreSymbolication APIs
	void *csHandle = dlopen("/System/Library/PrivateFrameworks/CoreSymbolication.framework/CoreSymbolication", RTLD_NOW);
	CSSymbolicatorRef (*__CSSymbolicatorCreateWithPathAndArchitecture)(const char* path, cpu_type_t type) = dlsym(csHandle, "CSSymbolicatorCreateWithPathAndArchitecture");
	CSSymbolRef (*__CSSymbolicatorGetSymbolWithMangledNameAtTime)(CSSymbolicatorRef cs, const char* name, uint64_t time) = dlsym(csHandle, "CSSymbolicatorGetSymbolWithMangledNameAtTime");
	CSRange (*__CSSymbolGetRange)(CSSymbolRef sym) = dlsym(csHandle, "CSSymbolGetRange");
	CSSymbolicatorRef symbolicator = __CSSymbolicatorCreateWithPathAndArchitecture("/usr/lib/dyld", CPU_TYPE_ARM64);
	CSSymbolRef symbol = __CSSymbolicatorGetSymbolWithMangledNameAtTime(symbolicator, "__ZN5dyld413ProcessConfig8Security7getAMFIERKNS0_7ProcessERNS_15SyscallDelegateE", 0);
	CSRange range = __CSSymbolGetRange(symbol);
	uint64_t getAMFIOffset = range.location;
	if (getAMFIOffset == 0) {
		return 1;
	}

	FILE *dyldFile = fopen(dyldPath.fileSystemRepresentation, "rb+");
	if (!dyldFile) return 2;
	fseek(dyldFile, getAMFIOffset, SEEK_SET);
	uint32_t patchInstr[2] = { 
		0xD2801BE0, // mov x0, 0xDF
		0xD65F03C0  // ret
	};
	fwrite(patchInstr, sizeof(patchInstr), 1, dyldFile); 
	fclose(dyldFile);
	NSLog(@"patched dyld");

	int csRet = resignFile(dyldPath, true);
	if (csRet != 0) {
		return 3;
	}
	NSLog(@"resigned dyld");

	return 0;
}