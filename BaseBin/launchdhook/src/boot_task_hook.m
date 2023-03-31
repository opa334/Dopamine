#import <xpc/xpc.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <unistd.h>
#import "substrate.h"
#import <libjailbreak/patchfind.h>
#import <mach-o/dyld.h>

/*extern xpc_object_t xpc_create_from_plist(const void *buf, size_t len);

void addLaunchDaemon(xpc_object_t xdict, const char *path)
{
	int ldFd = open(path, O_RDONLY);
	if (ldFd >= 0) {
		struct stat s = {};
		if(fstat(ldFd, &s) != 0) {
			close(ldFd);
			return;
		}
		size_t len = s.st_size;
		void *addr = mmap(NULL, len, PROT_READ, MAP_FILE | MAP_PRIVATE, ldFd, 0);
		if (addr) {
			xpc_object_t daemonXdict = xpc_create_from_plist(addr, len);
			if (daemonXdict) {
				xpc_dictionary_set_value(xdict, path, daemonXdict);
			}
		}
		close(ldFd);
	}
}*/

/*xpc_object_t (*xpc_dictionary_get_value_orig)(xpc_object_t xdict, const char *key);
xpc_object_t xpc_dictionary_get_value_hook(xpc_object_t xdict, const char *key)
{
	xpc_object_t orgValue = xpc_dictionary_get_value_orig(xdict, key);
	if (!strcmp(key, "Boot")) {
		xpc_object_t jbinitBootTaskDict = xpc_dictionary_create_empty();
		xpc_object_t jbinitProgramArguments = xpc_array_create_empty();
    	xpc_array_set_string(jbinitProgramArguments, XPC_ARRAY_APPEND, "/var/jb/basebin/jbinit");
    	xpc_array_set_string(jbinitProgramArguments, XPC_ARRAY_APPEND, "reinit");
		xpc_dictionary_set_value(jbinitBootTaskDict, "ProgramArguments", jbinitProgramArguments);
		xpc_dictionary_set_bool(jbinitBootTaskDict, "PerformAfterUserspaceReboot", true);
		//xpc_dictionary_set_bool(jbinitBootTaskDict, "RequireRun", true);
		xpc_dictionary_set_value(orgValue, "jbinit", jbinitBootTaskDict);
	}
	else if (!strcmp(key, "LaunchDaemons")) {
		addLaunchDaemon(orgValue, "/var/jb/basebin/jailbreakd.plist");
	}
	else if (!strcmp(key, "Paths")) {
		xpc_array_set_string(orgValue, XPC_ARRAY_APPEND, "/var/jb/Library/LaunchDaemons");
		xpc_array_set_string(orgValue, XPC_ARRAY_APPEND, "/var/jb/basebin");
	}
	return orgValue;
}*/

/*void *(*performBootTask_orig)(char *, void *, void *);
void *performBootTask_hook(char *key, void *a2, void *a3)
{
	if (key) {
		if (!strcmp(key, "usermanagerd")) {
			// Before usermanagerd boot task executes, perform our own boot task
			performBootTask_orig("jbinit", a2, a3);
		}
	}
	return performBootTask_orig(key, a2, a3);
}*/

/*bool (*stringStartsWith_orig)(char *, char *);
bool stringStartsWith_hook(char *s1, char *s2)
{
	bool starts = stringStartsWith_orig(s1, s2);

	if (s1 && s2)  {
		//FILE *f = fopen("/var/mobile/string_starts.log", "a");
		//fprintf(f, "stringStartsWith(%s, %s) => %d\n", s1, s2, starts);
		//fclose(f);
		if (!strcmp(s1, "/var/jb/basebin/jailbreakd.plist")) {
			return true;
		}
	}

	return starts;
}*/

/*int stringEndsWith(const char* str, const char* suffix) {
    size_t str_len = strlen(str);
    size_t suffix_len = strlen(suffix);

    if (str_len < suffix_len) {
        return 0;
    }

    return strcmp(str + str_len - suffix_len, suffix) == 0;
}*/

extern int stringEndsWith(const char* str, const char* suffix);

void (*sub_100012B44_orig)(uint8_t *);
void sub_100012B44_hook(uint8_t *someStruct)
{
	const char *someString = *(const char**)(someStruct + 0x8);
	if (someString) {
		if (stringEndsWith(someString, "com.apple.UserEventAgent-System.plist")) {
			static dispatch_once_t onceToken;
			dispatch_once (&onceToken, ^{
				*(const char**)(someStruct + 0x8) = strdup("/var/jb/basebin/jailbreakd.plist");
				sub_100012B44_orig(someStruct);
				*(const char**)(someStruct + 0x8) = someString;
			});
		}
	}

	sub_100012B44_orig(someStruct);
}

void initBootTaskHooks(void)
{
	extern int gLaunchdImageIndex;
	/*
	Unique instructions in performBootTask:
	mov x19, x0
	nop
	nop
	*/
	/*unsigned char performBootTaskBytes[] = "\xF3\x03\x00\xAA\x1F\x20\x03\xD5\x1F\x20\x03\xD5";
	unsigned char performBootTaskMask[] = "\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF";

	void *performBootTaskMid = patchfind_find(gLaunchdImageIndex, (unsigned char*)performBootTaskBytes, (unsigned char*)performBootTaskMask, sizeof(performBootTaskBytes));
	void *performBootTaskPtr = patchfind_seek_back(performBootTaskMid, 0xD503237F, 0xFFFFFFFF, 50 * 4);
	MSHookFunction(performBootTaskPtr, (void *)performBootTask_hook, (void **)&performBootTask_orig);*/

	/*void *stringStartsWithPtr = (void *)(_dyld_get_image_vmaddr_slide(gLaunchdImageIndex) + 0x100011A40);
	MSHookFunction(stringStartsWithPtr, (void *)stringStartsWith_hook, (void **)&stringStartsWith_orig);*/
	
	//MSHookFunction(&xpc_dictionary_get_value, (void *)xpc_dictionary_get_value_hook, (void **)&xpc_dictionary_get_value_orig);

	void *sub_100012B44 = (void*)_dyld_get_image_vmaddr_slide(gLaunchdImageIndex) + 0x100012B44;
	MSHookFunction(sub_100012B44, (void *)sub_100012B44_hook, (void **)&sub_100012B44_orig);
}