#import <Foundation/Foundation.h>
#include <sys/sysctl.h>
#include <xpc/xpc.h>
#import <substrate.h>
#include <roothide.h>
#include "common.h"

#ifndef DEBUG
// #define NSLog(args...)	
#endif

#define kMobileKeyBagError (-1)
#define kMobileKeyBagDeviceIsUnlocked 0
#define kMobileKeyBagDeviceIsLocked 1
#define kMobileKeyBagDeviceLocking 2
#define kMobileKeyBagDisabled 3

%group coreauthd

bool __thread gFakePass = true;

%hookf(int, MKBGetDeviceLockState, CFDictionaryRef options)
{
	int ret = %orig;

	NSLog(@"MKBGetDeviceLockState: %@ -> %d", options, ret);

	if(gFakePass && ret == kMobileKeyBagDisabled) {
        ret = kMobileKeyBagDeviceIsUnlocked;
	}

	return ret;
}

%hookf(CFDictionaryRef, MKBGetDeviceLockStateInfo, CFDictionaryRef options)
{
	CFDictionaryRef ret = %orig;

	NSMutableDictionary* newret = ((__bridge NSDictionary*)ret).mutableCopy;

	if(gFakePass && [newret[@"ls"] longValue] == kMobileKeyBagDisabled)
	{
        newret[@"ls"] = @(kMobileKeyBagDeviceIsUnlocked);
	}

	NSLog(@"MKBGetDeviceLockStateInfo: %@ -> %@ -> %@", options, ret, newret);

	CFRelease(ret);
	return CFRetain((__bridge CFDictionaryRef)newret);
}

%hook Context
- (void*)evaluatePolicy:(long)policy options:(id)options uiDelegate:(id)delegate originator:(id)originator request:(id)request reply:(void(^)(NSDictionary*,NSError*))reply {
	NSLog(@"evaluatePolicy: %ld options: %@ uiDelegate: %@ originator: %@ request: %@ reply: %@", policy, options, delegate, originator, request, reply);

	NSNumber* _pid = [originator valueForKey:@"_processId"];
	pid_t pid = _pid.intValue;

	uint32_t csFlags = 0;
	csops(pid, CS_OPS_STATUS, &csFlags, sizeof(csFlags));

	gFakePass = (csFlags & CS_PLATFORM_BINARY)==0;
	void* ret = %orig;
	gFakePass = true;
	return ret;
}
%end

%end

%group securityd 

%hookf(Boolean, CFEqual, CFTypeRef cf1, CFTypeRef cf2)
{
	if(cf1==kSecAttrAccessibleWhenUnlockedThisDeviceOnly || cf2==kSecAttrAccessibleWhenUnlockedThisDeviceOnly) {
		if(%orig(cf1, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly) || %orig(cf2, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly)) {
            NSLog(@"hijacking %@ : %@", cf1, cf2);
			return YES; //akpu->aku
		}
	}
	else if(cf1==kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly || cf2==kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly) {
        NSLog(@"preventing %@ : %@", cf1, cf2);
		return NO;
	}

	return %orig;
}

%end

%group ctkd

%hookf(CFTypeRef, SecAccessControlGetProtection, SecAccessControlRef access_control)
{
	CFTypeRef ret = %orig;

	CFTypeRef newret = ret;
	if(CFEqual(ret, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly)) {
		newret = kSecAttrAccessibleWhenUnlockedThisDeviceOnly; //akpu->aku
	}
	NSLog(@"SecAccessControlGetProtection %@->%@ : %@", ret, newret, access_control);
	ret = newret;
	return ret;
}

%end


%group keybagd

%hook KBXPCService
- (void)changeSystemSecretfromOldSecret:(id)a3 oldSize:(uint64_t)a4 toNewSecret:(id)a5 newSize:(uint64_t)a6 opaqueData:(id)a7 reply:(id)a8
{
	NSLog(@"KBXPCService:changeSystemSecretfromOldSecret %@ %llu toNewSecret %@ %llu opaqueData %@ reply %@", a3, a4, a5, a6, a7, a8);
	return;
}
%end

%end


__attribute__((visibility("default"))) void palera1n()
{
	NSString* getProcessName();
	NSString *processName = getProcessName();
    NSLog(@"palera1n init %@", processName);

    cpu_subtype_t cpuFamily = 0;
    size_t cpuFamilySize = sizeof(cpuFamily);
    sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
    if(cpuFamily != CPUFAMILY_ARM_MONSOON_MISTRAL) { //A11 only
        return;
    }

    if ([processName isEqualToString:@"coreauthd"]) {
	    MSImageRef MobileKeyBagImage = MSGetImageByName("/System/Library/PrivateFrameworks/MobileKeyBag.framework/MobileKeyBag");
        %init(coreauthd, MKBGetDeviceLockState = MSFindSymbol(MobileKeyBagImage, "_MKBGetDeviceLockState"), MKBGetDeviceLockStateInfo = MSFindSymbol(MobileKeyBagImage, "_MKBGetDeviceLockStateInfo"));
    }
    else if ([processName isEqualToString:@"securityd"]) {
        %init(securityd);
    }
    else if ([processName isEqualToString:@"ctkd"]) {
	    MSImageRef SecurityFramework = MSGetImageByName("/System/Library/Frameworks/Security.framework/Security");
        %init(ctkd, SecAccessControlGetProtection = MSFindSymbol(SecurityFramework, "_SecAccessControlGetProtection"));
	}
    else if ([processName isEqualToString:@"keybagd"]) {
        %init(keybagd);
    }
}
