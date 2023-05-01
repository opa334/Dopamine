#import <spawn.h>
#import <libfilecom/FCHandler.h>
#import <libjailbreak/libjailbreak.h>
#import <unistd.h>
#import <sys/param.h>
#import <sys/mount.h>

extern int (*posix_spawn_orig)(pid_t *restrict, const char *restrict, const posix_spawn_file_actions_t *restrict, const posix_spawnattr_t *restrict, char *const[restrict], char *const[restrict]);

void boomerang_userspaceRebootIncoming()
{
	// Fix Xcode debugging being broken after the userspace reboot
	unmount("/Developer", MNT_FORCE);

	pid_t boomerangPid = 0;

	// Wait until boomerang process has initialized primitives
	dispatch_semaphore_t sema = dispatch_semaphore_create(0);
	FCHandler *handler = [[FCHandler alloc] initWithReceiveFilePath:prebootPath(@"basebin/.communication/boomerang_to_launchd") sendFilePath:prebootPath(@"basebin/.communication/launchd_to_boomerang")];
	__weak FCHandler *weakHandler = handler;
	handler.receiveHandler = ^(NSDictionary *message) {
		NSString *identifier = message[@"id"];
		if (identifier) {
			if ([identifier isEqualToString:@"getPPLRW"]) {
				pid_t pid = [(NSNumber *)message[@"pid"] intValue];
				uint64_t magicPage = 0;
				int ret = handoffPPLPrimitives(pid, &magicPage);
				[weakHandler sendMessage:@{@"id" : @"receivePPLRW", @"magicPage" : @(magicPage), @"errCode" : @(ret)}];
			}
			else if ([identifier isEqualToString:@"signThreadState"]) {
				uint64_t actContextKptr = [(NSNumber*)message[@"actContext"] unsignedLongLongValue];
				signState(actContextKptr);
				[weakHandler sendMessage:@{@"id" : @"signedThreadState"}];
			}
			else if ([identifier isEqualToString:@"primitivesInitialized"])
			{
				dispatch_semaphore_signal(sema); // DONE, exit
			}
		}
	};

	int ret = posix_spawn_orig(&boomerangPid, prebootPath(@"basebin/boomerang").fileSystemRepresentation, NULL, NULL, NULL, NULL);
	if (ret != 0) return;

	dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
}
