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

#include <libjailbreak/jbclient_mach.h>

// Library validation bypass
// Dyld will call fcntl to attach a code signature to a dylib before mapping it in
// So we hook fcntl to ensure the code signature to be attached is added to trustcache

bool proc_has_bootstrap_port(void)
{
	static bool hasBootstrapPort = false;
	static bool didCheckBootstrapPort = false;

	if (!didCheckBootstrapPort) {
		mach_port_t launchdPort = MACH_PORT_NULL;
		task_get_bootstrap_port(task_self_trap(), &launchdPort);
		if (launchdPort) {
			mach_port_deallocate(task_self_trap(), launchdPort);
		}
		hasBootstrapPort = launchdPort != MACH_PORT_NULL;
		didCheckBootstrapPort = true;
	}

	return hasBootstrapPort;
}

int HOOK(__fcntl)(int fd, int cmd, void *arg1, void *arg2, void *arg3, void *arg4, void *arg5, void *arg6, void *arg7, void *arg8)
{
	// Disable LV bypass if this process does not have a bootstrap port
	// But only if the process is also running in safe mode

	// We do not want to apply the LV bypass if injection into this process is disabled and it doesn't have a bootstrap port
	// This fixes the following things
	// - Driverkit processes crash looping
	//   (They will crash when trying to contact launchdhook over the port obtained from mach_ports_lookup)
	// - The system deadlocking when launching a setuid binary due to the following circular dependency:
	//   setuid process -> launchdhook -> jbctl -> launchdhook
	//   (a jbctl child from launchd is used for the setuid fix)
	// - The system deadlocking during early boot

	if (jbinfo_is_checked_in() || proc_has_bootstrap_port()) {
			switch (cmd) {
			case F_ADDSIGS:
			case F_ADDFILESIGS:
			case F_ADDFILESIGS_RETURN: {
				struct siginfo siginfo;
				siginfo.source = (cmd == F_ADDSIGS) ? SIGNATURE_SOURCE_PROC : SIGNATURE_SOURCE_FILE;
				if (arg1) memcpy(&siginfo.signature, (fsignatures_t *)arg1, sizeof (fsignatures_t));
				jbclient_mach_trust_file(fd, arg1 ? &siginfo : NULL);
				break;
			}
		}
	}

	return (int)msyscall_errno(0x5C, fd, cmd, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8);
}