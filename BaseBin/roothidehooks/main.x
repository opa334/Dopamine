#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#include "common.h"

#ifndef DEBUG
#define NSLog(args...)	
#endif

NSString* safe_getExecutablePath()
{
	char executablePathC[PATH_MAX];
	uint32_t executablePathCSize = sizeof(executablePathC);
	_NSGetExecutablePath(&executablePathC[0], &executablePathCSize);
	return [NSString stringWithUTF8String:executablePathC];
}

NSString* getProcessName()
{
	return safe_getExecutablePath().lastPathComponent;
}

%ctor
{
	NSLog(@"roothidehooks coming... %@", safe_getExecutablePath());
	NSString *processName = getProcessName();
	/*if ([processName isEqualToString:@"installd"]) {
		extern void installdInit(void);
		installdInit();
	}
	else*/ if ([processName isEqualToString:@"cfprefsd"]) {
		extern void cfprefsdInit(void);
		cfprefsdInit();
	}
	else if ([processName isEqualToString:@"lsd"]) {
		extern void lsdInit(void);
		lsdInit();
	}
	else if ([processName isEqualToString:@"SpringBoard"]) {
		extern void sbInit(void);
		sbInit();
	}
}