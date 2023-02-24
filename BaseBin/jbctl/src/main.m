#import "libjailbreak.h"

int main(int argc, char* argv[])
{
	if (argc != 3) return 1;

	char *cmd = argv[1];
	if (!strcmp(cmd, "unrestrict-cs")) {
		int pid = atoi(argv[2]);
		jbdUnrestrictCodeSigning(pid);
	}
	else if (!strcmp(cmd, "handoff-ppl")) {
		int pid = atoi(argv[2]);
		uint64_t page = jbdInitPPLRemote(pid);
		if (page) {
			printf("Initialized PPL primitives in pid %d, mapping: 0x%llX\n", pid, page);
		}
		else {
			printf("Failed to initialize PPL primitives in pid %d\n", pid);
		}
	}

	return 0;
}