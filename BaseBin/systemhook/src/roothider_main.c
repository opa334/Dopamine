#include <pwd.h>
#include <stdio.h>
#include <dlfcn.h>
#include <unistd.h>
#include <libgen.h>
#include <sys/sysctl.h>
#include <sys/proc_info.h>

#include <litehook.h>

#include "common/common.h"
#include "common/envbuf.h"
#include "sandbox.h"
#include "roothider.h"

const char* HOOK_DYLIB_PATH = NULL;

bool dyld_patch_fallback_enabled = false;

//export for PatchLoader
__attribute__((visibility("default"))) int PLRequiredJIT() {
	return 0;
}

static uid_t _CFGetSVUID(bool *successful) {
    uid_t uid = -1;
    struct kinfo_proc kinfo;
    u_int miblen = 4;
    size_t  len;
    int mib[miblen];
    int ret;
    mib[0] = CTL_KERN;
    mib[1] = KERN_PROC;
    mib[2] = KERN_PROC_PID;
    mib[3] = getpid();
    len = sizeof(struct kinfo_proc);
    ret = sysctl(mib, miblen, &kinfo, &len, NULL, 0);
    if (ret != 0) {
        uid = -1;
        *successful = false;
    } else {
        uid = kinfo.kp_eproc.e_pcred.p_svuid;
        *successful = true;
    }
    return uid;
}

bool _CFCanChangeEUIDs(void) {
    static bool canChangeEUIDs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uid_t euid = geteuid();
        uid_t uid = getuid();
        bool gotSVUID = false;
        uid_t svuid = _CFGetSVUID(&gotSVUID);
        canChangeEUIDs = (uid == 0 || uid != euid || svuid != euid || !gotSVUID);
    });
    return canChangeEUIDs;
}

void loadPathHook()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
		void* roothidehooks = dlopen(JBROOT_PATH("/basebin/roothidehooks.dylib"), RTLD_NOW);
		ASSERT(roothidehooks != NULL);
		void (*pathhook)() = dlsym(roothidehooks, "pathhook");
		ASSERT(pathhook != NULL);
		pathhook();
	});
}

void redirect_env_paths(const char* rootdir)
{
    //for now libSystem should be initlized, container should be set.

    char* homedir = NULL;

/* 
there is a bug in NSHomeDirectory,
if a containerized root process changes its uid/gid, 
NSHomeDirectory may return a home directory that it cannot access. (exclude NSTemporaryDirectory)
We just keep this bug:
*/
    if(!issetugid()) // issetugid() should always be false at this time. (but how about persona-mgmt? idk)
    {
        homedir = getenv("CFFIXED_USER_HOME");
        if(homedir)
        {
#define CONTAINER_PATH_PREFIX   "/private/var/mobile/Containers/Data/" // +/Application,PluginKitPlugin,InternalDaemon
            if(strncmp(homedir, CONTAINER_PATH_PREFIX, sizeof(CONTAINER_PATH_PREFIX)-1) == 0)
            {
                return; //containerized
            }
            else
            {
                homedir = NULL; //from parent, drop it
            }
        }
    }

    if(!homedir) {
        struct passwd* pwd = getpwuid(geteuid());
        if(pwd && pwd->pw_dir) {
            homedir = pwd->pw_dir;
        }
    }

    // if(!homedir) {
    //     //CFCopyHomeDirectoryURL does, but not for NSHomeDirectory
    //     homedir = getenv("HOME");
    // }

    if(!homedir) {
        homedir = "/var/empty";
    }

	if(homedir[0] == '/') {
		char newhome[PATH_MAX*2]={0};
		strlcpy(newhome, rootdir, sizeof(newhome));
		strlcat(newhome, homedir, sizeof(newhome));
		setenv("CFFIXED_USER_HOME", newhome, 1);
	}
}

void redirect_paths(const char* rootdir)
{
    do {
        
        char executablePath[PATH_MAX]={0};
        uint32_t bufsize=sizeof(executablePath);
        if(_NSGetExecutablePath(executablePath, &bufsize) != 0)
            break;
        
        char realexepath[PATH_MAX]={0};
        if(!realpath(executablePath, realexepath))
            break;
            
        char realjbroot[PATH_MAX+1]={0};
        if(!realpath(rootdir, realjbroot))
            break;
        
        if(realjbroot[0] && realjbroot[strlen(realjbroot)-1] != '/')
            strlcat(realjbroot, "/", sizeof(realjbroot));
        
        if(strncmp(realexepath, realjbroot, strlen(realjbroot)) != 0)
            break;

        //for jailbroken binaries
        redirect_env_paths(rootdir);
		
		if(_CFCanChangeEUIDs()) {
			loadPathHook();
		}
    
        pid_t ppid = __getppid();
        ASSERT(ppid > 0);
        if(ppid != 1)
            break;
        
        char pwd[PATH_MAX];
        if(getcwd(pwd, sizeof(pwd)) == NULL)
            break;
        if(strcmp(pwd, "/") != 0)
            break;
    
        ASSERT(chdir(rootdir)==0);
        
    } while(0);
}


kSpawnConfig spawn_config_for_executable(const char* path, char *const argv[restrict]);
void string_enumerate_components(const char *string, const char *separator, void (^enumBlock)(const char *pathString, bool *stop));

void trust_insert_libraries(char** envc)
{
	const char* DYLD_INSERT_LIBRARIES = envbuf_getenv(envc, "DYLD_INSERT_LIBRARIES");
	if(!DYLD_INSERT_LIBRARIES) return;

	string_enumerate_components(DYLD_INSERT_LIBRARIES, ":", ^(const char *path, bool *stop) {
		if (strcmp(path, HOOK_DYLIB_PATH) != 0) {
			jbclient_trust_library_recurse(path, NULL);
		}
	});
}

int __no_need_to_trust_now__(const char* path)
{
	return 0;
}

#define NBINPREFS       4
#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
int posix_spawnattr_getprocesstype_np(const posix_spawnattr_t * __restrict, int * __restrict) __API_AVAILABLE(macos(10.8), ios(6.0));

int roothide_systemhook___posix_spawn_prehook(pid_t *restrict pidp, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict], void *orig, int (*trust_binary)(const char *path), int (*set_process_debugged)(uint64_t pid, bool fullyDebugged), double jetsamMultiplier)
{
	if(!path) { //Don't crash here due to bad posix_spawn call
		return __posix_spawn_orig(pidp, path, desc, argv, envp);
	}

	if(!desc || !desc->attrp) {
		posix_spawnattr_t attr=NULL;
		posix_spawnattr_init(&attr);
		int ret = posix_spawn(pidp, path, (desc && desc->file_actions) ? &desc->file_actions : NULL, &attr, argv, envp);
		posix_spawnattr_destroy(&attr);
		return ret;
	}

	if(!jbclient_dyld_patch_enabled())
	{
		trust_binary = __no_need_to_trust_now__;
	}

	return posix_spawn_hook_shared(pidp, path, desc, argv, envp, orig, trust_binary, set_process_debugged, jetsamMultiplier);
}

int roothide_systemhook___posix_spawn_posthook(pid_t *restrict pidp, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict])
{
	posix_spawnattr_t attrp = &desc->attrp;

	kSpawnConfig spawnConfig = 0;
	if(!jbclient_dyld_patch_enabled())
	{
		spawnConfig = spawn_config_for_executable(path, argv);

		if (spawnConfig & kSpawnConfigTrust) {
			size_t outCount = 0;
			bool preferredArchsSet = false;
			cpu_type_t preferredTypes[NBINPREFS] = {0};
			cpu_subtype_t preferredSubtypes[NBINPREFS] = {0};
			if (posix_spawnattr_getarchpref_np(attrp, 4, preferredTypes, preferredSubtypes, &outCount) == 0) {
				for (size_t i = 0; i < outCount; i++) {
					if (preferredTypes[i] != 0 || preferredSubtypes[i] != UINT32_MAX) {
						preferredArchsSet = true;
						break;
					}
				}
			}

			xpc_object_t preferredArchsArray = NULL;
			if (preferredArchsSet) {
				preferredArchsArray = xpc_array_create_empty();
				for (size_t i = 0; i < outCount; i++) {
					xpc_object_t curArch = xpc_dictionary_create_empty();
					xpc_dictionary_set_uint64(curArch, "type", preferredTypes[i]);
					xpc_dictionary_set_uint64(curArch, "subtype", preferredSubtypes[i]);
					xpc_array_set_value(preferredArchsArray, XPC_ARRAY_APPEND, curArch);
					xpc_release(curArch);
				}
			}

			// Upload binary to trustcache if needed
			jbclient_trust_executable_recurse(path, preferredArchsArray);

			if (preferredArchsArray) {
				xpc_release(preferredArchsArray);
			}
		}
	}

	short flags = 0;
	posix_spawnattr_getflags(attrp, &flags);

	int proctype = 0;
	posix_spawnattr_getprocesstype_np(attrp, &proctype);

	bool should_suspend = (proctype != POSIX_SPAWN_PROC_TYPE_DRIVER);
	bool should_resume = should_suspend && (flags & POSIX_SPAWN_START_SUSPENDED)==0;
	bool patch_exec = should_suspend && (flags & POSIX_SPAWN_SETEXEC) != 0;

	if (should_suspend) {
		posix_spawnattr_setflags(attrp, flags | POSIX_SPAWN_START_SUSPENDED);
	}

	if (patch_exec) {
		if (jbdSpawnExecStart(path, should_resume) != 0) { // jdb fault?
			//restore flags
			posix_spawnattr_setflags(attrp, flags);
			return 201;
		}
	}

	// on some devices dyldhook may fail due to vm_protect(VM_PROT_READ|VM_PROT_WRITE), 2, (os/kern) protection failure in dsc::__DATA_CONST:__const, 
	// so we need to disable dyld-in-cache here. (or we can use VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY)
	char **envc = envbuf_mutcopy((const char **)envp);
	if(envbuf_getenv(envc, "DYLD_INSERT_LIBRARIES")) {
		envbuf_setenv(&envc, "DYLD_IN_CACHE", "0");
	}

	if(!jbclient_dyld_patch_enabled())
	{
		if (spawnConfig & kSpawnConfigTrust) {
			trust_insert_libraries(envc);
		}
	}

	int pid = 0;
	int ret = __posix_spawn_orig(&pid, path, desc, argv, envc);
	if (pidp) *pidp = pid;

	envbuf_free(envc);

	// maybe caller will use it again? restore flags
	posix_spawnattr_setflags(attrp, flags);

	if (patch_exec) { //exec failed?
		jbdSpawnExecCancel(path);
	} else if (ret == 0 && pid > 0) {
		if (should_suspend) {
			if(jbdSpawnPatchChild(pid, should_resume) != 0) { // jdb fault? kill
				//just kill it instead of letting it hang forever, and the requester decides what to do later
				kill(pid, SIGQUIT); //core dump
				kill(pid, SIGKILL);
				return 202;
			}
		}
	}

	return ret;
}

int roothide_systemhook___execve_prehook(const char *path, char *const argv[], char *const envp[], void *orig, int (*trust_binary)(const char *path))
{
	//try POSIX_SPAWN_SETEXEC first
	posix_spawnattr_t attr = NULL;
	posix_spawnattr_init(&attr);
	posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC);
	int ret = posix_spawn(NULL, path, NULL, &attr, argv, envp);
	posix_spawnattr_destroy(&attr);

	//posix_spawn with POSIX_SPAWN_SETEXEC failed
	assert(ret != 0);

	/* some processes are only allowed to call execve but not posix_spawn,
	 e.g: "configd" on ios15, we need to trace it so that we can patch the subprocess before it runs. */
	if(ret==EPERM && access(path, X_OK)==0 && sandbox_check(getpid(), "process-fork", SANDBOX_CHECK_NO_REPORT, NULL) == 0)
	{
		trust_binary = __no_need_to_trust_now__;
		return execve_hook_shared(path, argv, envp, orig, trust_binary);
	}

	// posix_spawn will return errno and restore errno if it fails
	// so we need to set errno by ourself
	errno = ret; 
	return -1;
}

int roothide_systemhook___execve_posthook(const char *path, char *const argv[], char *const envp[])
{
	/* the posix_spawn call above should already trust the executable
	(also its libraries) and the inserted libraries, so we can skip them below */

	bool traced = false;

	if(jbdExecTraceStart(path, &traced) != 0) { // jdb fault?
		errno = 203;
		return -1;
	}

	//wait for SIGSTOP
	while(!traced) usleep(10*1000);

	char **envc = envbuf_mutcopy((const char **)envp);
	if(envbuf_getenv(envc, "DYLD_INSERT_LIBRARIES")) {
		envbuf_setenv(&envc, "DYLD_IN_CACHE", "0");
	}
	
	int ret = __execve_orig(path, argv, envc);
	int olderr = errno;
	
	envbuf_free(envc);

	// exec* should never return if successful

	bool detached = false;

	if(jbdExecTraceCancel(path, &detached) != 0) {
		//broken process
		exit(99);
	}

	//wait for detach
	while(!detached) usleep(10*1000);

	errno = olderr;
	return ret;
}

void* (*dyld_dlopen_orig)(void *dyld, const char* path, int mode);
void* dyld_dlopen_hook(void *dyld, const char* path, int mode)
{
	if (path && !(mode & RTLD_NOLOAD)) {
		jbclient_trust_library_recurse(path, __builtin_return_address(0));
	}
    __attribute__((musttail)) return dyld_dlopen_orig(dyld, path, mode);
}

void* (*dyld_dlopen_from_orig)(void *dyld, const char* path, int mode, void* addressInCaller);
void* dyld_dlopen_from_hook(void *dyld, const char* path, int mode, void* addressInCaller)
{
	if (path && !(mode & RTLD_NOLOAD)) {
		jbclient_trust_library_recurse(path, addressInCaller);
	}
	__attribute__((musttail)) return dyld_dlopen_from_orig(dyld, path, mode, addressInCaller);
}

void* (*dyld_dlopen_audited_orig)(void *dyld, const char* path, int mode);
void* dyld_dlopen_audited_hook(void *dyld, const char* path, int mode)
{
	if (path && !(mode & RTLD_NOLOAD)) {
		jbclient_trust_library_recurse(path, __builtin_return_address(0));
	}
	__attribute__((musttail)) return dyld_dlopen_audited_orig(dyld, path, mode);
}

bool (*dyld_dlopen_preflight_orig)(void *dyld, const char *path);
bool dyld_dlopen_preflight_hook(void *dyld, const char* path)
{
	if (path) {
		jbclient_trust_library_recurse(path, __builtin_return_address(0));
	}
	__attribute__((musttail)) return dyld_dlopen_preflight_orig(dyld, path);
}

int hook_dyld_routine(void **dyld, int idx, void *hook, void **orig, uint16_t pacSalt)
{
	if (!dyld) return -1;

	uint64_t dyldPacDiversifier = ((uint64_t)dyld & ~(0xFFFFull << 48)) | (0x63FAull << 48);
	void **dyldFuncPtrs = ptrauth_auth_data(*dyld, ptrauth_key_process_independent_data, dyldPacDiversifier);
	if (!dyldFuncPtrs) return -1;

	if (vm_protect(mach_task_self_, (mach_vm_address_t)&dyldFuncPtrs[idx], sizeof(void *), false, VM_PROT_READ | VM_PROT_WRITE) == 0) {
		uint64_t location = (uint64_t)&dyldFuncPtrs[idx];
		uint64_t pacDiversifier = (location & ~(0xFFFFull << 48)) | ((uint64_t)pacSalt << 48);

		*orig = ptrauth_auth_and_resign(dyldFuncPtrs[idx], ptrauth_key_process_independent_code, pacDiversifier, ptrauth_key_function_pointer, 0);
		dyldFuncPtrs[idx] = ptrauth_auth_and_resign(hook, ptrauth_key_function_pointer, 0, ptrauth_key_process_independent_code, pacDiversifier);
		vm_protect(mach_task_self_, (mach_vm_address_t)&dyldFuncPtrs[idx], sizeof(void *), false, VM_PROT_READ);
		return 0;
	}

	return -1;
}

void init_dyldhooks()
{
	// Apply dyld hooks
	void ***gDyldPtr = litehook_find_dsc_symbol("/usr/lib/system/libdyld.dylib", "__ZN5dyld45gDyldE");
	if (gDyldPtr) {
		hook_dyld_routine(*gDyldPtr, 14, (void *)&dyld_dlopen_hook, (void **)&dyld_dlopen_orig, 0xBF31);
		hook_dyld_routine(*gDyldPtr, 18, (void *)&dyld_dlopen_preflight_hook, (void **)&dyld_dlopen_preflight_orig, 0xB1B6);
		hook_dyld_routine(*gDyldPtr, 97, (void *)&dyld_dlopen_from_hook, (void **)&dyld_dlopen_from_orig, 0xD48C);
		hook_dyld_routine(*gDyldPtr, 98, (void *)&dyld_dlopen_audited_hook, (void **)&dyld_dlopen_audited_orig, 0xD2A5);
	}
}

extern struct mach_header __dso_handle;
extern const char* dyld_image_path_containing_address(const void* addr);

extern int parse_dyldhook_jbinfo(char **jbRootPathOut, char **bootUUIDOut, char **sandboxExtensionsOut, bool *fullyDebuggedOut);

void roothide_init()
{
	if(getenv("DYLD_INSERT_LIBRARIES")) {
		const char* DYLD_IN_CACHE = getenv("DYLD_IN_CACHE");
		if(DYLD_IN_CACHE && strcmp(DYLD_IN_CACHE, "0") == 0) {
			unsetenv("DYLD_IN_CACHE");
		}
	}

	HOOK_DYLIB_PATH = strdup(dyld_image_path_containing_address(&__dso_handle));

	if(parse_dyldhook_jbinfo(NULL, NULL, NULL, NULL) != 0)
	{
		dyld_patch_fallback_enabled = true;
	}
}

void roothide_init_with_checkin(const char* rootdir)
{
	if(dyld_patch_fallback_enabled)
	{
		init_dyldhooks();
	}

	redirect_paths(rootdir);

	dlopen(JBROOT_PATH("/usr/lib/roothideinit.dylib"), RTLD_NOW);
}

void roothide_init_with_executable(const char* executable)
{
	if (__builtin_available(iOS 16.0, *))
	{
		if(!isRemovableBundlePath(executable)) {
			litehook_hook_function(__sysctl, __sysctl_hook);
			litehook_hook_function(__sysctlbyname, __sysctlbyname_hook);
		}
	}

#ifndef __arm64e__
	if(strcmp(executable, "/System/Library/Frameworks/LocalAuthentication.framework/Support/coreauthd")==0
	|| strcmp(executable, "/System/Library/Frameworks/CryptoTokenKit.framework/ctkd")==0
	|| strcmp(executable, "/usr/libexec/securityd")==0
	|| strcmp(executable, "/usr/libexec/keybagd")==0) {
		if(jbclient_palehide_present())
		{
			void* roothidehooks = dlopen(JBROOT_PATH("/basebin/roothidehooks.dylib"), RTLD_NOW);
			ASSERT(roothidehooks != NULL);
			void (*palera1n)() = dlsym(roothidehooks, "palera1n");
			palera1n();
		}
	}
#endif

	if(string_has_suffix(executable, "/Dopamine.app/Dopamine")) {
		loadPathHook(); //requre jit
	}

	dlopen(JBROOT_PATH("/usr/lib/roothidepatch.dylib"), RTLD_NOW); //require jit
}

