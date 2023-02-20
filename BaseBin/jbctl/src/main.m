#import "libjailbreak.h"

int main(int argc, char* argv[])
{
	if (argc != 3) return 1;

	char *cmd = argv[1];
	if (!strcmp(cmd, "unrestrict-cs")) {
		int pid = atoi(argv[2]);
		jbdUnrestrictCodeSigning(pid);
	}

	return 0;
}