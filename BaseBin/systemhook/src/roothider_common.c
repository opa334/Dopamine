#include <stdio.h>
#include <unistd.h>
#include <libproc.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <sys/syscall.h>
#include <sys/proc_info.h>
#include <dispatch/dispatch.h>

#include "roothider.h"

pid_t __getppid()
{
	int32_t opt[4] = {
		CTL_KERN,
		KERN_PROC,
		KERN_PROC_PID,
		getpid(),
	};
	struct kinfo_proc info={0};
	size_t len = sizeof(struct kinfo_proc);
	if(sysctl(opt, 4, &info, &len, NULL, 0) == 0) {
		if((info.kp_proc.p_flag & P_TRACED) != 0) {
			return info.kp_proc.p_oppid;
		}
	}

    struct proc_bsdinfo procInfo;
	//some process may be killed by sandbox if call systme getppid() so try this first
	if (proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &procInfo, sizeof(procInfo)) == sizeof(procInfo)) {
		return procInfo.pbi_ppid;
	}

	return getppid();
}

#define APP_PATH_PREFIX "/private/var/containers/Bundle/Application/"
char* getAppUUIDPath(const char* path)
{
    if(!path) return NULL;

    char abspath[PATH_MAX];
    if(!realpath(path, abspath)) return NULL;

    if(strncmp(abspath, APP_PATH_PREFIX, sizeof(APP_PATH_PREFIX)-1) != 0)
        return NULL;

    char* p1 = abspath + sizeof(APP_PATH_PREFIX)-1;
    char* p2 = strchr(p1, '/');
    if(!p2) return NULL;

    //is normal app or jailbroken app/daemon?
    if((p2 - p1) != (sizeof("xxxxxxxx-xxxx-xxxx-yxxx-xxxxxxxxxxxx")-1))
        return NULL;
	
	*p2 = '\0';

	return strdup(abspath);
}

bool isRemovableBundlePath(const char* path)
{
    const char* uuidpath = getAppUUIDPath(path);
	if(!uuidpath) return false;
	free((void*)uuidpath);
	return true;
}

bool hasTrollstoreMarker(const char* path)
{
    char* uuidpath = getAppUUIDPath(path);
	if(!uuidpath) return false;

	char* markerpath=NULL;
	asprintf(&markerpath, "%s/_TrollStore", uuidpath);

	int ret = access(markerpath, F_OK);
    if(ret != 0) {
        free((void*)markerpath); markerpath = NULL;
        asprintf(&markerpath, "%s/_TrollStoreLite", uuidpath);
        ret = access(markerpath, F_OK);
    }

    free((void*)markerpath);
	free((void*)uuidpath);

	return ret==0;
}

/* the only reason this function exists is to allow Choicy
	 to block systemhook injection for both stock daemons and normal apps (but not for their child processes) */
bool allowInjectWithSafeMode(const char* path)
{
	if(getpid() != 1) {
		return true;
	}

	if(isRemovableBundlePath(path))
	{
		if(hasTrollstoreMarker(path)) {
			//always inject into trollstored apps unless we blacklist it in roothide manager
			return true;
		} else {
			return false;
		}
	}

	struct statfs fs = {0};
	if(statfs(path, &fs) == 0) {
		if(strcmp(fs.f_mntonname, "/") == 0) {
			// disallow injecting into system process if Choicy blocked it
			return false;
		}
	}

	return true;
}


int __sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
int syscall__sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen) {
	return syscall(SYS_sysctl, name, namelen, oldp, oldlenp, newp, newlen);
}
int __sysctl_hook(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen)
{
	static int cached_namelen = 0;
	static int cached_name[CTL_MAXNAME+2]={0};

	static int cached_namelen2 = 0;
	static int cached_name2[CTL_MAXNAME+2]={0};

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		int mib[] = {0, 3}; //https://github.com/apple-oss-distributions/Libc/blob/899a3b2d52d95d75e05fb286a5e64975ec3de757/gen/FreeBSD/sysctlbyname.c#L24
		size_t buflen = sizeof(cached_name);
		const char* query = "security.mac.amfi.developer_mode_status";
		if(syscall__sysctl(mib, sizeof(mib)/sizeof(mib[0]), cached_name, &buflen, (void*)query, strlen(query))==0) {
			cached_namelen = buflen / sizeof(cached_name[0]);
		}

		int mib2[] = {0, 3};
		size_t buflen2 = sizeof(cached_name2);
		const char* query2 = "security.mac.amfi.launch_env_logging";
		if(syscall__sysctl(mib2, sizeof(mib2)/sizeof(mib2[0]), cached_name2, &buflen2, (void*)query2, strlen(query2))==0) {
			cached_namelen2 = buflen2 / sizeof(cached_name2[0]);
		}
	});

	if(name && namelen && cached_namelen &&
	 namelen==cached_namelen && memcmp(cached_name, name, namelen*sizeof(name[0]))==0) {
		if(oldp && oldlenp && *oldlenp>=sizeof(int)) {

			if(syscall__sysctl(cached_name2,cached_namelen2,oldp,oldlenp,newp,newlen) == 0) {
				return 0;
			}

			*(int*)oldp = 1;
			*oldlenp = sizeof(int);
			return 0;
		}
	}

	return syscall__sysctl(name,namelen,oldp,oldlenp,newp,newlen);
}

int __sysctlbyname(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
int syscall__sysctlbyname(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen)
{
	return syscall(SYS_sysctlbyname, name, namelen, oldp, oldlenp, newp, newlen);
}
int __sysctlbyname_hook(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen)
{
	const char* target = "security.mac.amfi.developer_mode_status";
	if(name && namelen==strlen(target) && strncmp(name, target, namelen)==0) {

		const char* name2 = "security.mac.amfi.launch_env_logging";
		size_t namelen2 = strlen(name2);

		if(syscall__sysctlbyname(name2,namelen2,oldp,oldlenp,newp,newlen)==0) {
			return 0;
		}

		if(oldp && oldlenp && *oldlenp>=sizeof(int)) {
			*(int*)oldp = 1;
			*oldlenp = sizeof(int);
			return 0;
		}
	}
	return syscall__sysctlbyname(name,namelen,oldp,oldlenp,newp,newlen);
}


#include <libkern/OSCacheControl.h>

extern int roothider_inline_version;

static void inline_memcpy(void *restrict dest, const void *src, size_t len)
{
    const uint8_t* s8 = src;
    volatile uint8_t* d8 = dest;
    while (len--) *d8++ = *s8++;
}

static
__attribute__((noinline, naked))
kern_return_t inline_vm_protect(mach_port_t task, vm_address_t address, vm_size_t size, bool set_maximum, vm_prot_t new_protection)
{
    __asm("mov x16, #0xFFFFFFFFFFFFFFF2");
    __asm("svc 0x80");
    __asm("ret");
}

//Export these for use by other hook frameworks

__attribute__((visibility("default"))) 
kern_return_t substrate_hook_memory(void* target, void* data, size_t size)
{
	if(roothider_inline_version >= 19) {
		return hookd_hook(mach_task_self_, (uint64_t)target, data, size);
	}

    kern_return_t kr = inline_vm_protect(mach_task_self_, (vm_address_t)target, size, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);

    if (kr != KERN_SUCCESS) {
        return kr;
    }

    inline_memcpy(target, data, size);

    // this might fail when developer mode is disabled.
    kr = inline_vm_protect(mach_task_self_, (vm_address_t)target, size, 0, VM_PROT_READ | VM_PROT_EXECUTE);

    if (kr != KERN_SUCCESS) {
		// if it fails here, the process is corrupted because we can't recover the previous executable page.
        __builtin_trap(); 
        return kr;
    }

    sys_icache_invalidate(target, size);
	
    return kr;
}

__attribute__((visibility("default"))) 
kern_return_t substrate_vm_protect(mach_port_t task, vm_address_t address, vm_size_t size, bool set_maximum, vm_prot_t new_protection)
{
	if(roothider_inline_version >= 19) {
		return hookd_vm_protect(task, address, size, set_maximum, new_protection);
	}

	return inline_vm_protect(task, address, size, set_maximum, new_protection);
}
