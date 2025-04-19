#include "jbserver_global.h"
#include "jbsettings.h"
#include <libjailbreak/info.h>
#include <sandbox.h>
#include <libproc.h>
#include <sys/proc_info.h>

#include <libjailbreak/signatures.h>
#include <libjailbreak/trustcache.h>
#include <libjailbreak/kernel.h>
#include <libjailbreak/util.h>
#include <libjailbreak/primitives.h>
#include <libjailbreak/codesign.h>

bool gSystemwideDomainEnabled = true;
void systemwide_domain_set_enabled(bool enabled)
{
	gSystemwideDomainEnabled = enabled;
}

extern bool string_has_prefix(const char *str, const char* prefix);
extern bool string_has_suffix(const char* str, const char* suffix);

char *combine_strings(char separator, char **components, int count)
{
	if (count <= 0) return NULL;

	bool isFirst = true;

	size_t outLength = 1;
	for (int i = 0; i < count; i++) {
		if (components[i]) {
			outLength += !isFirst + strlen(components[i]);
			if (isFirst) isFirst = false;
		}
	}

	isFirst = true;
	char *outString = malloc(outLength * sizeof(char));
	*outString = 0;

	for (int i = 0; i < count; i++) {
		if (components[i]) {
			if (isFirst) {
				strlcpy(outString, components[i], outLength);
				isFirst = false;
			}
			else {
				char separatorString[2] = { separator, 0 };
				strlcat(outString, (char *)separatorString, outLength);
				strlcat(outString, components[i], outLength);
			}
		}
	}

	return outString;
}

bool systemwide_domain_allowed(audit_token_t clientToken)
{
	if (!gSystemwideDomainEnabled) {
		// While the jailbreak is hidden, we need to disable the systemwide domain
		pid_t pid = audit_token_to_pid(clientToken);
		char procPath[4*MAXPATHLEN];
		if (proc_pidpath(pid, procPath, sizeof(procPath)) <= 0) {
			return false;
		}

		if (string_has_suffix(procPath, "/Dopamine.app/Dopamine")) {
			// We still want it to be accessible by Dopamine itself though
			// Unfortunately, there is not really a better check here since
			// - Dopamine can be sideloaded, so no control over entitlements
			// - App identifier could be changed by whoever installed it aswell
			return true;
		}

		return false;
	}
	return true;
}

static int systemwide_get_jbroot(char **rootPathOut)
{
	*rootPathOut = strdup(jbinfo(rootPath));
	return 0;
}

static int systemwide_get_boot_uuid(char **bootUUIDOut)
{
	const char *launchdUUID = getenv("LAUNCHD_UUID");
	*bootUUIDOut = launchdUUID ? strdup(launchdUUID) : NULL;
	return 0;
}

CS_SuperBlob *siginfo_resolve_superblob(struct siginfo *siginfo, int pid, int fd)
{
	if (!siginfo) return NULL;
	if (siginfo->signature.fs_blob_size == 0) return NULL;

	size_t superblobSize = siginfo->signature.fs_blob_size;
	CS_SuperBlob *superblob = malloc(superblobSize);
	if (!superblob) return NULL;

	bool success = false;

	switch (siginfo->source) {
		case SIGNATURE_SOURCE_FILE: {
			uintptr_t superblobStart = siginfo->signature.fs_file_start + (uintptr_t)siginfo->signature.fs_blob_start;
			uintptr_t superblobEnd   = superblobStart + superblobSize;
			struct stat st = {};

        	if (fstat(fd, &st) != 0) break;
			if (superblobEnd > st.st_size) break;
			if (lseek(fd, superblobStart, SEEK_SET) != superblobStart) break;
			if (read(fd, superblob, superblobSize) != superblobSize) break;

			success = true;
		}
		case SIGNATURE_SOURCE_PROC: {
			uint64_t proc = proc_find(pid);

			if (!proc) break;
			if (proc_vreadbuf(proc, siginfo->signature.fs_blob_start, superblob, superblobSize) != 0) break;

			success = true;
		}
	}

	if (!success) {
		free(superblob);
		superblob = NULL;
	}

	return superblob;
}

int systemwide_trust_file(audit_token_t *processToken, int rfd, struct siginfo *siginfo, size_t siginfoSize)
{
	if (siginfo && siginfoSize != sizeof(struct siginfo)) return -1;

	pid_t pid = -1;
	int fd = -1;
	if (!processToken) {
		pid = 1;
		fd = dup(rfd);
	}
	else {
		pid = audit_token_to_pid(*processToken);
		struct vnode_fdinfowithpath vnodeInfo;
		int ok = proc_pidfdinfo(pid, rfd, PROC_PIDFDVNODEPATHINFO, &vnodeInfo, sizeof(vnodeInfo));
		if (ok > 0) {
			fd = open(vnodeInfo.pvip.vip_path, O_RDONLY);
		}
	}

	if (fd < 0) return -1;

	struct statfs fsb;
	int fsr = fstatfs(fd, &fsb);
	if (fsr == 0) {
		// Anything on the rootfs or fakelib mount point can be ignored as it's guaranteed to already be in trustcache
		if (!strcmp(fsb.f_mntonname, "/") || !strcmp(fsb.f_mntonname, "/usr/lib")) {
			close(fd);
			return 0;
		}
	}

	cdhash_t *cdhashes = NULL;
	uint32_t cdhashesCount = 0;

	if (siginfo) {
		// If we were passed a siginfo, get the cdhash of the superblob from the siginfo
		CS_SuperBlob *superblob = siginfo_resolve_superblob(siginfo, pid, fd);
		if (superblob) {
			cdhash_t cdhash;
			if (code_signature_calculate_adhoc_cdhash(superblob, cdhash)) {
				if (!is_cdhash_trustcached(cdhash)) {
					cdhashes = malloc(sizeof(cdhash_t));
					cdhashesCount = 1;
					memcpy(&cdhashes[0], &cdhash, sizeof(cdhash_t));
				}
			}
			free(superblob);
		}
	}
	else {
		// If we weren't passed a siginfo, get cdhashes of all slices
		file_collect_untrusted_cdhashes(fd, &cdhashes, &cdhashesCount);
	}
	
	if (cdhashes && cdhashesCount > 0) {
		jb_trustcache_add_cdhashes(cdhashes, cdhashesCount);
		free(cdhashes);
	}

	close(fd);
	return 0;
}

int systemwide_trust_file_by_path(const char *path)
{
	int fd = open(path, O_RDONLY);
	if (fd < 0) return -1;
	int r = systemwide_trust_file(NULL, fd, NULL, 0);
	close(fd);
	return r;
}

int systemwide_process_checkin(audit_token_t *processToken, char **rootPathOut, char **bootUUIDOut, char **sandboxExtensionsOut, bool *fullyDebuggedOut)
{
	// Fetch process info
	pid_t pid = audit_token_to_pid(*processToken);
	char procPath[4*MAXPATHLEN];
	if (proc_pidpath(pid, procPath, sizeof(procPath)) <= 0) {
		return -1;
	}

	// Find proc in kernelspace
	uint64_t proc = proc_find(pid);
	if (!proc) {
		return -1;
	}

	// Get jbroot and boot uuid
	systemwide_get_jbroot(rootPathOut);
	systemwide_get_boot_uuid(bootUUIDOut);

	// Generate sandbox extensions for the requesting process
	char *sandboxExtensionsArr[] = {
		// Make /var/jb readable and executable
		sandbox_extension_issue_file_to_process("com.apple.app-sandbox.read", JBROOT_PATH(""), 0, *processToken),
		sandbox_extension_issue_file_to_process("com.apple.sandbox.executable", JBROOT_PATH(""), 0, *processToken),

		// Make /var/jb/var/mobile writable
		sandbox_extension_issue_file_to_process("com.apple.app-sandbox.read-write", JBROOT_PATH("/var/mobile"), 0, *processToken),
	};
	int sandboxExtensionsCount = sizeof(sandboxExtensionsArr) / sizeof(char *);
	*sandboxExtensionsOut = combine_strings('|', sandboxExtensionsArr, sandboxExtensionsCount);
	for (int i = 0; i < sandboxExtensionsCount; i++) {
		if (sandboxExtensionsArr[i]) {
			free(sandboxExtensionsArr[i]);
		}
	}

	bool fullyDebugged = false;
	if (string_has_prefix(procPath, "/private/var/containers/Bundle/Application") || string_has_prefix(procPath, JBROOT_PATH("/Applications"))) {
		// This is an app, enable CS_DEBUGGED based on user preference
		if (jbsetting(markAppsAsDebugged)) {
			fullyDebugged = true;
		}
	}
	*fullyDebuggedOut = fullyDebugged;

	// Allow invalid pages
	cs_allow_invalid(proc, fullyDebugged);

	// Fix setuid
	struct stat sb;
	if (stat(procPath, &sb) == 0) {
		if (S_ISREG(sb.st_mode) && (sb.st_mode & (S_ISUID | S_ISGID))) {
			uint64_t ucred = proc_ucred(proc);
			if ((sb.st_mode & (S_ISUID))) {
				kwrite32(proc + koffsetof(proc, svuid), sb.st_uid);
				kwrite32(ucred + koffsetof(ucred, svuid), sb.st_uid);
				kwrite32(ucred + koffsetof(ucred, uid), sb.st_uid);
			}
			if ((sb.st_mode & (S_ISGID))) {
				kwrite32(proc + koffsetof(proc, svgid), sb.st_gid);
				kwrite32(ucred + koffsetof(ucred, svgid), sb.st_gid);
				kwrite32(ucred + koffsetof(ucred, groups), sb.st_gid);
			}
			uint32_t flag = kread32(proc + koffsetof(proc, flag));
			if ((flag & P_SUGID) != 0) {
				flag &= ~P_SUGID;
				kwrite32(proc + koffsetof(proc, flag), flag);
			}
		}
	}

	if (__builtin_available(iOS 16.0, *)) {
		// In iOS 16+ there is a super annoying security feature called Protobox
		// Amongst other things, it allows for a process to have a syscall mask
		// If a process calls a syscall it's not allowed to call, it immediately crashes
		// Because for tweaks and hooking this is unacceptable, we update these masks to be 1 for all syscalls on all processes
		// That will at least get rid of the syscall mask part of Protobox
		proc_allow_all_syscalls(proc);

		// Some processes also have a filter for mach messages, fortunately there is one allowed message id that can be used for the check-in
		// Then we remove the filter to make other message ids accessible afterwards aswell
		proc_remove_msg_filter(proc);
	}

	// For whatever reason after SpringBoard has restarted, AutoFill and other stuff stops working
	// The fix is to always also restart the kbd daemon alongside SpringBoard
	// Seems to be something sandbox related where kbd doesn't have the right extensions until restarted
	if (strcmp(procPath, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") == 0) {
		static bool springboardStartedBefore = false;
		if (!springboardStartedBefore) {
			// Ignore the first SpringBoard launch after userspace reboot
			// This fix only matters when SpringBoard gets restarted during runtime
			springboardStartedBefore = true;
		}
		else {
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				killall("/System/Library/TextInput/kbd", SIGKILL);
			});
		}
	}
	// For the Dopamine app itself we want to give it a saved uid/gid of 0, unsandbox it and give it CS_PLATFORM_BINARY
	// This is so that the buttons inside it can work when jailbroken, even if the app was not installed by TrollStore
	else if (string_has_suffix(procPath, "/Dopamine.app/Dopamine")) {
		// svuid = 0, svgid = 0
		uint64_t ucred = proc_ucred(proc);
		kwrite32(proc + koffsetof(proc, svuid), 0);
		kwrite32(ucred + koffsetof(ucred, svuid), 0);
		kwrite32(proc + koffsetof(proc, svgid), 0);
		kwrite32(ucred + koffsetof(ucred, svgid), 0);

		// platformize
		proc_csflags_set(proc, CS_PLATFORM_BINARY);
	}

#ifdef __arm64e__
	// On arm64e every image has a trust level associated with it
	// "In trust cache" trust levels have higher runtime enforcements, this can be a problem for some tools as Dopamine trustcaches everything that's adhoc signed
	// So we add the ability for a binary to get a different trust level using the "jb.pmap_cs_custom_trust" entitlement
	// This is for binaries that rely on weaker PMAP_CS checks (e.g. Lua trampolines need it)
	xpc_object_t customTrustObj = xpc_copy_entitlement_for_token("jb.pmap_cs.custom_trust", processToken);
	if (customTrustObj) {
		if (xpc_get_type(customTrustObj) == XPC_TYPE_STRING) {
			const char *customTrustStr = xpc_string_get_string_ptr(customTrustObj);
			uint32_t customTrust = pmap_cs_trust_string_to_int(customTrustStr);
			if (customTrust >= 2) {
				uint64_t mainCodeDir = proc_find_main_binary_code_dir(proc);
				if (mainCodeDir) {
					kwrite32(mainCodeDir + koffsetof(pmap_cs_code_directory, trust), customTrust);
				}
			}
		}
	}
#endif

	proc_rele(proc);
	return 0;
}

int systemwide_fork_fix(audit_token_t *parentToken, uint64_t childPid)
{
	int retval = 3;
	uint64_t parentPid = audit_token_to_pid(*parentToken);
	uint64_t parentProc = proc_find(parentPid);
	uint64_t childProc = proc_find(childPid);

	if (childProc && parentProc) {
		retval = 2;
		// Safety check to ensure we are actually coming from fork
		if (kread_ptr(childProc + koffsetof(proc, pptr)) == parentProc) {
			cs_allow_invalid(childProc, false);

			uint64_t childTask  = proc_task(childProc);
			uint64_t childVmMap = kread_ptr(childTask + koffsetof(task, map));

			uint64_t parentTask  = proc_task(parentProc);
			uint64_t parentVmMap = kread_ptr(parentTask + koffsetof(task, map));

			uint64_t parentHeader = kread_ptr(parentVmMap  + koffsetof(vm_map, hdr));
			uint64_t parentEntry  = kread_ptr(parentHeader + koffsetof(vm_map_header, links) + koffsetof(vm_map_links, next));

			uint64_t childHeader  = kread_ptr(childVmMap  + koffsetof(vm_map, hdr));
			uint64_t childEntry   = kread_ptr(childHeader + koffsetof(vm_map_header, links) + koffsetof(vm_map_links, next));

			uint64_t childFirstEntry = childEntry, parentFirstEntry = parentEntry;
			do {
				uint64_t childStart  = kread_ptr(childEntry  + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, min));
				uint64_t childEnd    = kread_ptr(childEntry  + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, max));
				uint64_t parentStart = kread_ptr(parentEntry + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, min));
				uint64_t parentEnd   = kread_ptr(parentEntry + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, max));

				if (parentStart < childStart) {
					parentEntry = kread_ptr(parentEntry + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, next));
				}
				else if (parentStart > childStart) {
					childEntry = kread_ptr(childEntry + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, next));
				}
				else {
					uint64_t parentFlags = kread64(parentEntry + koffsetof(vm_map_entry, flags));
					uint64_t childFlags  = kread64(childEntry  + koffsetof(vm_map_entry, flags));

					uint8_t parentProt = VM_FLAGS_GET_PROT(parentFlags), parentMaxProt = VM_FLAGS_GET_MAXPROT(parentFlags);
					uint8_t childProt  = VM_FLAGS_GET_PROT(childFlags),  childMaxProt  = VM_FLAGS_GET_MAXPROT(childFlags);

					if (parentProt != childProt || parentMaxProt != childMaxProt) {
						VM_FLAGS_SET_PROT(childFlags, parentProt);
						VM_FLAGS_SET_MAXPROT(childFlags, parentMaxProt);
						kwrite64(childEntry + koffsetof(vm_map_entry, flags), childFlags);
					}

					parentEntry = kread_ptr(parentEntry + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, next));
					childEntry  = kread_ptr(childEntry  + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, next));
				}
			} while (parentEntry != 0 && childEntry != 0 && parentEntry != parentFirstEntry && childEntry != childFirstEntry);
			retval = 0;
		}
	}
	if (childProc)  proc_rele(childProc);
	if (parentProc) proc_rele(parentProc);

	return retval;
}

static int systemwide_cs_revalidate(audit_token_t *callerToken)
{
	uint64_t callerPid = audit_token_to_pid(*callerToken);
	if (callerPid > 0) {
		uint64_t callerProc = proc_find(callerPid);
		if (callerProc) {
			proc_csflags_set(callerProc, CS_VALID);
			return 0;
		}
	}
	return -1;
}

struct jbserver_domain gSystemwideDomain = {
	.permissionHandler = systemwide_domain_allowed,
	.actions = {
		// JBS_SYSTEMWIDE_GET_JBROOT
		{
			.handler = systemwide_get_jbroot,
			.args = (jbserver_arg[]){
				{ .name = "root-path", .type = JBS_TYPE_STRING, .out = true },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_GET_BOOT_UUID
		{
			.handler = systemwide_get_boot_uuid,
			.args = (jbserver_arg[]){
				{ .name = "boot-uuid", .type = JBS_TYPE_STRING, .out = true },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_TRUST_FILE
		{
			.handler = systemwide_trust_file,
			.args = (jbserver_arg[]){
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "fd", .type = JBS_TYPE_UINT64, .out = false },
				{ .name = "siginfo", .type = JBS_TYPE_DATA, .out = false },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_PROCESS_CHECKIN
		{
			.handler = systemwide_process_checkin,
			.args = (jbserver_arg[]) {
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "root-path", .type = JBS_TYPE_STRING, .out = true },
				{ .name = "boot-uuid", .type = JBS_TYPE_STRING, .out = true },
				{ .name = "sandbox-extensions", .type = JBS_TYPE_STRING, .out = true },
				{ .name = "fully-debugged", .type = JBS_TYPE_BOOL, .out = true },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_FORK_FIX
		{
			.handler = systemwide_fork_fix,
			.args = (jbserver_arg[]) {
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ .name = "child-pid", .type = JBS_TYPE_UINT64, .out = false },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_CS_REVALIDATE
		{
			.handler = systemwide_cs_revalidate,
			.args = (jbserver_arg[]) {
				{ .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
				{ 0 },
			},
		},
		// JBS_SYSTEMWIDE_JBSETTINGS_GET
		{
			.handler = jbsettings_get,
			.args = (jbserver_arg[]){
				{ .name = "key", .type = JBS_TYPE_STRING, .out = false },
				{ .name = "value", .type = JBS_TYPE_XPC_GENERIC, .out = true },
			},
		},
		{ 0 },
	},
};