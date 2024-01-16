#include "info.h"
#include "kernel.h"
#include "primitives.h"
#include <sys/utsname.h>
#include <xpc/xpc.h>
#include <sys/types.h>
#include <sys/sysctl.h>

void jbinfo_initialize_dynamic_offsets(xpc_object_t xoffsetDict)
{
	SYSTEM_INFO_DESERIALIZE(xoffsetDict);
}

void jbinfo_initialize_hardcoded_offsets(void)
{
	struct utsname name;
	uname(&name);
	char *xnuVersion = name.release;

	cpu_subtype_t cpuFamily = 0;
	size_t cpuFamilySize = sizeof(cpuFamily);
    sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);

	uint32_t pmapEl2Adjust = ((kconstant(exceptionLevel) == 8) ? 8 : 0);
	uint32_t taskJitboxAdjust = ((cpuFamily == CPUFAMILY_ARM_BLIZZARD_AVALANCHE) ? 0x10 : 0x0);

	// proc
	gSystemInfo.kernelStruct.proc.list_next =  0x0;
	gSystemInfo.kernelStruct.proc.list_prev =  0x8;
	gSystemInfo.kernelStruct.proc.task      = 0x10;
	gSystemInfo.kernelStruct.proc.pptr      = 0x18;
	gSystemInfo.kernelStruct.proc.pid       = 0x68;

	// filedesc
	gSystemInfo.kernelStruct.filedesc.ofiles_start = 0x20;

	// task
	gSystemInfo.kernelStruct.task.map     = 0x28;
	gSystemInfo.kernelStruct.task.threads = 0x60;

	// ipc_space
	gSystemInfo.kernelStruct.ipc_space.table          = 0x20;
	gSystemInfo.kernelStruct.ipc_space.table_uses_smd = false;

	// ipc_entry
	gSystemInfo.kernelStruct.ipc_entry.object      = 0x0;
	gSystemInfo.kernelStruct.ipc_entry.struct_size = 0x18;

	// map
	gSystemInfo.kernelStruct.vm_map.hdr = 0x10;

	// pmap
	gSystemInfo.kernelStruct.pmap.tte        = 0x0;
	gSystemInfo.kernelStruct.pmap.ttep       = 0x8;
	gSystemInfo.kernelStruct.pmap.sw_asid    = 0xBE + pmapEl2Adjust;
	gSystemInfo.kernelStruct.pmap.wx_allowed = 0xC2 + pmapEl2Adjust;
	gSystemInfo.kernelStruct.pmap.type       = 0xC8 + pmapEl2Adjust;

	// vm_map_header
	gSystemInfo.kernelStruct.vm_map_header.links    =  0x0;
	gSystemInfo.kernelStruct.vm_map_header.nentries = 0x20;

	// vm_map_entry
	gSystemInfo.kernelStruct.vm_map_entry.links = 0x0;
	gSystemInfo.kernelStruct.vm_map_entry.flags = 0x48;

	// vm_map_links
	gSystemInfo.kernelStruct.vm_map_links.prev =  0x0;
	gSystemInfo.kernelStruct.vm_map_links.next =  0x8;
	gSystemInfo.kernelStruct.vm_map_links.min  = 0x10;
	gSystemInfo.kernelStruct.vm_map_links.max  = 0x18;

	// ucred
	uint32_t ucred_cr_posix = 0x18;
	gSystemInfo.kernelStruct.ucred.uid    = ucred_cr_posix +  0x0;
	gSystemInfo.kernelStruct.ucred.svuid  = ucred_cr_posix +  0x8;
	gSystemInfo.kernelStruct.ucred.groups = ucred_cr_posix + 0x10;
	gSystemInfo.kernelStruct.ucred.svgid  = ucred_cr_posix + 0x54;
	gSystemInfo.kernelStruct.ucred.label  = 0x78;

	// tt_free_entry
	gSystemInfo.kernelStruct.tt_free_entry.next = 0x0;

	if (strcmp(xnuVersion, "21.0.0") >= 0) { // iOS 15+
		// proc
		gSystemInfo.kernelStruct.proc.svuid   =  0x3C;
		gSystemInfo.kernelStruct.proc.svgid   =  0x40;
		gSystemInfo.kernelStruct.proc.ucred   =  0xD8;
		gSystemInfo.kernelStruct.proc.fd      =  0xE0;
		gSystemInfo.kernelStruct.proc.flag    = 0x1BC;
		gSystemInfo.kernelStruct.proc.textvp  = 0x2A8;
		gSystemInfo.kernelStruct.proc.csflags = 0x300;

		// task
		gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x5B0 + taskJitboxAdjust;

		// ipc_port
		gSystemInfo.kernelStruct.ipc_port.kobject = 0x58;

		// vm_map
		gSystemInfo.kernelStruct.vm_map.flags = 0x11C;

		// trustcache
		gSystemInfo.kernelStruct.trustcache.next        =  0x0;
		gSystemInfo.kernelStruct.trustcache.this        =  0x8;
		gSystemInfo.kernelStruct.trustcache.struct_size = 0x10;

		if (strcmp(xnuVersion, "21.2.0") >= 0) { // iOS 15.2+
			// proc
			gSystemInfo.kernelStruct.proc.ucred   =   0x0; // Moved to proc_ro
			gSystemInfo.kernelStruct.proc.csflags =   0x0; // Moved to proc_ro
			gSystemInfo.kernelStruct.proc.proc_ro =  0x20;
			gSystemInfo.kernelStruct.proc.svuid   =  0x44;
			gSystemInfo.kernelStruct.proc.svgid   =  0x48;
			gSystemInfo.kernelStruct.proc.fd      =  0xD8;
			gSystemInfo.kernelStruct.proc.flag    = 0x264;
			gSystemInfo.kernelStruct.proc.textvp  = 0x358;

			// proc_ro
			gSystemInfo.kernelStruct.proc_ro.exists  = true;
			gSystemInfo.kernelStruct.proc_ro.csflags = 0x1C;
			gSystemInfo.kernelStruct.proc_ro.ucred   = 0x20;

			// task
			gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x580 + taskJitboxAdjust;

			// vm_map
			gSystemInfo.kernelStruct.vm_map.flags = 0x11C;

			if (strcmp(xnuVersion, "21.4.0") >= 0) { // iOS 15.4+
				// proc
				gSystemInfo.kernelStruct.proc.textvp = 0x350;

				// vm_map
				gSystemInfo.kernelStruct.vm_map.flags = 0x94;

				// ipc_port
				gSystemInfo.kernelStruct.ipc_port.kobject = 0x48;

				if (strcmp(xnuVersion, "22.0.0") >= 0) { // iOS 16+
					gSystemInfo.kernelConstant.smdBase = 3;

					// proc
					gSystemInfo.kernelStruct.proc.task   =   0x0; // Removed, task is now at (proc + sizeof(proc))
					gSystemInfo.kernelStruct.proc.pptr   =  0x10;
					gSystemInfo.kernelStruct.proc.svuid  =  0x3C;
					gSystemInfo.kernelStruct.proc.svgid  =  0x40;
					gSystemInfo.kernelStruct.proc.pid    =  0x60;
					gSystemInfo.kernelStruct.proc.fd     =  0xD8;
					gSystemInfo.kernelStruct.proc.flag   = 0x25C;
					gSystemInfo.kernelStruct.proc.textvp = 0x350;

					// trustcache
					gSystemInfo.kernelStruct.trustcache.next = 0x0;
					gSystemInfo.kernelStruct.trustcache.this = 0x20;
					gSystemInfo.kernelStruct.trustcache.struct_size = 0x28;					

					// pmap
					gSystemInfo.kernelStruct.pmap.sw_asid    = 0xB6 + pmapEl2Adjust;
					gSystemInfo.kernelStruct.pmap.wx_allowed = 0xBA + pmapEl2Adjust;
					gSystemInfo.kernelStruct.pmap.type       = 0xC0 + pmapEl2Adjust;

					if (strcmp(xnuVersion, "22.1.0") >= 0) { // iOS 16.1+
						gSystemInfo.kernelStruct.ipc_space.table_uses_smd = true;
						if (strcmp(xnuVersion, "22.3.0") >= 0) { // iOS 16.3+
							gSystemInfo.kernelConstant.smdBase = 2;
							if (strcmp(xnuVersion, "22.4.0") >= 0) { // iOS 16.4+
								// proc
								gSystemInfo.kernelStruct.proc.flag   = 0x454;
								gSystemInfo.kernelStruct.proc.textvp = 0x548;
							}
						}
					}
				}
			}
		}
	}
}

void jbinfo_initialize_boot_constants(void)
{
	gSystemInfo.kernelConstant.base     = kconstant(staticBase) + gSystemInfo.kernelConstant.slide;
	gSystemInfo.kernelConstant.virtBase = kread64(ksymbol(gVirtBase));
	//gSystemInfo.kernelConstant.virtSize = ...;
	gSystemInfo.kernelConstant.physBase = kread64(ksymbol(gPhysBase));
	gSystemInfo.kernelConstant.physSize = kread64(ksymbol(gPhysSize));
	gSystemInfo.kernelConstant.cpuTTEP  = kread64(ksymbol(cpu_ttep));
}

xpc_object_t jbinfo_get_serialized(void)
{
	xpc_object_t systemInfo = xpc_dictionary_create_empty();
	SYSTEM_INFO_SERIALIZE(systemInfo);
	return systemInfo;
}