#import "internal.h"
#import "dyldpatch.h"
#import "codesign.h"
#import <libjailbreak/carboncopy.h>
#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <sys/mount.h>

SInt32 CFUserNotificationDisplayAlert(CFTimeInterval timeout, CFOptionFlags flags, CFURLRef iconURL, CFURLRef soundURL, CFURLRef localizationURL, CFStringRef alertHeader, CFStringRef alertMessage, CFStringRef defaultButtonTitle, CFStringRef alternateButtonTitle, CFStringRef otherButtonTitle, CFOptionFlags *responseFlags) API_AVAILABLE(ios(3.0));

void initMountPath(NSString *mountPath)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    bool new = NO;

    if([fileManager fileExistsAtPath:mountPath]){
        NSString *newPath = NSJBRootPath(mountPath); 

        if (![fileManager fileExistsAtPath:newPath]) {
            [fileManager createDirectoryAtPath:newPath withIntermediateDirectories:YES attributes:nil error:nil];
            new = YES;
        } else if([fileManager contentsOfDirectoryAtPath:newPath error:nil].count == 0){
            new = YES;
        }

        if(new){
            NSString *tmpPath = [NSString stringWithFormat:@"%@_tmp", newPath];
            [fileManager copyItemAtPath:mountPath toPath:tmpPath error:nil];
            [fileManager removeItemAtPath:newPath error:nil];
            [fileManager moveItemAtPath:tmpPath toPath:newPath error:nil];
        }
    }
}

int jbctl_handle_internal(const char *command, int argc, char* argv[])
{
	if (!strcmp(command, "launchd_stash_port")) {
		mach_port_t *selfInitPorts = NULL;
		mach_msg_type_number_t selfInitPortsCount = 0;
		if (mach_ports_lookup(mach_task_self(), &selfInitPorts, &selfInitPortsCount) != 0) {
			printf("ERROR: Failed port lookup on self\n");
			return -1;
		}
		if (selfInitPortsCount < 3) {
			printf("ERROR: Unexpected initports count on self\n");
			return -1;
		}
		if (selfInitPorts[2] == MACH_PORT_NULL) {
			printf("ERROR: Port to stash not set\n");
			return -1;
		}

		printf("Port to stash: %u\n", selfInitPorts[2]);

		mach_port_t launchdTaskPort;
		if (task_for_pid(mach_task_self(), 1, &launchdTaskPort) != 0) {
			printf("task_for_pid on launchd failed\n");
			return -1;
		}
		mach_port_t *launchdInitPorts = NULL;
		mach_msg_type_number_t launchdInitPortsCount = 0;
		if (mach_ports_lookup(launchdTaskPort, &launchdInitPorts, &launchdInitPortsCount) != 0) {
			printf("mach_ports_lookup on launchd failed\n");
			return -1;
		}
		if (launchdInitPortsCount < 3) {
			printf("ERROR: Unexpected initports count on launchd\n");
			return -1;
		}
		launchdInitPorts[2] = selfInitPorts[2]; // Transfer port to launchd
		if (mach_ports_register(launchdTaskPort, launchdInitPorts, launchdInitPortsCount) != 0) {
			printf("ERROR: Failed stashing port into launchd\n");
			return -1;
		}
		mach_port_deallocate(mach_task_self(), launchdTaskPort);
		return 0;
	}
	else if (!strcmp(command, "fakelib_init")) {
		NSString *basebinPath = NSJBRootPath(@"/basebin");
		NSString *fakelibPath = NSJBRootPath(@"/basebin/.fakelib");
		printf("Initalizing fakelib...\n");

		// Copy /usr/lib to /var/jb/basebin/.fakelib
		[[NSFileManager defaultManager] removeItemAtPath:fakelibPath error:nil];
		[[NSFileManager defaultManager] createDirectoryAtPath:fakelibPath withIntermediateDirectories:YES attributes:nil error:nil];
		carbonCopy(@"/usr/lib", fakelibPath);

		// Backup and patch dyld
		NSString *dyldBackupPath = NSJBRootPath(@"/basebin/.dyld.orig");
		NSString *dyldPatchPath = NSJBRootPath(@"/basebin/.dyld.patched");
		carbonCopy(@"/usr/lib/dyld", dyldBackupPath);
		carbonCopy(@"/usr/lib/dyld", dyldPatchPath);
		apply_dyld_patch(dyldPatchPath.fileSystemRepresentation);
		resign_file(dyldPatchPath, YES);

		// Copy systemhook to fakelib
		carbonCopy(NSJBRootPath(@"/basebin/systemhook.dylib"), NSJBRootPath(@"/basebin/.fakelib/systemhook.dylib"));

		// Replace dyld in fakelib with patched dyld
		NSString *fakelibDyldPath = [fakelibPath stringByAppendingPathComponent:@"dyld"];
		[[NSFileManager defaultManager] removeItemAtPath:fakelibDyldPath error:nil];
		carbonCopy(dyldPatchPath, NSJBRootPath(@"/basebin/.fakelib/dyld"));
		return 0;
	}
	else if (!strcmp(command, "fakelib_mount")) {
		int ret = 10;
		// Mount fakelib on top of /usr/lib
		printf("Getting kernel ucred...\n");
		uint64_t orgUcred = 0;
		if (jbclient_root_steal_ucred(0, &orgUcred) == 0) {
			// Here we steal the kernel ucred
			// This allows us to mount to paths that would otherwise be restricted by sandbox
			printf("Applying mount...\n");
			ret = mount("bindfs", "/usr/lib", MNT_RDONLY, (void *)JBRootPath("/basebin/.fakelib"));
			// revert
			printf("Dropping kernel ucred...\n");
			jbclient_root_steal_ucred(orgUcred, NULL);
		}
		return ret;
	}
	else if (!strcmp(command, "startup")) {
		char *panicMessage = NULL;
		if (jbclient_watchdog_get_last_userspace_panic(&panicMessage) == 0) {
			NSString *printMessage = [NSString stringWithFormat:@"Dopamine has protected you from a userspace panic by temporarily disabling tweak injection and triggering a userspace reboot instead. A log is available under Analytics in the Preferences app. You can reenable tweak injection in the Dopamine app.\n\nPanic message: \n%s", panicMessage];
			CFUserNotificationDisplayAlert(0, 2/*kCFUserNotificationCautionAlertLevel*/, NULL, NULL, NULL, CFSTR("Watchdog Timeout"), (__bridge CFStringRef)printMessage, NULL, NULL, NULL, NULL);
			free(panicMessage);
		}
		exec_cmd(JBRootPath("/usr/bin/uicache"), "-a", NULL);
	}
	else if (!strcmp(command, "install_pkg")) {
		if (argc > 1) {
			extern char **environ;
			char *dpkg = JBRootPath("/usr/bin/dpkg");
			int r = execve(dpkg, (const char *[]){dpkg, "-i", argv[1], NULL}, environ);
			return r;
		}
		return -1;
	}
 	else if (!strcmp(command, "mount")) {
		int ret = 11;
		// Here we fake a mount
		printf("Getting kernel ucred...\n");
		uint64_t orgUcred = 0;
		if (jbclient_root_steal_ucred(0, &orgUcred) == 0) {
			// Here we steal the kernel ucred
			// This allows us to mount to paths that would otherwise be restricted by sandbox
			printf("Applying mount %s...\n",argv[1]);
			initMountPath([NSString stringWithUTF8String:argv[1]]);
			ret = mount("bindfs", argv[1], MNT_RDONLY, (void *)JBRootPath(argv[1]));
			printf("ret = %d\n",ret);
			// revert
			printf("Dropping kernel ucred...\n");
			jbclient_root_steal_ucred(orgUcred, NULL);
		}
		return ret;
	}
	else if (!strcmp(command, "unmount")) {
		int ret = 12;
		// Here we fake a mount
		printf("Getting kernel ucred...\n");
		uint64_t orgUcred = 0;
		if (jbclient_root_steal_ucred(0, &orgUcred) == 0) {
			// Here we steal the kernel ucred
			// This allows us to mount to paths that would otherwise be restricted by sandbox
			printf("Applying unmount %s\n",argv[1]);
			ret = unmount(argv[1], MNT_FORCE);
			printf("ret = %d\n",ret);
			// revert
			printf("Dropping kernel ucred...\n");
			jbclient_root_steal_ucred(orgUcred, NULL);
		}
		return ret;
	}
	return -1;
}
