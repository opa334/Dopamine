#import "launchctl.h"
#import <spawn.h>

int spawn(NSString* path, NSArray* args)
{
	NSMutableArray* argsM = args.mutableCopy ?: [NSMutableArray new];
	[argsM insertObject:path atIndex:0];

	NSUInteger argCount = [argsM count];
	char **argsC = (char **)malloc((argCount + 1) * sizeof(char*));

	for (NSUInteger i = 0; i < argCount; i++)
	{
		argsC[i] = strdup([[argsM objectAtIndex:i] UTF8String]);
	}
	argsC[argCount] = NULL;

	pid_t task_pid;
	int status = -200;
	int spawnError = posix_spawn(&task_pid, path.fileSystemRepresentation, NULL, NULL, (char *const *)argsC, NULL);
	for (NSUInteger i = 0; i < argCount; i++)
	{
		free(argsC[i]);
	}
	free(argsC);

	do
	{
		if (waitpid(task_pid, &status, 0) != -1) {
		} else
		{
			return -222;
		}
	} while (!WIFEXITED(status) && !WIFSIGNALED(status));

	return WEXITSTATUS(status);
}

int main(int argc, char* argv[])
{
	launchctlLoad("/var/jb/basebin/jailbreakd.plist");

	if (argc >= 2) {
		if (!strcmp(argv[1], "reinit")) {
			// After a userspace reboot, the launchd boot task will spawn this process with "reinit"
			// This means we are also resposible to load the other daemons
			spawn(@"/var/jb/usr/bin/launchctl", @[@"bootstrap", @"system", @"/var/jb/Library/LaunchDaemons"]);
		}
	}
}