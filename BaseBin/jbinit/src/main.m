#import "launchctl.h"
#import <spawn.h>

int main(int argc, char* argv[])
{
	launchctlLoad("/var/jb/Library/LaunchDaemons/com.opa334.jailbreakd.plist");
}