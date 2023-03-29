#import "substrate.h"
#import <spawn.h>

void boomerang_userspaceRebootIncoming()
{
	pid_t boomerangPid = 0;
	int ret = posix_spawn(&boomerangPid, "/var/jb/basebin/boomerang", NULL, NULL, NULL, NULL);

	// TODO: Pass primitives
}
