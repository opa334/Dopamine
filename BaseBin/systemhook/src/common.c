#include "common.h"
#include <xpc/xpc.h>
#include "launchd.h"
#include <mach-o/dyld.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sandbox.h>
#include <paths.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include "envbuf.h"

#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
int posix_spawnattr_getprocesstype_np(const posix_spawnattr_t * __restrict, int * __restrict) __API_AVAILABLE(macos(10.8), ios(6.0));

char *JB_SandboxExtensions = NULL;
char *JB_RootPath = NULL;

#define JBD_MSG_SETUID_FIX 21
#define JBD_MSG_PROCESS_BINARY 22
#define JBD_MSG_DEBUG_ME 24
#define JBD_MSG_FORK_FIX 25
#define JBD_MSG_INTERCEPT_USERSPACE_PANIC 26

#define JETSAM_MULTIPLIER 3
#define XPC_TIMEOUT 0.1 * NSEC_PER_SEC

#define POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE 0x48
#define POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE 0x4C

bool swh_is_debugged = false;

bool stringStartsWith(const char *str, const char* prefix)
{
	if (!str || !prefix) {
		return false;
	}

	size_t str_len = strlen(str);
	size_t prefix_len = strlen(prefix);

	if (str_len < prefix_len) {
		return false;
	}

	return !strncmp(str, prefix, prefix_len);
}

bool stringEndsWith(const char* str, const char* suffix)
{
	if (!str || !suffix) {
		return false;
	}

	size_t str_len = strlen(str);
	size_t suffix_len = strlen(suffix);

	if (str_len < suffix_len) {
		return false;
	}

	return !strcmp(str + str_len - suffix_len, suffix);
}

extern char **environ;
kern_return_t bootstrap_look_up(mach_port_t port, const char *service, mach_port_t *server_port);

bool jbdSystemWideIsReachable(void)
{
	int sbc = sandbox_check(getpid(), "mach-lookup", SANDBOX_FILTER_GLOBAL_NAME | SANDBOX_CHECK_NO_REPORT, "com.opa334.jailbreakd.systemwide");
	return sbc == 0;
}

mach_port_t jbdSystemWideMachPort(void)
{
	mach_port_t outPort = MACH_PORT_NULL;
	kern_return_t kr = KERN_SUCCESS;

	if (getpid() == 1) {
		mach_port_t self_host = mach_host_self();
		kr = host_get_special_port(self_host, HOST_LOCAL_NODE, 16, &outPort);
		mach_port_deallocate(mach_task_self(), self_host);
	}
	else {
		kr = bootstrap_look_up(bootstrap_port, "com.opa334.jailbreakd.systemwide", &outPort);
	}

	if (kr != KERN_SUCCESS) return MACH_PORT_NULL;
	return outPort;
}

xpc_object_t sendLaunchdMessageFallback(xpc_object_t xdict)
{
	xpc_dictionary_set_bool(xdict, "jailbreak", true);
	xpc_dictionary_set_bool(xdict, "jailbreak-systemwide", true);

	void* pipePtr = NULL;
	if(_os_alloc_once_table[1].once == -1)
	{
		pipePtr = _os_alloc_once_table[1].ptr;
	}
	else
	{
		pipePtr = _os_alloc_once(&_os_alloc_once_table[1], 472, NULL);
		if (!pipePtr) _os_alloc_once_table[1].once = -1;
	}

	xpc_object_t xreply = nil;
	if (pipePtr) {
		struct xpc_global_data* globalData = pipePtr;
		xpc_object_t pipe = globalData->xpc_bootstrap_pipe;
		if (pipe) {
			int err = xpc_pipe_routine_with_flags(pipe, xdict, &xreply, 0);
			if (err != 0) {
				return nil;
			}
		}
	}
	return xreply;
}

xpc_object_t sendJBDMessageSystemWide(xpc_object_t xdict)
{
	xpc_object_t jbd_xreply = nil;
	if (jbdSystemWideIsReachable()) {
		mach_port_t jbdPort = jbdSystemWideMachPort();
		if (jbdPort != -1) {
			xpc_object_t pipe = xpc_pipe_create_from_port(jbdPort, 0);
			if (pipe) {
				int err = xpc_pipe_routine(pipe, xdict, &jbd_xreply);
				if (err != 0) jbd_xreply = nil;
				xpc_release(pipe);
			}
			mach_port_deallocate(mach_task_self(), jbdPort);
		}
	}

	if (!jbd_xreply && getpid() != 1) {
		return sendLaunchdMessageFallback(xdict);
	}

	return jbd_xreply;
}

int64_t jbdswFixSetuid(void)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_SETUID_FIX);
	xpc_object_t reply = sendJBDMessageSystemWide(message);
	int64_t result = -1;
	if (reply) {
		result  = xpc_dictionary_get_int64(reply, "result");
		xpc_release(reply);
	}
	return result;
}

int64_t jbdswProcessBinary(const char *filePath)
{
	// if file doesn't exist, bail out
	if (access(filePath, F_OK) != 0) return 0;

	// if file is on rootfs mount point, it doesn't need to be
	// processed as it's guaranteed to be in static trust cache
	// same goes for our /usr/lib bind mount (which is guaranteed to be in dynamic trust cache)
	struct statfs fs;
	int sfsret = statfs(filePath, &fs);
	if (sfsret == 0) {
		if (!strcmp(fs.f_mntonname, "/") || !strcmp(fs.f_mntonname, "/usr/lib")) return -1;
	}

	char absolutePath[PATH_MAX];
	if (realpath(filePath, absolutePath) == NULL) return -1;

	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_PROCESS_BINARY);
	xpc_dictionary_set_string(message, "filePath", absolutePath);

	xpc_object_t reply = sendJBDMessageSystemWide(message);
	int64_t result = -1;
	if (reply) {
		result  = xpc_dictionary_get_int64(reply, "result");
		xpc_release(reply);
	}
	return result;
}

int64_t jbdswProcessLibrary(const char *filePath)
{
	if (_dyld_shared_cache_contains_path(filePath)) return 0;
	return jbdswProcessBinary(filePath);
}

int64_t jbdswDebugMe(void)
{
	if (swh_is_debugged) return 0;
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_DEBUG_ME);
	xpc_object_t reply = sendJBDMessageSystemWide(message);
	int64_t result = -1;
	if (reply) {
		result  = xpc_dictionary_get_int64(reply, "result");
		xpc_release(reply);
	}
	if (result == 0) {
		swh_is_debugged = true;
	} 
	return result;
}

int64_t jbdswForkFix(pid_t childPid)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_FORK_FIX);
	xpc_dictionary_set_int64(message, "childPid", childPid);
	xpc_object_t reply = sendJBDMessageSystemWide(message);
	int64_t result = -1;
	if (reply) {
		result  = xpc_dictionary_get_int64(reply, "result");
		xpc_release(reply);
	}
	return result;
}

int64_t jbdswInterceptUserspacePanic(const char *messageString)
{
	xpc_object_t message = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(message, "id", JBD_MSG_INTERCEPT_USERSPACE_PANIC);
	xpc_dictionary_set_string(message, "message", messageString);
	xpc_object_t reply = sendJBDMessageSystemWide(message);
	int64_t result = -1;
	if (reply) {
		result  = xpc_dictionary_get_int64(reply, "result");
		xpc_release(reply);
	}
	return result;
}

// Derived from posix_spawnp in Apple libc
int resolvePath(const char *file, const char *searchPath, int (^attemptHandler)(char *path))
{
	const char *env_path;
	char *bp;
	char *cur;
	char *p;
	char **memp;
	int lp;
	int ln;
	int cnt;
	int err = 0;
	int eacces = 0;
	struct stat sb;
	char path_buf[PATH_MAX];

	env_path = searchPath;
	if (!env_path) {
		env_path = getenv("PATH");
		if (!env_path) {
			env_path = _PATH_DEFPATH;
		}
	}

	/* If it's an absolute or relative path name, it's easy. */
	if (index(file, '/')) {
		bp = (char *)file;
		cur = NULL;
		goto retry;
	}
	bp = path_buf;

	/* If it's an empty path name, fail in the usual POSIX way. */
	if (*file == '\0')
		return (ENOENT);

	if ((cur = alloca(strlen(env_path) + 1)) == NULL)
		return ENOMEM;
	strcpy(cur, env_path);
	while ((p = strsep(&cur, ":")) != NULL) {
		/*
		 * It's a SHELL path -- double, leading and trailing colons
		 * mean the current directory.
		 */
		if (*p == '\0') {
			p = ".";
			lp = 1;
		} else {
			lp = strlen(p);
		}
		ln = strlen(file);

		/*
		 * If the path is too long complain.  This is a possible
		 * security issue; given a way to make the path too long
		 * the user may spawn the wrong program.
		 */
		if (lp + ln + 2 > sizeof(path_buf)) {
			err = ENAMETOOLONG;
			goto done;
		}
		bcopy(p, path_buf, lp);
		path_buf[lp] = '/';
		bcopy(file, path_buf + lp + 1, ln);
		path_buf[lp + ln + 1] = '\0';

retry:		err = attemptHandler(bp);
		switch (err) {
		case E2BIG:
		case ENOMEM:
		case ETXTBSY:
			goto done;
		case ELOOP:
		case ENAMETOOLONG:
		case ENOENT:
		case ENOTDIR:
			break;
		case ENOEXEC:
			goto done;
		default:
			/*
			 * EACCES may be for an inaccessible directory or
			 * a non-executable file.  Call stat() to decide
			 * which.  This also handles ambiguities for EFAULT
			 * and EIO, and undocumented errors like ESTALE.
			 * We hope that the race for a stat() is unimportant.
			 */
			if (stat(bp, &sb) != 0)
				break;
			if (err == EACCES) {
				eacces = 1;
				continue;
			}
			goto done;
		}
	}
	if (eacces)
		err = EACCES;
	else
		err = ENOENT;
done:
	return (err);
}

void enumeratePathString(const char *pathsString, void (^enumBlock)(const char *pathString, bool *stop))
{
	char *pathsCopy = strdup(pathsString);
	char *pathString = strtok(pathsCopy, ":");
	while (pathString != NULL) {
		bool stop = false;
		enumBlock(pathString, &stop);
		if (stop) break;
		pathString = strtok(NULL, ":");
	}
	free(pathsCopy);
}

typedef enum 
{
	kBinaryConfigDontInject = 1 << 0,
	kBinaryConfigDontProcess = 1 << 1
} kBinaryConfig;

kBinaryConfig configForBinary(const char* path, char *const argv[restrict])
{
	// Don't do anything for jailbreakd because this wanting to launch implies it's not running currently
	if (stringEndsWith(path, "/jailbreakd")) {
		return (kBinaryConfigDontInject | kBinaryConfigDontProcess);
	}

	if (!strcmp(path, "/usr/libexec/xpcproxy")) {
		if (argv) {
			if (argv[0]) {
				if (argv[1]) {
					if (!strcmp(argv[1], "com.opa334.jailbreakd")) {
						// Don't do anything for xpcproxy if it's called on jailbreakd because this also implies jbd is not running currently
						return (kBinaryConfigDontInject | kBinaryConfigDontProcess);
					}
					else if (!strcmp(argv[1], "com.apple.ReportCrash")) {
						// Skip ReportCrash too as it might need to execute while jailbreakd is in a crashed state
						return (kBinaryConfigDontInject | kBinaryConfigDontProcess);
					}
					else if (!strcmp(argv[1], "com.apple.ReportMemoryException")) {
						// Skip ReportMemoryException too as it might need to execute while jailbreakd is in a crashed state
						return (kBinaryConfigDontInject | kBinaryConfigDontProcess);
					}
				}
			}
		}
	}

	// Blacklist to ensure general system stability
	// I don't like this but for some processes it seems neccessary
	const char *processBlacklist[] = {
		"/System/Library/Frameworks/GSS.framework/Helpers/GSSCred",
		"/System/Library/PrivateFrameworks/IDSBlastDoorSupport.framework/XPCServices/IDSBlastDoorService.xpc/IDSBlastDoorService",
		"/System/Library/PrivateFrameworks/MessagesBlastDoorSupport.framework/XPCServices/MessagesBlastDoorService.xpc/MessagesBlastDoorService",
		"/usr/sbin/wifid"
	};
	size_t blacklistCount = sizeof(processBlacklist) / sizeof(processBlacklist[0]);
	for (size_t i = 0; i < blacklistCount; i++)
	{
		if (!strcmp(processBlacklist[i], path)) return (kBinaryConfigDontInject | kBinaryConfigDontProcess);
	}

	return 0;
}

// 1. Make sure the about to be spawned binary and all of it's dependencies are trust cached
// 2. Insert "DYLD_INSERT_LIBRARIES=/usr/lib/systemhook.dylib" into all binaries spawned

int spawn_hook_common(pid_t *restrict pid, const char *restrict path,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict],
					   void *orig)
{
	int (*pspawn_orig)(pid_t *restrict, const char *restrict, const posix_spawn_file_actions_t *restrict, const posix_spawnattr_t *restrict, char *const[restrict], char *const[restrict]) = orig;
	if (!path) {
		return pspawn_orig(pid, path, file_actions, attrp, argv, envp);
	}

	kBinaryConfig binaryConfig = configForBinary(path, argv);

	if (!(binaryConfig & kBinaryConfigDontProcess)) {
		// jailbreakd: Upload binary to trustcache if needed
		jbdswProcessBinary(path);
	}

	const char *existingLibraryInserts = envbuf_getenv((const char **)envp, "DYLD_INSERT_LIBRARIES");
	__block bool systemHookAlreadyInserted = false;
	if (existingLibraryInserts) {
		enumeratePathString(existingLibraryInserts, ^(const char *existingLibraryInsert, bool *stop) {
			if (!strcmp(existingLibraryInsert, HOOK_DYLIB_PATH)) {
				systemHookAlreadyInserted = true;
			}
			else {
				jbdswProcessBinary(existingLibraryInsert);
			}
		});
	}

	int JBEnvAlreadyInsertedCount = (int)systemHookAlreadyInserted;

	if (envbuf_getenv((const char **)envp, "JB_SANDBOX_EXTENSIONS")) {
		JBEnvAlreadyInsertedCount++;
	}

	if (envbuf_getenv((const char **)envp, "JB_ROOT_PATH")) {
		JBEnvAlreadyInsertedCount++;
	}

	// Check if we can find at least one reason to not insert jailbreak related environment variables
	// In this case we also need to remove pre existing environment variables if they are already set
	bool shouldInsertJBEnv = true;
	bool hasSafeModeVariable = false;
	do {
		if (binaryConfig & kBinaryConfigDontInject) {
			shouldInsertJBEnv = false;
			break;
		}

		// Check if we can find a _SafeMode or _MSSafeMode variable
		// In this case we do not want to inject anything
		const char *safeModeValue = envbuf_getenv((const char **)envp, "_SafeMode");
		const char *msSafeModeValue = envbuf_getenv((const char **)envp, "_MSSafeMode");
		if (safeModeValue) {
			if (!strcmp(safeModeValue, "1")) {
				shouldInsertJBEnv = false;
				hasSafeModeVariable = true;
				break;
			}
		}
		if (msSafeModeValue) {
			if (!strcmp(msSafeModeValue, "1")) {
				shouldInsertJBEnv = false;
				hasSafeModeVariable = true;
				break;
			}
		}

		if (attrp) {
			int proctype = 0;
			posix_spawnattr_getprocesstype_np(attrp, &proctype);
			if (proctype == POSIX_SPAWN_PROC_TYPE_DRIVER) {
				// Do not inject hook into DriverKit drivers
				shouldInsertJBEnv = false;
				break;
			}
		}

		if (access(HOOK_DYLIB_PATH, F_OK) != 0) {
			// If the hook dylib doesn't exist, don't try to inject it (would crash the process)
			shouldInsertJBEnv = false;
			break;
		}
	} while (0);

	// If systemhook is being injected and Jetsam limits are set, increase them by a factor of JETSAM_MULTIPLIER
	if (shouldInsertJBEnv) {
		if (attrp) {
			uint8_t *attrStruct = *attrp;
			if (attrStruct) {
				int memlimit_active = *(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE);
				if (memlimit_active != -1) {
					*(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE) = memlimit_active * JETSAM_MULTIPLIER;
				}
				int memlimit_inactive = *(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE);
				if (memlimit_inactive != -1) {
					*(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE) = memlimit_inactive * JETSAM_MULTIPLIER;
				}
			}
		}
	}

	if ((shouldInsertJBEnv && JBEnvAlreadyInsertedCount == 3) || (!shouldInsertJBEnv && JBEnvAlreadyInsertedCount == 0 && !hasSafeModeVariable)) {
		// we're already good, just call orig
		return pspawn_orig(pid, path, file_actions, attrp, argv, envp);
	}
	else {
		// the state we want to be in is not the state we are in right now

		char **envc = envbuf_mutcopy((const char **)envp);

		if (shouldInsertJBEnv) {
			if (!systemHookAlreadyInserted) {
				char newLibraryInsert[strlen(HOOK_DYLIB_PATH) + (existingLibraryInserts ? (strlen(existingLibraryInserts) + 1) : 0) + 1];
				strcpy(newLibraryInsert, HOOK_DYLIB_PATH);
				if (existingLibraryInserts) {
					strcat(newLibraryInsert, ":");
					strcat(newLibraryInsert, existingLibraryInserts);
				}
				envbuf_setenv(&envc, "DYLD_INSERT_LIBRARIES", newLibraryInsert);
			}

			envbuf_setenv(&envc, "JB_SANDBOX_EXTENSIONS", JB_SandboxExtensions);
			envbuf_setenv(&envc, "JB_ROOT_PATH", JB_RootPath);
		}
		else {
			if (systemHookAlreadyInserted && existingLibraryInserts) {
				if (!strcmp(existingLibraryInserts, HOOK_DYLIB_PATH)) {
					envbuf_unsetenv(&envc, "DYLD_INSERT_LIBRARIES");
				}
				else {
					char *newLibraryInsert = malloc(strlen(existingLibraryInserts)+1);
					newLibraryInsert[0] = '\0';

					__block bool first = true;
					enumeratePathString(existingLibraryInserts, ^(const char *existingLibraryInsert, bool *stop) {
						if (strcmp(existingLibraryInsert, HOOK_DYLIB_PATH) != 0) {
							if (first) {
								strcpy(newLibraryInsert, existingLibraryInsert);
								first = false;
							}
							else {
								strcat(newLibraryInsert, ":");
								strcat(newLibraryInsert, existingLibraryInsert);
							}
						}
					});
					envbuf_setenv(&envc, "DYLD_INSERT_LIBRARIES", newLibraryInsert);

					free(newLibraryInsert);
				}
			}
			envbuf_unsetenv(&envc, "_SafeMode");
			envbuf_unsetenv(&envc, "_MSSafeMode");
			envbuf_unsetenv(&envc, "JB_SANDBOX_EXTENSIONS");
			envbuf_unsetenv(&envc, "JB_ROOT_PATH");
		}

		int retval = pspawn_orig(pid, path, file_actions, attrp, argv, envc);
		envbuf_free(envc);
		return retval;
	}
}
