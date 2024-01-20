#import <libjailbreak/libjailbreak.h>
#import "internal.h"

int reboot3(uint64_t flags, ...);
#define RB2_USERREBOOT (0x2000000000000000llu)
extern char **environ;

void print_usage(void)
{
	printf("Usage: jbctl <command> <arguments>\n\
Available commands:\n\
	proc_set_debugged <pid>\t\tMarks the process with the given pid as being debugged, allowing invalid code pages inside of it\n\
	rebuild_trustcache\t\tRebuilds the TrustCache, clearing any previously trustcached files that no longer exists from it (automatically ran daily at midnight)\n\
	update <tipa/basebin> <path>\tInitiates a jailbreak update either based on a TIPA or based on a basebin.tar file, TIPA installation depends on TrollStore, afterwards it triggers a userspace reboot\n");
}

int main(int argc, char* argv[])
{
	setvbuf(stdout, NULL, _IOLBF, 0);
	if (argc < 2) {
		print_usage();
		return 1;
	}

	jbclient_xpc_init_launchd();

	char *cmd = argv[1];
	if (!strcmp(cmd, "proc_set_debugged")) {
		if (argc != 3) {
			print_usage();
			return 1;
		}
		int pid = atoi(argv[2]);
		int64_t result = jbclient_platform_set_process_debugged(pid);
		if (result == 0) {
			printf("Successfully marked proc of pid %d as debugged\n", pid);
		}
		else {
			printf("Failed to mark proc of pid %d as debugged\n", pid);
		}
	}
	else if (!strcmp(cmd, "rebuild_trustcache")) {
		//jbdRebuildTrustCache();
	} else if (!strcmp(cmd, "reboot_userspace")) {
		return reboot3(RB2_USERREBOOT);
	} else if (!strcmp(cmd, "update")) {
		if (argc < 4) {
			print_usage();
			return 2;
		}
		/*char *updateType = argv[2];
		int64_t result = -1;
		if (!strcmp(updateType, "tipa")) {
			result = jbdUpdateFromTIPA([NSString stringWithUTF8String:argv[3]], false);
		} else if(!strcmp(updateType, "basebin")) {
			result = jbdUpdateFromBasebinTar([NSString stringWithUTF8String:argv[3]], false);
		}
		if (result == 0) {
			printf("Update applied, userspace rebooting to finalize it...\n");
			sleep(2);
			return reboot3(RB2_USERREBOOT);
		}
		else {
			printf("Update failed with error code %lld\n", result);
			return result;
		}*/
	} else if (!strcmp(cmd, "internal")) {
		if (getuid() != 0) return -1;
		if (argc < 3) return -1;

		const char *internalCmd = argv[2];
		return jbctl_handle_internal(internalCmd);
	}

	return 0;
}
