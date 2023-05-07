#import "launchctl.h"
#import <spawn.h>
#import <libjailbreak/libjailbreak.h>

int main(int argc, char* argv[])
{
	launchctlLoad(prebootPath(@"basebin/LaunchDaemons/com.opa334.jailbreakd.plist").fileSystemRepresentation);
	launchctlLoad(prebootPath(@"basebin/LaunchDaemons/com.opa334.trustcache_rebuild.plist").fileSystemRepresentation);
}