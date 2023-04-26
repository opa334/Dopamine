#import <Foundation/Foundation.h>

NSString* safe_getExecutablePath()
{
	extern char*** _NSGetArgv();
	char* executablePathC = **_NSGetArgv();
	return [NSString stringWithUTF8String:executablePathC];
}

NSString* getProcessName()
{
	return safe_getExecutablePath().lastPathComponent;
}

%ctor
{
	NSString *processName = getProcessName();
	if ([processName isEqualToString:@"installd"]) {
		extern void installdInit(void);
		//installdInit();
	}
	else if ([processName isEqualToString:@"cfprefsd"]) {
		extern void cfprefsdInit(void);
		cfprefsdInit();
	}
}