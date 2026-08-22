#import <Foundation/Foundation.h>

#include <spawn.h>
#include <substrate.h>
#include <sys/sysctl.h>

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/roothider.h>

#include "../systemhook/src/common/common.h"
#include "../systemhook/src/common/envbuf.h"

const char* HOOK_DYLIB_PATH = NULL;

#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
extern int posix_spawnattr_getprocesstype_np(const posix_spawnattr_t *__restrict, int *__restrict) __API_AVAILABLE(macos(10.8), ios(6.0));
extern int posix_spawnattr_setexceptionports_np(posix_spawnattr_t *__restrict, exception_mask_t, mach_port_t, exception_behavior_t, thread_state_flavor_t) __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

//from launchdhook/spawn_hook.c
extern int systemwide_trust_file_by_path(const char *path);
extern int platform_set_process_debugged(uint64_t pid, bool fullyDebugged);
extern int __posix_spawn_hook(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict]);
extern int __posix_spawn_orig_wrapper(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict]);

//from systemhook/roothide_common.c
int __sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
int __sysctl_hook(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
int __sysctlbyname(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
int __sysctlbyname_hook(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

/*
int (*sysctlbyname_orig)(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
int sysctlbyname_hook(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen)
{
	if (strcmp(name, "vm.shared_region_pivot") == 0) {
		return 0;
	}
	return sysctlbyname_orig(name, oldp, oldlenp, newp, newlen);
}
*/

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
int (*orig_bind)(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int new_bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen)
{
    if (addr->sa_family == AF_INET && addrlen >= sizeof(struct sockaddr_in)) {
        struct sockaddr_in addr_in = *(struct sockaddr_in*)addr;
        in_port_t port = ntohs(addr_in.sin_port);
        if (port == 0) {
			int ret = -1;
			for(port=IPPORT_HIFIRSTAUTO; port<=IPPORT_HILASTAUTO; port++)
			{
				addr_in.sin_port = htons(port);
				ret = orig_bind(sockfd, (struct sockaddr*)&addr_in, addrlen);
				if(ret==0 || errno!=EADDRINUSE) {
					break;
				}
			}
			return ret;
        }
    } else if (addr->sa_family == AF_INET6 && addrlen >= sizeof(struct sockaddr_in6)) {
        struct sockaddr_in6 addr_in6 = *(struct sockaddr_in6*)addr;
        in_port_t port = ntohs(addr_in6.sin6_port);
        if (port == 0) {
			int ret = -1;
			for(port=IPPORT_HIFIRSTAUTO; port<=IPPORT_HILASTAUTO; port++)
			{
				addr_in6.sin6_port = htons(port);
				ret = orig_bind(sockfd, (struct sockaddr*)&addr_in6, addrlen);
				if(ret==0 || errno!=EADDRINUSE) {
					break;
				}
			}
			return ret;
        }
    }
    return orig_bind(sockfd, addr, addrlen);
}

extern xpc_object_t (*orig_xpc_dictionary_create_reply)(xpc_object_t original);
extern xpc_object_t new_xpc_dictionary_create_reply(xpc_object_t original);
extern int (*orig_xpc_pipe_routine_reply)(xpc_object_t reply);
extern int new_xpc_pipe_routine_reply(xpc_object_t reply);

void roothide_launchd_preinit()
{
	JBLogDebug("roothide_launchd_preinit");

#ifdef ENABLE_LOGS
	enableJBDLog(JBLogDebugFunction, JBLogErrorFunction);
#endif

	exec_set_patch(false);
}

void roothide_launchd_postinit(bool firstLoad)
{
	JBLogDebug("roothide_launchd_postinit: firstLoad=%d", firstLoad);

	launchdhookFirstLoad = firstLoad;

	exec_set_patch(true);

	if(firstLoad)
	{
		HOOK_DYLIB_PATH = "";
		
		if (__builtin_available(iOS 16.0, *))
		{
			hideDeveloperMode();
		}
		
#ifdef __arm64e__
		if (!__builtin_available(iOS 16.0, *))
		{
			if(roothide_config_set_spinlock_fix(dyld_patch_enabled()) != 0) {
				launchd_panic("roothide_config_set_spinlock_fix failed");
				return;
			}
		}
#endif
	}
	else
	{		
		NSString* systemhookFilePath = [NSString stringWithFormat:@"%@/systemhook-%016llX.dylib", JBROOT_PATH(@"/basebin"), jbinfo(jbrand)];

		if([NSFileManager.defaultManager fileExistsAtPath:JBROOT_PATH(@"/basebin/systemhook.dylib")])
		{
			[NSFileManager.defaultManager removeItemAtPath:systemhookFilePath error:nil];
			assert([NSFileManager.defaultManager moveItemAtPath:JBROOT_PATH(@"/basebin/systemhook.dylib") toPath:systemhookFilePath error:nil]);
		}
		
		assert(unsandbox("/usr/lib", systemhookFilePath.fileSystemRepresentation) == 0);

		//new "real path"
		asprintf(&HOOK_DYLIB_PATH, "/usr/lib/systemhook-%016llX.dylib", jbinfo(jbrand));
	}

	if (__builtin_available(iOS 16.0, *))
	{
		void* __sysctl_orig = NULL;
		void* __sysctlbyname_orig = NULL;
		MSHookFunction(&__sysctl, (void *) __sysctl_hook, &__sysctl_orig);
		MSHookFunction(&__sysctlbyname, (void *) __sysctlbyname_hook, &__sysctlbyname_orig);
		MSHookFunction(&bind, (void*)new_bind, &orig_bind); //fix network issues on iOS16+
	}
#ifdef __arm64e__
	else 
	{
		// iOS15 arm64e only
		// MSHookFunction(sysctlbyname, (void *)sysctlbyname_hook, (void **)&sysctlbyname_orig);
	}
#endif

	if(!firstLoad)
	{
		int ret = ensure_dyld_trustcache(JBROOT_PATH("/basebin/.fakelib/dyld"));
		if (ret != 0) {
			launchd_panic("ensure dyld trustcache failed: %d", ret);
			return;
		}
	}

	loadAppStoredIdentifiers();

	MSHookFunction(&xpc_dictionary_create_reply, (void*)new_xpc_dictionary_create_reply, &orig_xpc_dictionary_create_reply);
	MSHookFunction(&xpc_pipe_routine_reply, (void*)new_xpc_pipe_routine_reply, &orig_xpc_pipe_routine_reply);

	// load jailbreakd after applying hooks
	assert(initJailbreakd(firstLoad) == 0);
}

#include <dlfcn.h>
#include <IOKit/IOKitLib.h>
void fix__iosConnect()
{
    MSImageRef IOSurfaceImage = MSGetImageByName("/System/Library/Frameworks/IOSurface.framework/IOSurface");
    JBLogDebug("IOSurfaceImage=%p\n", IOSurfaceImage);
    assert(IOSurfaceImage != NULL);

    io_service_t* __iosService = MSFindSymbol(IOSurfaceImage, "__iosService");
    io_connect_t* __iosConnect = MSFindSymbol(IOSurfaceImage, "__iosConnect");
    assert(__iosService != NULL && __iosConnect != NULL);

    JBLogDebug("__iosService=%p __iosConnect=%p\n", __iosService, __iosConnect);
    JBLogDebug("*__iosService=%d *__iosConnect=%d\n", *__iosService, *__iosConnect);

    kern_return_t (*IOServiceClose)(io_connect_t connect);
    kern_return_t (*IOServiceOpen)(io_service_t service, task_port_t owningTask, uint32_t type, io_connect_t* connect);

    *(void **)&IOServiceOpen = dlsym(RTLD_DEFAULT, "IOServiceOpen");
    *(void **)&IOServiceClose = dlsym(RTLD_DEFAULT, "IOServiceClose");
    assert(IOServiceOpen != NULL && IOServiceClose != NULL);
    
    io_connect_t old__iosConnect = *__iosConnect;

    if(old__iosConnect) {

        assert(*__iosService != 0);

        kern_return_t kr = IOServiceOpen(*__iosService, mach_task_self(), 0, __iosConnect);
        JBLogDebug("IOServiceOpen kr=%x, new iosConnect=%d\n", kr, *__iosConnect);
        assert(kr == KERN_SUCCESS);

        kr = IOServiceClose(old__iosConnect);
        assert(kr == KERN_SUCCESS);
    }
}

int roothide_trust_executable_recurse(const char *executablePath, const char *processWorkingDir, xpc_object_t preferredArchsArray);
int roothide_launchd_trust_executable(const char* path)
{
	return dyld_patch_enabled() ? systemwide_trust_file_by_path(path) : roothide_trust_executable_recurse(path, "/", NULL);
}

int roothide_launchd___posix_spawn_posthook(pid_t *restrict pidp, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict])
{
	//spawn_prehook ensure this is always available
	posix_spawnattr_t attrp = &desc->attrp;

	short flags = 0;
	posix_spawnattr_getflags(attrp, &flags);

	int proctype = 0;
	posix_spawnattr_getprocesstype_np(attrp, &proctype);

	bool should_suspend = (proctype != POSIX_SPAWN_PROC_TYPE_DRIVER);
	bool should_resume = should_suspend && (flags & POSIX_SPAWN_START_SUSPENDED)==0;

	if (should_suspend) {
		posix_spawnattr_setflags(attrp, flags | POSIX_SPAWN_START_SUSPENDED);
	}

	// on some devices dyldhook may fail due to vm_protect(VM_PROT_READ|VM_PROT_WRITE), 2, (os/kern) protection failure in dsc::__DATA_CONST:__const, 
	// so we need to disable dyld-in-cache here. (or we can use VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY)
	char **envc = envbuf_mutcopy((const char **)envp);
	if(envbuf_getenv(envc, "DYLD_INSERT_LIBRARIES")) {
		envbuf_setenv(&envc, "DYLD_IN_CACHE", "0");
	}

#ifdef __arm64e__
	if (!__builtin_available(iOS 16.0, *))
	{
		if(!dyld_patch_enabled() && process_force_dyld_patch(path, argv)) {
			envbuf_setenv(&envc, "SPINLOCK_FIX_DISABLED", "1");
		}
	}
#endif

	int pid = 0;
	int ret = __posix_spawn_orig_wrapper(&pid, path, desc, argv, envc);
	if(pidp) *pidp = pid;

	envbuf_free(envc);
	
	posix_spawnattr_setflags(attrp, flags); // maybe caller will use it again?

	if (ret == 0 && pid > 0) {
		if(should_suspend) {
			if(jbdSpawnPatchChild(pid, should_resume) != 0) {
				JBLogError("Failed to patch spawned process (%d) %s", pid, path);
				//just kill it instead of letting it hang forever so that launchd can respawn it later
				kill(pid, SIGQUIT); //core dump
				kill(pid, SIGKILL);
				ret = 202;
			}
		}
	} else {
		JBLogError("spawn failed: %d %s, pid=%d", ret, strerror(ret), pid);
	}

	return ret;
}

int roothide_launchd___posix_spawn__spinlock_fix_only(pid_t *restrict pidp, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict])
{
	//spawn_prehook ensure this is always available
	posix_spawnattr_t attrp = &desc->attrp;

	short flags = 0;
	posix_spawnattr_getflags(attrp, &flags);

	bool should_resume = (flags & POSIX_SPAWN_START_SUSPENDED)==0;

	posix_spawnattr_setflags(attrp, flags | POSIX_SPAWN_START_SUSPENDED);

	int pid = 0;
	int ret = __posix_spawn_orig_wrapper(&pid, path, desc, argv, envp);
	if(pidp) *pidp = pid;
	
	posix_spawnattr_setflags(attrp, flags); // maybe caller will use it again?

	if (ret == 0 && pid > 0) {
		if(jbdSpinlockFixOnly(pid, should_resume)  != 0) {
			JBLogError("Failed to patch(spinlock fix) spawned process (%d) %s", pid, path);
			//just kill it instead of letting it hang forever so that launchd can respawn it later
			kill(pid, SIGQUIT); //core dump
			kill(pid, SIGKILL);
			ret = 202;
		}
	} else {
		JBLogError("spawn failed: %d %s, pid=%d", ret, strerror(ret), pid);
	}

	return ret;
}

int roothide_launchd___posix_spawn_prehook(pid_t *restrict pidp, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict])
{
	if(!desc || !desc->attrp) {
		posix_spawnattr_t attr=NULL;
		posix_spawnattr_init(&attr);
		int ret = posix_spawn(pidp, path, (desc && desc->file_actions) ? &desc->file_actions : NULL, &attr, argv, envp);
		posix_spawnattr_destroy(&attr);
		return ret;
	}
	posix_spawnattr_t attrp = &desc->attrp;

	if(!path) {
		return __posix_spawn_hook(pidp, path, desc, argv, envp);
	}

	if(isRemovableBundlePath(path)) {
		static dispatch_once_t onceToken = {0};
		dispatch_once(&onceToken, ^{
			fix__iosConnect();
		});
	}

	if(strcmp(path, "/sbin/launchd") == 0) {
		short flags = 0;
		posix_spawnattr_getflags(attrp, &flags);
		posix_spawnattr_setflags(attrp, flags | POSIX_SPAWN_START_SUSPENDED);
		return __posix_spawn_hook(pidp, path, desc, argv, envp);
	}

	if(path && string_has_suffix(path, "/Dopamine.app/Dopamine"))
	{
		/* if the jailbreak activation is interrupted for some reason, 
			we prevent the app from relaunching to prevent the system from being in an unknown state */
		if(launchdhookFirstLoad) {
#ifdef ENABLE_LOGS
			launchd_panic("reboot device due to jailbreak failure!");
#endif
			return EPERM;
		}

		char roothidefile[PATH_MAX];
		snprintf(roothidefile, sizeof(roothidefile), "%s.roothide", path);
		if(access(roothidefile, F_OK) != 0) {
			return EPERM;
		}
	}
	
	if(string_has_suffix(path, "/basebin/jailbreakd")) {
		return __posix_spawn_orig_wrapper(pidp, path, desc, argv, envp);
	}


	// mitigate spinlock panic for ios15(A12+) devices

	bool iOS15Arm64e = false;
	bool choicyBlocked = false;
#ifdef __arm64e__
	if (!__builtin_available(iOS 16.0, *))
	{
		iOS15Arm64e = true;
		if(envbuf_getenv(envp, "_SafeMode") || envbuf_getenv(envp, "_MSSafeMode")) {
			if(path && isRemovableBundlePath(path) && !hasTrollstoreMarker(path)) {
				choicyBlocked = true;
			}
		}
	}
#endif

	bool roothideBlacklisted = isBlacklistedPath(path);
	if (choicyBlocked || roothideBlacklisted)
	{
		int ret;

		JBLogDebug("blacklisted app %s", path);

		if(dyld_patch_enabled() && iOS15Arm64e && roothideBlacklisted && (strstr(path, "/PlugIns/") || strstr(path, "/Extensions/") || strstr(path, ".appex/"))) {
			JBLogDebug("prevent blacklisted app's extension from running: ", path);
			ret = EPERM;
		}
		else if(dyld_patch_enabled() && iOS15Arm64e && roothideBlacklisted && (envbuf_getenv(envp, "ActivePrewarm") || envbuf_getenv(envp, "DYLD_USE_CLOSURES"))) {
			JBLogDebug("prevent blacklisted app from prewarming: ", path);
			ret = EPERM;
		}
		else
		{
			char **envc = envbuf_mutcopy((const char **)envp);

			//choicy may set these 
			envbuf_unsetenv(&envc, "_SafeMode");
			envbuf_unsetenv(&envc, "_MSSafeMode");
	
			/* According to xnu, the new thread in new process will not run in userland until after copyout pid
			https://github.com/apple-oss-distributions/xnu/blob/8d741a5de7ff4191bf97d57b9f54c2f6d4a15585/bsd/kern/kern_exec.c#L4321
			https://github.com/apple-oss-distributions/xnu/blob/8d741a5de7ff4191bf97d57b9f54c2f6d4a15585/bsd/kern/kern_exec.c#L4882
			https://github.com/apple-oss-distributions/xnu/blob/8d741a5de7ff4191bf97d57b9f54c2f6d4a15585/bsd/kern/kern_exec.c#L4933
			*/
	
			/* and posix_spawn->kernel->amfid->launchd may cause xpc dead loop so we can't use lock-spawn-unlock here */
	
			volatile pid_t* blacklistedPidp = allocBlacklistProcessId();
	
			if(roothideBlacklisted || !dyld_patch_enabled() || !iOS15Arm64e) {
				ret = __posix_spawn_orig_wrapper(blacklistedPidp, path, desc, argv, envc);
			} else {
				ret = roothide_launchd___posix_spawn__spinlock_fix_only(blacklistedPidp, path, desc, argv, envc);
			}
	
			pid_t pid = *blacklistedPidp;
			if(pidp) *pidp = *blacklistedPidp;

			commitBlacklistProcessId(blacklistedPidp); // will release blacklistedPidp
			blacklistedPidp = NULL;

			envbuf_free(envc);
				
			if(ret==0 && pid>0) {
				short flags = 0;
				posix_spawnattr_getflags(attrp, &flags);
				if((flags & POSIX_SPAWN_START_SUSPENDED) != 0) {
					platform_set_process_debugged(pid, false);
				}
			}
		}
	
		return ret;
	}

	if(launchdhookFirstLoad) 
	{
		//we should not enable system-wide injection until the jailbreak is finalized (userspace reboot).
		return __posix_spawn_orig_wrapper(pidp, path, desc, argv, envp);
	}
	
	return __posix_spawn_hook(pidp, path, desc, argv, envp);
}

