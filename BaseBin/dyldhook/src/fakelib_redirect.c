#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sandbox.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <sys/mman.h>

#include "machomerger_hook.h"
#include "dyld_jbinfo.h"
#include "dyld.h"

// When hiding the jailbreak in Dopamine settings, a lot of processes will crash due to the /usr/lib mount disappearing
// Anything that has libraries inside /usr/lib that are not in the shared cache (e.g. libobjc_trampolines.dylib) mapped in will crash
// We solve this here by redirecting dlopen calls for files in /usr/lib to /var/jb/basebin/.fakelib (if the latter is accessible)
// This way the vnode will not be on /usr/lib mount and the /usr/lib mount therefore can be unmounted without making stuff crash
// There are a few rare edge cases of processes that cannot access /var/jb/basebin/.fakelib for some reason, so we need to make sure those still go over /usr/lib

#if IOS < 18

extern void *ORIG(_ZN5dyld44APIs11dlopen_fromEPKciPv)(uintptr_t self, const char* path, int mode, void* addressInCaller);
void *HOOK(_ZN5dyld44APIs11dlopen_fromEPKciPv)(uintptr_t self, const char* path, int mode, void* addressInCaller)
{
	if (jbinfo_is_checked_in()) {
		if (!access(path, F_OK)) {
			const char *orgPrefix = "/usr/lib/";
    		size_t orgPrefixLen = strlen(orgPrefix);
			if (!strncmp(path, orgPrefix, orgPrefixLen)) {
				char *jbroot = jbinfo_get_jbroot();
				if (jbroot) {
					const char *suffix = &path[orgPrefixLen-1];
					const char *middle = "/basebin/.fakelib";

					size_t redirPathSize = strlen(suffix) + strlen(middle) + strlen(jbroot) + 1;
					char redirPath[redirPathSize];
					strcpy(redirPath, jbroot);
					strcat(redirPath, middle);
					strcat(redirPath, suffix);

					void *handle = ORIG(_ZN5dyld44APIs11dlopen_fromEPKciPv)(self, redirPath, mode, addressInCaller);
					if (handle) return handle;

					// If anything failed, fall through
				}
			}
		}
	}

	return ORIG(_ZN5dyld44APIs11dlopen_fromEPKciPv)(self, path, mode, addressInCaller);
}

#endif