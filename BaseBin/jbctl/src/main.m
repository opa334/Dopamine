#import <libjailbreak/jailbreakd.h>

int main(int argc, char* argv[])
{
	if (argc < 2) return 1;

	char *cmd = argv[1];
	if (!strcmp(cmd, "unrestrict_proc")) {
		if (argc != 3) return 1;
		int pid = atoi(argv[2]);
		int64_t result = jbdProcSetDebugged(getpid());
		if (result == 0) {
			printf("Successfully unrestricted proc of %d\n", pid);
		}
		else {
			printf("Failed to unrestrict proc of %d\n", pid);
		}
	}
	else if (!strcmp(cmd, "rebuild_trustcache")) {
		jbdRebuildTrustCache();
	} else if (!strcmp(cmd, "init_environment")) {
		jbdInitEnvironment(nil);
	}

	return 0;
}