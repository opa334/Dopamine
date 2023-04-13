#import "launchctl.h"
#import <spawn.h>

int main(int argc, char* argv[])
{
	launchctlLoad("/var/jb/basebin/LaunchDaemons/com.opa334.jailbreakd.plist");
	launchctlLoad("/var/jb/basebin/LaunchDaemons/com.opa334.trustcache_rebuild.plist");
}