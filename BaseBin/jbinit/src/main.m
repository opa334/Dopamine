#import <Foundation/Foundation.h>
#import <spawn.h>
#import <libjailbreak/libjailbreak.h>
#import "launchctl.h"

int main(int argc, char* argv[])
{
	NSString *idownloaddEnabledPath = prebootPath(@"basebin/LaunchDaemons/com.opa334.idownloadd.plist");
	NSString *idownloaddDisabledPath = prebootPath(@"basebin/LaunchDaemons/Disabled/com.opa334.idownloadd.plist");
	if (argc == 2) {
		char *cmd = argv[1];
		if (!strcmp(cmd, "start_idownload")) {
			if ([[NSFileManager defaultManager] fileExistsAtPath:idownloaddDisabledPath]) {
				[[NSFileManager defaultManager] moveItemAtPath:idownloaddDisabledPath toPath:idownloaddEnabledPath error:nil];
				launchctl_load(idownloaddEnabledPath.fileSystemRepresentation, false);
			}
			return 0;
		}
		else if (!strcmp(cmd, "stop_idownload")) {
			if ([[NSFileManager defaultManager] fileExistsAtPath:idownloaddEnabledPath]) {
				launchctl_load(idownloaddEnabledPath.fileSystemRepresentation, true);
				[[NSFileManager defaultManager] moveItemAtPath:idownloaddEnabledPath toPath:idownloaddDisabledPath error:nil];
			}
			return 0;
		}
	}
	launchctl_load(prebootPath(@"basebin/LaunchDaemons/com.opa334.jailbreakd.plist").fileSystemRepresentation, false);
	launchctl_load(prebootPath(@"basebin/LaunchDaemons/com.opa334.trustcache_rebuild.plist").fileSystemRepresentation, false);
}