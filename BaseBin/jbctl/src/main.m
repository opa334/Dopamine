#import <libjailbreak/jailbreakd.h>

int main(int argc, char* argv[])
{
	if (argc < 2) return 1;

	char *cmd = argv[1];
	if (!strcmp(cmd, "proc_set_debugged")) {
		if (argc != 3) return 1;
		int pid = atoi(argv[2]);
		int64_t result = jbdProcSetDebugged(getpid());
		if (result == 0) {
			printf("Successfully marked proc of pid %d as debugged\n", pid);
		}
		else {
			printf("Failed to mark proc of pid %d as debugged\n", pid);
		}
	}
	else if (!strcmp(cmd, "rebuild_trustcache")) {
		jbdRebuildTrustCache();
	} else if (!strcmp(cmd, "init_environment")) {
		jbdInitEnvironment(nil);
	} else if (!strcmp(cmd, "update")) {
		if (argc < 4) return 2;
		char *updateType = argv[2];
		int64_t result = -1;
		if (!strcmp(updateType, "tipa")) {
			result = jbdUpdateFromTIPA([NSString stringWithUTF8String:argv[3]]);
		} else if(!strcmp(updateType, "basebin")) {
			result = jbdUpdateFromBasebinTar([NSString stringWithUTF8String:argv[3]]);
		}
		if (result == 0) {
			printf("Update applied, userspace reboot to finish.");
		}
		else {
			printf("Update failed with error code %lld", result);
			return result;
		}
	}

	return 0;
}