#import <Foundation/Foundation.h>
#include <roothide.h>
#import <fcntl.h>
#include "common.h"

%hookf(int, fcntl, int fildes, int cmd, ...) {
	if (cmd == F_SETPROTECTIONCLASS) {
		char filePath[PATH_MAX];
		if (fcntl(fildes, F_GETPATH, filePath) != -1) {
			// Skip setting protection class on jailbreak apps, this doesn't work and causes snapshots to not be saved correctly
			if (isSubPathOf(filePath, jbroot("/var/mobile/Library/SplashBoard/Snapshots/"))) {
				return 0;
			}
		}
	}

	va_list a;
	va_start(a, cmd);
	const char *arg1 = va_arg(a, void *);
	const void *arg2 = va_arg(a, void *);
	const void *arg3 = va_arg(a, void *);
	const void *arg4 = va_arg(a, void *);
	const void *arg5 = va_arg(a, void *);
	const void *arg6 = va_arg(a, void *);
	const void *arg7 = va_arg(a, void *);
	const void *arg8 = va_arg(a, void *);
	const void *arg9 = va_arg(a, void *);
	const void *arg10 = va_arg(a, void *);
	va_end(a);
	return %orig(fildes, cmd, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10);
}

@interface XBSnapshotContainerIdentity : NSObject
@property NSString* bundleIdentifier;
@end

%hook XBSnapshotContainerIdentity

/*
-(id)_initWithBundleIdentifier:(id)arg1 bundlePath:(id)arg2 dataContainerPath:(id)arg3 bundleContainerPath:(id)arg4 
{
    NSLog(@"snapshot init, id=%@, bundlePath=%@, dataContainerPath=%@, bundleContainerPath=%@", arg1, arg2, arg3, arg4);

    return %orig;
}
*/

-(NSString *)snapshotContainerPath {
    NSString* path = %orig;

    if([path hasPrefix:@"/var/mobile/Library/SplashBoard/Snapshots/"] && (![self.bundleIdentifier hasPrefix:@"com.apple."] || is_apple_internal_identifier(self.bundleIdentifier.UTF8String))) {
        NSLog(@"snapshotContainerPath redirect %@ : %@", self.bundleIdentifier, path);
        path = jbroot(path);
    }

    return path;
}

%end

static const void *kDenyQueryTagKey = &kDenyQueryTagKey;

%hook FBSApplicationLibrary
-(id)applicationInfoForBundleIdentifier:(NSString*)bundleIdentifier
{
	id result = %orig; //SBApplicationInfo
	NSURL* executableURL = [result performSelector:@selector(executableURL)];
	NSLog(@"FBSApplicationLibrary applicationInfoForBundleIdentifier %@ : %@, %@", bundleIdentifier, result, executableURL);

	NSNumber* tag = objc_getAssociatedObject(bundleIdentifier, kDenyQueryTagKey);

	if(tag && tag.boolValue) {

		if(is_sensitive_app_identifier(bundleIdentifier.UTF8String)) {
			NSLog(@"FBSApplicationLibrary deny query %@", bundleIdentifier);
			return nil;
		}

		if(result && executableURL && isJailbreakBundlePath(executableURL.path.fileSystemRepresentation)) {
			NSLog(@"FBSApplicationLibrary deny query %@", bundleIdentifier);
			return nil;
		}
	}

	return result;
}
%end

%hook FBSystemService
-(void*)openApplication:(NSString*)bundleIdentifier withOptions:(id)options originator:(id)originator requestID:(void*)requestID completion:(void*)completion
{
	NSLog(@"openApplication %@ withOptions:%@ originator:%@ requestID:%@ completion:%p", bundleIdentifier, options, originator, requestID, completion);

	id currentContext = [NSClassFromString(@"BSServiceConnection") performSelector:@selector(currentContext)];
	id remoteProcess = [currentContext performSelector:@selector(remoteProcess)]; //BSProcessHandle

	NSNumber* _pid = [remoteProcess valueForKey:@"_pid"];
	NSString* _bundleID = [remoteProcess valueForKey:@"_bundleID"]; //may be nil

	pid_t pid = _pid.intValue;

	NSLog(@"openApplication %@ from pid=%d bundleID=%@", bundleIdentifier, pid, _bundleID);

	if(jbclient_blacklist_check_pid(pid)==true) {
		NSLog(@"openApplication deny request from %@", _bundleID);
		objc_setAssociatedObject(bundleIdentifier, kDenyQueryTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	return %orig;
}
%end

void sbInit(void)
{
	NSLog(@"sbInit...");
	%init();
}
