#include "jbserver_global.h"
#include "jbsettings.h"
#include <libjailbreak/info.h>
#include <sandbox.h>
#include <libproc.h>
#include <sys/proc_info.h>

#include <libjailbreak/hookd.h>
#include <libjailbreak/signatures.h>
#include <libjailbreak/trustcache.h>
#include <libjailbreak/kernel.h>
#include <libjailbreak/util.h>
#include <libjailbreak/primitives.h>
#include <libjailbreak/codesign.h>
#include <libjailbreak/txm.h>

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

                // We still want it to be accessible by Dopamine itself though
                if (is_dopamine_app(procPath)) return true;

                // RootHide port: executables living INSIDE the jbroot must always be
                // able to check in. These are the jailbreak's own tools and user-
                // installed apps (Sileo, Zebra, RootHide Manager, RootHidePatcher...).
                // Without check-in they never receive their sandbox extensions and
                // every file operation outside their own container fails with EPERM —
                // e.g. RootHidePatcher's "There was a problem with making the folder
                // for the deb" (createDirectory on <jbroot>/var/mobile fails inside
                // the app sandbox once the domain is hidden).
                //
                // This does NOT weaken the hide: blacklisted apps are stripped of the
                // injected environment in spawn_hook BEFORE any check-in, and the
                // blacklist check (isBlacklistedPath) still runs first for every spawn.
                // Only jbroot-resident binaries — which the user launched from an
                // invisible-to-stock-iOS directory — reach this point.
                //
                // jbinfo(rootPath) comes from dladdr of launchdhook.dylib itself and
                // may be either the /var/... or the /private/var/... spelling, while
                // proc_pidpath returns the kernel-resolved path (usually /private/var
                // on iOS). Compare BOTH spellings to stay correct regardless of which
                // form the launchd instance recorded.
                static char jbrootPrefix[2][PATH_MAX];
                static bool jbrootPrefixResolved = false;
                if (!jbrootPrefixResolved) {
                        const char *rootPath = jbinfo(rootPath);
                        if (rootPath && rootPath[0]) {
                                strlcpy(jbrootPrefix[0], rootPath, sizeof(jbrootPrefix[0]));
                                size_t len = strlen(jbrootPrefix[0]);
                                if (len > 0 && jbrootPrefix[0][len-1] == '/') {
                                        jbrootPrefix[0][len-1] = '\0';
                                }
                                if (string_has_prefix(jbrootPrefix[0], "/private/")) {
                                        strlcpy(jbrootPrefix[1], &jbrootPrefix[0][sizeof("/private") - 1], sizeof(jbrootPrefix[1]));
                                } else if (string_has_prefix(jbrootPrefix[0], "/var/")
                                        || string_has_prefix(jbrootPrefix[0], "/usr/")
                                        || string_has_prefix(jbrootPrefix[0], "/bin/")
                                        || string_has_prefix(jbrootPrefix[0], "/etc/")) {
                                        snprintf(jbrootPrefix[1], sizeof(jbrootPrefix[1]), "/private%s", jbrootPrefix[0]);
                                } else {
                                        jbrootPrefix[1][0] = '\0';
                                }
                                jbrootPrefixResolved = true;
                        }
                }
                if (jbrootPrefixResolved && jbrootPrefix[0][0] != '\0' &&
                    (string_has_prefix(procPath, jbrootPrefix[0]) ||
                     (jbrootPrefix[1][0] != '\0' && string_has_prefix(procPath, jbrootPrefix[1])))) {
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
        // Trace reduction: the LAUNCHD_UUID environment variable is scrubbed
        // from launchd's environ right after boot (see launchdhook main.m), so
        // read the cached copy instead. Fall back to getenv for the early-boot
        // window before the scrub happened (boomerang / first-load paths).
        const char *launchdUUID = jbinfo(bootUUID);
        if (!launchdUUID) launchdUUID = getenv("LAUNCHD_UUID");
        *bootUUIDOut = launchdUUID ? strdup(launchdUUID) : NULL;
        return 0;
}

int systemwide_trust_file(audit_token_t *processToken, int rfd, struct siginfo *siginfo, size_t siginfoSize, bool attach)
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

        struct siginfo *sigInfos = NULL;
        uint32_t sigInfoCount = 0;
        int r = 0;

        if (siginfo) {
                sigInfoCount = 1;
                sigInfos = malloc(sizeof(struct siginfo));
                memcpy(&sigInfos[0], siginfo, sizeof(struct siginfo));
        }
        else {
                file_collect_signatures(fd, &sigInfos, &sigInfoCount);
        }

        if (sigInfoCount > 0) {
                r = trust_signatures(pid, fd, sigInfos, sigInfoCount);

                // Attach if requested
                if (attach) {
                        for (uint32_t i = 0; i < sigInfoCount; i++) {
                                if (sigInfos[i].source != SIGNATURE_SOURCE_ALLOCATION) {
                                        sigInfos[i].signature.fs_blob_start = siginfo_resolve_superblob(&sigInfos[i], pid, fd);
                                        sigInfos[i].source = SIGNATURE_SOURCE_ALLOCATION;
                                }

                                int rr = fcntl(fd, F_ADDSIGS, &sigInfos[i].signature);
                                if (rr != 0) r = rr;
                        }
                }

                // Free allocated signatures
                for (uint32_t i = 0; i < sigInfoCount; i++) {
                        if (sigInfos[i].source == SIGNATURE_SOURCE_ALLOCATION) {
                                free(sigInfos[i].signature.fs_blob_start);
                        }
                }
        }

        if (sigInfos) {
                free(sigInfos);
        }
        
        close(fd);
        return r;
}

int systemwide_trust_file_by_path(const char *path)
{
        int fd = open(path, O_RDONLY);
        if (fd < 0) return -1;
        int r = systemwide_trust_file(NULL, fd, NULL, 0, false);
        close(fd);
        return r;
}

int systemwide_process_checkin(audit_token_t *processToken, char **rootPathOut, char **bootUUIDOut, char **sandboxExtensionsOut, bool *fullyDebuggedOut, bool *forceCSAdhocOut)
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
                // Make jbroot readable and executable (RootHide: dynamic path)
                sandbox_extension_issue_file_to_process("com.apple.app-sandbox.read", JBROOT_PATH(""), 0, *processToken),
                sandbox_extension_issue_file_to_process("com.apple.sandbox.executable", JBROOT_PATH(""), 0, *processToken),

                // Make jbroot/var/mobile writable (RootHide: dynamic path)
                sandbox_extension_issue_file_to_process("com.apple.app-sandbox.read-write", JBROOT_PATH("/var/mobile"), 0, *processToken),

                // ROOTHIDE PATCHER IMPORT FIX: the Patcher app's DocumentPicker
                // does its deb import (copyItem into jbroot/var/mobile/
                // RootHidePatcher/.Inbox) silently — failures are swallowed with
                // just a print(). Some sandbox implementations don't honour the
                // umbrella /var/mobile extension for a freshly-created subfolder,
                // so the copy fails with no UI feedback and "Select .deb file"
                // appears to do nothing. Issue a dedicated read-write extension
                // for the Patcher work tree so the import always succeeds.
                // Harmless for every other process: the path may not exist yet
                // (it is pre-created by DOBootstrapper on every jailbreak).
                sandbox_extension_issue_file_to_process("com.apple.app-sandbox.read-write", JBROOT_PATH("/var/mobile/RootHidePatcher"), 0, *processToken),
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

        // CS_ADHOC needs to be forced in dyld's fcntl hook on SPTM devices
        *forceCSAdhocOut = (ksymbol(SPTMArgs) != 0);

        // Allow invalid pages
        cs_allow_invalid(proc, fullyDebugged);

        // Fix setuid
        struct stat sb;
        if (stat(procPath, &sb) == 0) {
                if (S_ISREG(sb.st_mode) && (sb.st_mode & (S_ISUID | S_ISGID))) {
                        uint64_t ucred = proc_ucred(proc);

                        gid_t groups[NGROUPS_MAX];
                        kreadbuf(ucred + koffsetof(ucred, groups), groups, sizeof(groups));

                        int uid = kread32(ucred + koffsetof(ucred, uid)), gid = groups[0];
                        int ruid = kread32(ucred + koffsetof(ucred, ruid)), rgid = kread32(ucred + koffsetof(ucred, rgid));
                        int old_uid = uid, old_gid = gid;

                        if ((sb.st_mode & (S_ISUID))) {
                                kwrite32(proc + koffsetof(proc, svuid), sb.st_uid);
                                uid = sb.st_uid;
                        }
                        if ((sb.st_mode & (S_ISGID))) {
                                kwrite32(proc + koffsetof(proc, svgid), sb.st_gid);
                                gid = sb.st_gid;
                        }

                        if (old_uid != uid || old_gid != gid) {
                                proc_ucred_update_content(proc, procPath, uid, gid, ruid, rgid, groups);
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
        else if (is_dopamine_app(procPath)) {
                // platformize
                proc_csflags_set(proc, CS_PLATFORM_BINARY);
        }

        xpc_object_t customTrustObj = xpc_copy_entitlement_for_token("jb.pmap_cs.custom_trust", processToken);
        if (customTrustObj) {
                if (xpc_get_type(customTrustObj) == XPC_TYPE_STRING) {
                        const char *customTrustStr = xpc_string_get_string_ptr(customTrustObj);
                        uint32_t customTrust = pmap_cs_trust_string_to_int(customTrustStr);

                        if (host_is_arm64e()) {
                                if (customTrust >= 2) {
                                        uint64_t mainCodeDir = proc_find_main_binary_code_dir(proc);
                                        if (mainCodeDir) {
                                                kwrite32(mainCodeDir + koffsetof(pmap_cs_code_directory, trust), customTrust);
                                        }
                                }
                        }

                        if (__builtin_available(iOS 17.0, *)) {
                                if (customTrust <= pmap_cs_trust_string_to_int("PMAP_CS_APP_STORE")) {
                                        proc_csflags_clear(proc, CS_PLATFORM_BINARY);

                                        uint64_t proc_ro = kread_ptr(proc + koffsetof(proc, proc_ro));
                                        uint32_t t_flags = kread32(proc_ro + koffsetof(proc_ro, t_flags_ro));
                                        
                                        t_flags &= ~(kconstant(TFRO_PLATFORM));
                                        if (kconstant(TFRO_HARDENED)) {
                                                t_flags &= ~(kconstant(TFRO_HARDENED));
                                        }

                                        kwrite32(proc_ro + koffsetof(proc_ro, t_flags_ro), t_flags);

                                        if (koffsetof(task, security_config)) {
                                                uint64_t task = proc_task(proc);
                                                kwrite8(task + koffsetof(task, security_config), kread8(task + koffsetof(task, security_config)) & ~(0b111 << 3));
                                        }
                                }
                        }
                }
        }

        proc_rele(proc);
        return 0;
}

int txm_fork_fix(uint64_t parentAddressSpace, uint64_t childAddressSpace)
{
        uint64_t parentHead = parentAddressSpace + koffsetof(TXMAddressSpace, codeRegions);
        uint64_t childHead  =  childAddressSpace + koffsetof(TXMAddressSpace, codeRegions);

        uint64_t curCodeRegion = 0, nextCodeRegion = 0;
        for (curCodeRegion = RB_MIN(TXMCodeRegionRBTree, parentHead); curCodeRegion; curCodeRegion = nextCodeRegion) {
                nextCodeRegion = RB_NEXT(TXMCodeRegionRBTree, parentHead, curCodeRegion);

                uint8_t  curRegionType      =    kread8(curCodeRegion + koffsetof(TXMCodeRegion, type));
                uint64_t curRegionStartAddr =   kread64(curCodeRegion + koffsetof(TXMCodeRegion, startAddr));
                uint64_t curRegionEndAddr   =   kread64(curCodeRegion + koffsetof(TXMCodeRegion, endAddr));
                uint64_t curRegionCodeSig   = kread_ptr(curCodeRegion + koffsetof(TXMCodeRegion, codeSignature));

                uint64_t childCodeRegion = RB_FIND(TXMCodeRegionRBTree, childHead, CodeRegionRBTree_KEY(curRegionStartAddr));
                if (!childCodeRegion && !curRegionCodeSig) {
                        // If no region exists in the child yet, allocate a new one
                        // But only if the parent region does not have a code signature
                        childCodeRegion = allocateCodeRegionObject();

                        kwrite64(childCodeRegion + koffsetof(TXMCodeRegion, startAddr), curRegionStartAddr);
                        kwrite64(childCodeRegion + koffsetof(TXMCodeRegion, endAddr),   curRegionEndAddr);

                        RB_INSERT(TXMCodeRegionRBTree, childHead, childCodeRegion);
                }

                if (childCodeRegion) {
                        // Copy type from parent to child
                        kwrite8(childCodeRegion + koffsetof(TXMCodeRegion, type), curRegionType);
                }
        }

        return 0;
}

int systemwide_fork_fix(audit_token_t *parentToken, uint64_t childPid)
{
        int retval = 3;
        uint64_t parentPid  = audit_token_to_pid(*parentToken);
        uint64_t parentProc = proc_find(parentPid);
        uint64_t childProc  = proc_find(childPid);

        if (childProc && parentProc) {
                retval = 2;
                // Safety check to ensure we are actually coming from fork
                if (kread_ptr(childProc + koffsetof(proc, pptr)) == parentProc) {
                        uint64_t parentTask  = proc_task(parentProc);
                        uint64_t parentVmMap = kread_ptr(parentTask + koffsetof(task, map));
                        uint64_t parentPmap  = kread_ptr(parentVmMap + koffsetof(vm_map, pmap));

                        uint64_t childTask  = proc_task(childProc);
                        uint64_t childVmMap = kread_ptr(childTask + koffsetof(task, map));
                        uint64_t childPmap  = kread_ptr(childVmMap + koffsetof(vm_map, pmap));

                        cs_allow_invalid(childProc, false);

                        uint64_t parentHeader   = parentVmMap + koffsetof(vm_map, hdr);
                        uint32_t parentNentries = kread32(parentHeader + koffsetof(vm_map_header, nentries));
                        uint64_t parentEntry    = kread_ptr(parentHeader + koffsetof(vm_map_header, first));

                        uint64_t childHeader   = childVmMap + koffsetof(vm_map, hdr);
                        uint32_t childNentries = kread32(childHeader + koffsetof(vm_map_header, nentries));
                        uint64_t childEntry    = kread_ptr(childHeader + koffsetof(vm_map_header, first));

                        uint64_t childFirstEntry = childEntry, parentFirstEntry = parentEntry;
                        uint32_t childIdx = 0, parentIdx = 0;
                        do {
                                uint64_t childStart  = kread_ptr(childEntry  + koffsetof(vm_map_entry, start));
                                uint64_t childEnd    = kread_ptr(childEntry  + koffsetof(vm_map_entry, end));
                                uint64_t parentStart = kread_ptr(parentEntry + koffsetof(vm_map_entry, start));
                                uint64_t parentEnd   = kread_ptr(parentEntry + koffsetof(vm_map_entry, end));

                                if (parentStart < childStart) {
                                        parentEntry = kread_ptr(parentEntry + koffsetof(vm_map_entry, next));
                                        parentIdx++;
                                }
                                else if (parentStart > childStart) {
                                        childEntry = kread_ptr(childEntry + koffsetof(vm_map_entry, next));
                                        childIdx++;
                                }
                                else {
                                        uint64_t parentFlags = kread64(parentEntry + koffsetof(vm_map_entry, flags));
                                        uint64_t childFlags  = kread64(childEntry  + koffsetof(vm_map_entry, flags));

                                        uint8_t parentProt = VM_FLAGS_GET_PROT(parentFlags), parentMaxProt = VM_FLAGS_GET_MAXPROT(parentFlags);
                                        uint8_t childProt  = VM_FLAGS_GET_PROT(childFlags),  childMaxProt  = VM_FLAGS_GET_MAXPROT(childFlags);

                                        bool childFlagsNeedUpdate = false;

                                        if (parentProt != childProt || parentMaxProt != childMaxProt) {
                                                VM_FLAGS_SET_PROT(childFlags, parentProt);
                                                VM_FLAGS_SET_MAXPROT(childFlags, parentMaxProt);
                                                childFlagsNeedUpdate = true;
                                        }

                                        if (__builtin_available(iOS 16.0, *)) {
                                                // On iOS 16+ devices, there exists the vme_xnu_user_debug flag, which we also need to copy
                                                bool parentUserDebugFlag = VM_FLAGS_GET_XNU_USER_DEBUG(parentFlags);
                                                bool childUserDebugFlag  = VM_FLAGS_GET_XNU_USER_DEBUG(childFlags);
                                                if (parentUserDebugFlag != childUserDebugFlag) {
                                                        VM_FLAGS_SET_XNU_USER_DEBUG(childFlags, parentUserDebugFlag);
                                                        childFlagsNeedUpdate = true;
                                                }
                                        }

                                        if (childFlagsNeedUpdate) {
                                                kwrite64(childEntry + koffsetof(vm_map_entry, flags), childFlags);
                                        }

                                        parentEntry = kread_ptr(parentEntry + koffsetof(vm_map_entry, next));
                                        parentIdx++;
                                        childEntry  = kread_ptr(childEntry  + koffsetof(vm_map_entry, next));
                                        childIdx++;
                                }
                        } while (parentEntry != 0 && childEntry != 0 && parentEntry != parentFirstEntry && childEntry != childFirstEntry && parentIdx < parentNentries && childIdx < childNentries);

                        retval = 0;
                        // On TXM devices, fix up the TXM address space aswell
                        if (koffsetof(pmap, txm_address_space)) {
                                uint64_t parentAddressSpace = kread_ptr(parentPmap + koffsetof(pmap, txm_address_space));
                                uint64_t childAddressSpace  = kread_ptr(childPmap  + koffsetof(pmap, txm_address_space));
                                retval = txm_fork_fix(parentAddressSpace, childAddressSpace);
                        }
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

static int systemwide_persona_fix(audit_token_t *callerToken, int childPid, uid_t overwriteUid, gid_t overwriteGid)
{
        bool hasPersonaMgmtEntitlement = false;
        xpc_object_t *personaMgmtVal = xpc_copy_entitlement_for_token("com.apple.private.persona-mgmt", callerToken);
        if (personaMgmtVal) {
                if (xpc_get_type(personaMgmtVal) == XPC_TYPE_INT64) {
                        hasPersonaMgmtEntitlement = xpc_int64_get_value(personaMgmtVal) == 1;
                }
                else if (xpc_get_type(personaMgmtVal) == XPC_TYPE_UINT64) {
                        hasPersonaMgmtEntitlement = xpc_uint64_get_value(personaMgmtVal) == 1;
                }
                else if (xpc_get_type(personaMgmtVal) == XPC_TYPE_BOOL) {
                        hasPersonaMgmtEntitlement = xpc_bool_get_value(personaMgmtVal);
                }
        }

        if (!hasPersonaMgmtEntitlement) return -1;

        uint64_t childProc = proc_find(childPid);
        if (!childProc) return -1;

        char childProcPath[4*MAXPATHLEN];
        if (proc_pidpath(childPid, childProcPath, sizeof(childProcPath)) <= 0) {
                return -1;
        }

        uint64_t childUcred = proc_ucred(childProc);

        gid_t groups[NGROUPS_MAX];
        kreadbuf(childUcred + koffsetof(ucred, groups), groups, sizeof(groups));

        int uid = kread32(childUcred + koffsetof(ucred, uid)), gid = groups[0];
        int ruid = kread32(childUcred + koffsetof(ucred, ruid)), rgid = kread32(childUcred + koffsetof(ucred, rgid));
        int old_uid = uid, old_gid = gid;

        if (overwriteUid != -1) {
                uid = overwriteUid;
                kwrite32(childProc + koffsetof(proc, svuid), uid);
        }
        if (overwriteGid != -1) {
                gid = overwriteGid;
                kwrite32(childProc + koffsetof(proc, svgid), gid);
        }

        if (old_uid != uid || old_gid != gid) {
                if (old_gid != gid) groups[0] = gid;
                proc_ucred_update_content(childProc, childProcPath, uid, gid, uid, gid, groups);
        }

        return 0;
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
                                { .name = "attach", .type = JBS_TYPE_BOOL, .out = false },
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
                                { .name = "force-cs-adhoc", .type = JBS_TYPE_BOOL, .out = true },
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
                        .args = (jbserver_arg[]) {
                                { .name = "key", .type = JBS_TYPE_STRING, .out = false },
                                { .name = "value", .type = JBS_TYPE_XPC_GENERIC, .out = true },
                        },
                },
                // JBS_SYSTEMWIDE_PERSONA_FIX
                {
                        .handler = systemwide_persona_fix,
                        .args = (jbserver_arg[]) {
                                { .name = "caller-token", .type = JBS_TYPE_CALLER_TOKEN, .out = false },
                                { .name = "child-pid", .type = JBS_TYPE_UINT64, .out = false },
                                { .name = "overwrite-uid", .type = JBS_TYPE_UINT64, .out = false },
                                { .name = "overwrite-gid", .type = JBS_TYPE_UINT64, .out = false },
                        },
                },
                { 0 },
        },
};