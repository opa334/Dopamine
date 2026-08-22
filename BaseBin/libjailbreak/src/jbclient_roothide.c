#include <dlfcn.h>
#include <mach-o/dyld.h>
#include "jbclient_xpc.h"
#include "jbserver.h"

#include "roothider/log.h"
#include "roothider/xpc_private.h"

#ifdef ENABLE_LOGS
void (*XPCLogDebugFunction)(const char *format, ...);
void (*XPCLogErrorFunction)(const char *format, ...);

#define JBLogDebug(...) do { if(XPCLogDebugFunction)XPCLogDebugFunction(__VA_ARGS__); } while(0)
#define JBLogError(...) do { if(XPCLogErrorFunction)XPCLogErrorFunction(__VA_ARGS__); } while(0)

void enableXPCLog(void* debugLog, void* errorLog)
{
	XPCLogDebugFunction = debugLog;
	XPCLogErrorFunction = errorLog;
}
#endif

mach_port_t jbclient_jailbreakd_lookup()
{
	mach_port_t port = MACH_PORT_NULL;
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_JAILBREAKD_LOOKUP, NULL);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		if(result == 0) {
			xpc_object_t portobj = xpc_dictionary_get_value(xreply, "port");
			if (portobj) {
				port = xpc_mach_send_copy_right(portobj);
			}
		}
		xpc_release(xreply);
	}
	return port;
}

mach_port_t jbclient_jailbreakd_checkin()
{
	mach_port_t port = MACH_PORT_NULL;
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_JAILBREAKD_CHECKIN, NULL);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		if(result == 0) {
			xpc_object_t portobj = xpc_dictionary_get_value(xreply, "port");
			if (portobj) {
				port = xpc_mach_recv_extract_right(portobj);
			}
		}
		xpc_release(xreply);
	}
	return port;
}

bool jbclient_roothide_jailbroken()
{
	bool jailbroken = false;

    xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_JAILBROKEN_CHECK, xargs);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		if(result == 0) {
			jailbroken = xpc_dictionary_get_bool(xreply, "jailbroken");
		}
		xpc_release(xreply);
	}

	return jailbroken;
}

bool jbclient_palehide_present()
{
	bool palehide = false;

    xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_PALEHIDE_PRESENT, xargs);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		if(result == 0) {
			palehide = xpc_dictionary_get_bool(xreply, "palehide");
		}
		xpc_release(xreply);
	}

	return palehide;
}

bool jbclient_blacklist_check_pid(pid_t pid)
{
	bool blacklisted = false;

    xpc_object_t xargs = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(xargs, "checktype", "pid");
    xpc_dictionary_set_uint64(xargs, "checkvalue", pid);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_BLACKLIST_CHECK, xargs);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		if(result == 0) {
			blacklisted = xpc_dictionary_get_bool(xreply, "blacklisted");
		}
		xpc_release(xreply);
	}

	return blacklisted;
}

bool jbclient_blacklist_check_path(const char* path)
{
	bool blacklisted = false;

    xpc_object_t xargs = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(xargs, "checktype", "path");
    xpc_dictionary_set_string(xargs, "checkvalue", path);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_BLACKLIST_CHECK, xargs);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		if(result == 0) {
			blacklisted = xpc_dictionary_get_bool(xreply, "blacklisted");
		}
		xpc_release(xreply);
	}

	return blacklisted;
}

bool jbclient_blacklist_check_bundle(const char* bundle)
{
	bool blacklisted = false;

    xpc_object_t xargs = xpc_dictionary_create_empty();
    xpc_dictionary_set_string(xargs, "checktype", "bundle");
    xpc_dictionary_set_string(xargs, "checkvalue", bundle);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_BLACKLIST_CHECK, xargs);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		if(result == 0) {
			blacklisted = xpc_dictionary_get_bool(xreply, "blacklisted");
		}
		xpc_release(xreply);
	}

	return blacklisted;
}

int jbclient_trust_executable_recurse(const char *executablePath, xpc_object_t preferredArchsArray)
{
	if (!executablePath) return -1;

	if(access(executablePath, F_OK) != 0) {
		return -2;
	}

	xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_string(xargs, "executable-path", executablePath);

	char* cwd = getcwd(NULL, 0);
	if(cwd) {
		xpc_dictionary_set_string(xargs, "process-working-dir", cwd);
		free((void*)cwd);
	}

	if (preferredArchsArray) {
		xpc_dictionary_set_value(xargs, "preferred-archs", preferredArchsArray);
	}

	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_TRUST_EXECUTABLE_RECURSE, xargs);
	xpc_release(xargs);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

extern const char* dyld_image_path_containing_address(const void* addr);

int jbclient_trust_library_recurse(const char *libraryPath, void *addressInCaller)
{
	if (!libraryPath) return -1;

	if (_dyld_shared_cache_contains_path(libraryPath)) {
		return -1;
	}
	
	if(libraryPath[0] != '@') {
		if(access(libraryPath, F_OK) != 0) {
			return -3;
		}
	}

	/* the executable file may be removed from disk at runtime,
		 			so we need to use the cached path from dyld */
	char executablePath[PATH_MAX] = {0};
	uint32_t bufsize = sizeof(executablePath);
	//According to dyld this returns real-path on ios (but not on macos)
	if(_NSGetExecutablePath(executablePath, &bufsize) != 0) {
		return -2;
	}
	
	xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_string(xargs, "library-path", libraryPath);
	xpc_dictionary_set_string(xargs, "caller-executable-path", executablePath);

	if(addressInCaller) {
		const char* callerPath = dyld_image_path_containing_address(addressInCaller);
		if (callerPath) {
			xpc_dictionary_set_string(xargs, "caller-library-path", callerPath);
		}
	}

	char* cwd = getcwd(NULL, 0);
	if(cwd) {
		xpc_dictionary_set_string(xargs, "current-working-dir", cwd);
		free((void*)cwd);
	}


	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_TRUST_LIBRARY_RECURSE, xargs);
	xpc_release(xargs);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}

bool jbclient_dyld_patch_enabled()
{
	static bool enabled = false;

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		xpc_object_t xargs = xpc_dictionary_create_empty();
		xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_DYLD_PATCH_ENABLED_GET, xargs);
		if (xreply) {
			int64_t result = xpc_dictionary_get_int64(xreply, "result");
			if(result == 0) {
				enabled = xpc_dictionary_get_bool(xreply, "enabled");
			}
			xpc_release(xreply);
		}
	});

	return enabled;
}

int jbclient_set_dyld_patch(bool enabled)
{
    xpc_object_t xargs = xpc_dictionary_create_empty();
	xpc_dictionary_set_bool(xargs, "enabled", enabled);
	xpc_object_t xreply = jbserver_xpc_send(JBS_DOMAIN_ROOTHIDE, JBS_ROOTHIDE_DYLD_PATCH_ENABLED_SET, xargs);
	if (xreply) {
		int64_t result = xpc_dictionary_get_int64(xreply, "result");
		xpc_release(xreply);
		return result;
	}
	return -1;
}
