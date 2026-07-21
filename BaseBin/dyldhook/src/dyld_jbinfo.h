#define DYLD_JBINFO_MAXSIZE 0x4000

#define DYLD_STATE_CHECKED_IN 1

// A struct that allows dyldhook to stash information that systemhook can later access
struct dyld_jbinfo {
	uint64_t state;
	char *jbRootPath;
	char *bootUUID;
	char *sandboxExtensions;
	bool fullyDebugged;

	char data[];
};

extern bool jbinfo_is_checked_in(void);
extern char *jbinfo_get_jbroot(void);