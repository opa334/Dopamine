#import <libjailbreak/jailbreakd.h>

int main(int argc, char* argv[])
{
	if (argc < 2) return 1;

	char *cmd = argv[1];
	if (!strcmp(cmd, "unrestrict_proc")) {
		if (argc != 3) return 1;
		int pid = atoi(argv[2]);
		bool suc = jbdUnrestrictProc(pid);
		if (suc) {
			printf("Successfully unrestricted proc of %d\n", pid);
		}
		else {
			printf("Failed to unrestrict proc of %d\n", pid);
		}
	}
	else if (!strcmp(cmd, "rebuild_trustcache")) {
		jbdRebuildTrustCache();
	}

	return 0;
}