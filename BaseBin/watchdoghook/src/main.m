#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <xpc/xpc.h>
#include <IOKit/IOKitLib.h>

#include "substrate.h"

int64_t (*jbdswInterceptUserspacePanic)(const char *messageString) = NULL;
kern_return_t (*IOConnectCallStructMethod_orig)(mach_port_t connection, uint32_t selector, const void *inputStruct, size_t inputStructCnt, void *outputStruct, size_t *outputStructCnt) = NULL;
kern_return_t (*IOServiceOpen_orig)(io_service_t service, task_port_t owningTask, uint32_t type, io_connect_t *connect);
mach_port_t gIOWatchdogConnection = MACH_PORT_NULL;

kern_return_t IOServiceOpen_hook(io_service_t service, task_port_t owningTask, uint32_t type, io_connect_t *connect)
{
	kern_return_t orig = IOServiceOpen_orig(service, owningTask, type, connect);
	if (orig == KERN_SUCCESS && connect) {
		if (IOObjectConformsTo(service, "IOWatchdog")) {
			// save mach port of IOWatchdog for check later
			gIOWatchdogConnection = *connect;
		}
	}
	return orig;
}

kern_return_t IOConnectCallStructMethod_hook(mach_port_t connection, uint32_t selector, const void *inputStruct, size_t inputStructCnt, void *outputStruct, size_t *outputStructCnt)
{
	if (connection == gIOWatchdogConnection) {
		if (selector == 2) {
			return jbdswInterceptUserspacePanic((const char *)inputStruct);
		}
	}
	return IOConnectCallStructMethod_orig(connection, selector, inputStruct, inputStructCnt, outputStruct, outputStructCnt);
}

__attribute__((constructor)) static void initializer(void)
{
	jbdswInterceptUserspacePanic = dlsym(RTLD_DEFAULT, "jbdswInterceptUserspacePanic");
	MSHookFunction(IOServiceOpen, (void *)&IOServiceOpen_hook, (void **)&IOServiceOpen_orig);
	MSHookFunction(IOConnectCallStructMethod, (void *)&IOConnectCallStructMethod_hook, (void **)&IOConnectCallStructMethod_orig);
}