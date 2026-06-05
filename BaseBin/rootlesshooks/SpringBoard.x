#import <Foundation/Foundation.h>
#import <substrate.h>
#import <objc/objc.h>
#import <libroot.h>
#import <fcntl.h>

bool string_has_prefix(const char *str, const char* prefix)
{
	if (!str || !prefix) {
		return false;
	}

	size_t str_len = strlen(str);
	size_t prefix_len = strlen(prefix);

	if (str_len < prefix_len) {
		return false;
	}

	return !strncmp(str, prefix, prefix_len);
}

@interface XBSnapshotContainerIdentity : NSObject <NSCopying>
@property (nonatomic, readonly, copy) NSString* bundleIdentifier;
- (NSString*)snapshotContainerPath;
@end

%hook XBSnapshotContainerIdentity

- (NSString *)snapshotContainerPath
{
	NSString *path = %orig;
	if([path hasPrefix:@"/var/mobile/Library/SplashBoard/Snapshots/"] && ![self.bundleIdentifier hasPrefix:@"com.apple."]) {
		return JBROOT_PATH_NSSTRING(path);
	}
	return path;
}

%end

int __fcntl(int fd, int cmd, long arg);
%hookf(int, __fcntl, int fd, int cmd, long arg)
{
    if (cmd == F_SETPROTECTIONCLASS) {
        char path[PATH_MAX];
        if (%orig(fd, F_GETPATH, (long)path) != -1 && string_has_prefix(path, JBROOT_PATH_CSTRING("/var/mobile/Library/SplashBoard/Snapshots")))
        {
            return 0; // Skip setting protection class on jailbreak apps, this doesn't work and causes snapshots to not be saved correctly
        }
    }
    return %orig(fd, cmd, arg);
}

void springboardInit(void)
{
	%init();
}
