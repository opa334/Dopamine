#include <Foundation/Foundation.h>
#include <kern_memorystatus.h>
#include <mach-o/dyld.h>
#include <libproc.h>
#include <spawn.h>

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/roothider.h>

extern char **environ;

void jailbreakd_received_message(mach_port_t port);

int posix_spawnattr_setspecialport_np(posix_spawnattr_t *attr, mach_port_t new_port, int which);
int posix_spawnattr_set_registered_ports_np(posix_spawnattr_t * __restrict attr, mach_port_t portarray[], uint32_t count);

void setJetsamLimit(uint32_t sizeInMB, bool is_fatal_limit)
{
	uint32_t cmd = is_fatal_limit ? MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT : MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK;
	int rc = memorystatus_control(cmd, getpid(), sizeInMB, NULL, 0);
	if (rc < 0) { perror ("memorystatus_control"); exit(rc);}
}

void enableXPCLog(void* debugLog, void* errorLog);

int main(int argc, char* argv[])
{
	crashreporter_start();

	setJetsamLimit(50, false);

#ifdef ENABLE_LOGS
	enableXPCLog(JBLogDebugFunction, JBLogErrorFunction);
	enableJBDLog(JBLogDebugFunction, JBLogErrorFunction);
#endif

	JBLogDebug("Hello from jailbrakd! uid=%d pid=%d ppid=%d", getuid(), getpid(), getppid());

	@autoreleasepool {

		mach_port_t *registeredPorts=NULL;
		mach_msg_type_number_t registeredPortsCount = 0;
		kern_return_t kr = mach_ports_lookup(mach_task_self(), &registeredPorts, &registeredPortsCount);
		if(kr != KERN_SUCCESS || registeredPortsCount < 3) {
			JBLogError("mach_ports_lookup error: %d, %x, %s", registeredPortsCount, kr, mach_error_string(kr));
			return 1;
		}
		for(int i=0; i<registeredPortsCount; i++) {
			JBLogDebug("registeredPorts[%d]: %x", i, registeredPorts[i]);
		}

		mach_port_t bootstraport = registeredPorts[2];
		if(!MACH_PORT_VALID(bootstraport)) {
			JBLogError("invalid bootstraport");
			return 2;
		}
		JBLogDebug("bootstraport: %x", bootstraport);

		registeredPorts[2] = MACH_PORT_NULL;
		mach_ports_register(mach_task_self(), registeredPorts, registeredPortsCount);

		JBLogDebug("start initializing jb primitives");
		jbclient_xpc_set_custom_port(bootstraport);
		int ret = jbclient_initialize_primitives();
		JBLogDebug("jbclient_initialize_primitives ret: %d", ret);
		if(ret != 0) {
			JBLogError("Failed to initialize jailbreak primitives: %d", ret);
			return 3;
		}

		if(getenv("RESPAWN_REQUIRED"))
		{
			unsetenv("RESPAWN_REQUIRED");

			char selfPath[PATH_MAX]={0};
			uint32_t selfPathSize = sizeof(selfPath);
			_NSGetExecutablePath(selfPath, &selfPathSize);
	
			pid_t pid;
			posix_spawnattr_t attr = NULL;
			posix_spawnattr_init(&attr);
			posix_spawnattr_setflags(&attr, POSIX_SPAWN_START_SUSPENDED);
			// posix_spawnattr_setspecialport_np(&attr, bootstraport, TASK_BOOTSTRAP_PORT);
			// posix_spawnattr_set_registered_ports_np(&attr, (mach_port_t[]){ bootstraport, MACH_PORT_NULL }, 3);
			posix_spawnattr_set_registered_ports_np(&attr, (mach_port_t[]){ MACH_PORT_NULL, MACH_PORT_NULL, bootstraport }, 3);
			int ret = posix_spawn(&pid, selfPath, NULL, &attr, argv, environ);
			posix_spawnattr_destroy(&attr);

			if(ret != 0) {
				JBLogError("posix_spawn jailbreakd failed: %d, %s", ret, strerror(ret));
				return 4;
			}

			JBLogDebug("jailbreakd respawned: %d", pid);
	
			if(unrestrict(pid, proc_patch_dyld, false) != 0) {
				JBLogError("Failed to unrestrict process %d", pid);
				return 5;
			}

			if(dyld_patch_enabled()) {
				kill(pid, SIGCONT);
				return 0;
			} else {
				kill(pid, SIGKILL);
				waitpid(pid, NULL, 0);
			}
		}

		JBLogDebug("check in jailbreakd port...");
		mach_port_t serverPort = jbclient_jailbreakd_checkin();
		if (!MACH_PORT_VALID(serverPort)) {
			JBLogError("Failed to check in server port");
			return 6;
		}

		JBLogDebug("starting jailbreakd server, port=%x", serverPort);

		dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, (uintptr_t)serverPort, 0, dispatch_get_main_queue());
		dispatch_source_set_event_handler(source, ^{
			jailbreakd_received_message(serverPort);
		});
		dispatch_resume(source);

		dispatch_main();
	}

	JBLogDebug("jailbreakd exit...");
	return 0;
}
