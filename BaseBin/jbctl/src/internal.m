#import "internal.h"
#import "dyldpatch.h"
#import "carboncopy.h"
#import "codesign.h"
#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <sys/mount.h>

int jbctl_handle_internal(const char *command)
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
		const char *rootPathC = jbclient_get_root_path();
		if (!rootPathC) return 9;
		NSString *rootPath = [NSString stringWithUTF8String:rootPathC];
		NSString *basebinPath = [rootPath stringByAppendingPathComponent:@"basebin"];
		NSString *fakelibPath = [basebinPath stringByAppendingPathComponent:@".fakelib"];
		printf("Initalizing fakelib...\n");

		// Copy /usr/lib to /var/jb/basebin/.fakelib
		[[NSFileManager defaultManager] removeItemAtPath:fakelibPath error:nil];
		[[NSFileManager defaultManager] createDirectoryAtPath:fakelibPath withIntermediateDirectories:YES attributes:nil error:nil];
		carbonCopy(@"/usr/lib", fakelibPath);

		// Backup and patch dyld
		NSString *dyldBackupPath = [basebinPath stringByAppendingPathComponent:@".dyld.orig"];
		NSString *dyldPatchPath = [basebinPath stringByAppendingPathComponent:@".dyld.patched"];
		carbonCopy(@"/usr/lib/dyld", dyldBackupPath);
		carbonCopy(@"/usr/lib/dyld", dyldPatchPath);
		apply_dyld_patch(dyldPatchPath.fileSystemRepresentation);
		resign_file(dyldPatchPath, YES);

		// Replace dyld in fakelib with patched dyld
		NSString *fakelibDyldPath = [fakelibPath stringByAppendingPathComponent:@"dyld"];
		[[NSFileManager defaultManager] removeItemAtPath:fakelibDyldPath error:nil];
		carbonCopy(dyldPatchPath, fakelibDyldPath);
		return 0;
	}
	else if (!strcmp(command, "fakelib_mount")) {
		int ret = 10;
		const char *rootPathC = jbclient_get_root_path();
		if (!rootPathC) return 9;
		NSString *rootPath = [NSString stringWithUTF8String:rootPathC];
		NSString *basebinPath = [rootPath stringByAppendingPathComponent:@"basebin"];
		NSString *fakelibPath = [basebinPath stringByAppendingPathComponent:@".fakelib"];

		// Mount fakelib on top of /usr/lib
		printf("Getting kernel ucred...\n");
		uint64_t orgUcred = 0;
		if (jbclient_root_steal_ucred(0, &orgUcred) == 0) {
			// Here we steal the kernel ucred
			// This allows us to mount to paths that would otherwise be restricted by sandbox
			printf("Applying mount...\n");
			ret = mount("bindfs", "/usr/lib", MNT_RDONLY, (void *)fakelibPath.fileSystemRepresentation);

			// revert
			printf("Dropping kernel ucred...\n");
			jbclient_root_steal_ucred(orgUcred, NULL);
		}
		return ret;
	}
	return -1;
}