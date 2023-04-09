#import <Foundation/Foundation.h>
#import <spawn.h>
#import "spawn_wrapper.h"
#import <libjailbreak/libjailbreak.h>
extern char **environ;

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
	int spawnError = posix_spawn(&task_pid, path.fileSystemRepresentation, NULL, NULL, (char *const *)argsC, environ);
	for (NSUInteger i = 0; i < argCount; i++)
	{
		free(argsC[i]);
	}
	free(argsC);
	if (spawnError != 0) return spawnError;
	do
	{
		if (waitpid(task_pid, &status, 0) != -1) {
			JBLogDebug("Child status %d", WEXITSTATUS(status));
		} else
		{
			perror("waitpid");
			return -222;
		}
	} while (!WIFEXITED(status) && !WIFSIGNALED(status));

	return WEXITSTATUS(status);
}