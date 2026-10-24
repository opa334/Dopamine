#include "info.h"
#include "kernel.h"
#include "machine_info.h"
#include "primitives.h"
#include "util.h"
#include <sys/utsname.h>
#include <xpc/xpc.h>
#include <sys/types.h>
#include <sys/sysctl.h>

struct system_info gSystemInfo = { 0 };

void jbinfo_initialize_dynamic_offsets(xpc_object_t xoffsetDict)
{
	SYSTEM_INFO_DESERIALIZE(xoffsetDict);
}

struct xnu_version {
	uint64_t major;
	uint64_t minor;
	uint64_t patch;
};

int xnu_version_compare(struct xnu_version v1, struct xnu_version v2)
{
	if (v1.major > v2.major) return 1;
	if (v1.major < v2.major) return -1;
	if (v1.minor > v2.minor) return 1;
	if (v1.minor < v2.minor) return -1;
	if (v1.patch > v2.patch) return 1;
	if (v1.patch < v2.patch) return -1;
	return 0;
}

void jbinfo_initialize_hardcoded_offsets(void)
{
	struct utsname name;
	uname(&name);
	char *darwinVersion = name.release;

	struct xnu_version xnuVersion = { 0 };
	if (sscanf(strstr(name.version, "xnu-"), "xnu-%llu.%llu.%llu~%*s", &xnuVersion.major, &xnuVersion.minor, &xnuVersion.patch) != 3) {
		sscanf(strstr(name.version, "xnu-"), "xnu-%llu.%llu.%*s", &xnuVersion.major, &xnuVersion.minor);
	}

	bool isArm64e = host_is_arm64e();

	cpu_subtype_t cpuFamily = 0;
	size_t cpuFamilySize = sizeof(cpuFamily);
	sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);

	bool hasJitbox = (cpuFamily == CPUFAMILY_ARM_BLIZZARD_AVALANCHE || 	// A15 / M2
					  cpuFamily == CPUFAMILY_ARM_EVEREST_SAWTOOTH || 	// A16
					  cpuFamily == CPUFAMILY_ARM_COLL || 				// A17
					  cpuFamily == CPUFAMILY_ARM_TUPAI ||   			// A18
					  cpuFamily == CPUFAMILY_ARM_TAHITI ||  			// A18 Pro
					  cpuFamily == CPUFAMILY_ARM_IBIZA ||   			// M3
					  cpuFamily == CPUFAMILY_ARM_DONAN);				// M4

	bool hasSPTM = ksymbol(SPTMArgs) != 0;

	uint32_t taskJitboxAdjust = 0x0;
	if (hasJitbox) {
		taskJitboxAdjust = 0x10;
		if (strcmp(darwinVersion, "22.0.0") >= 0) {
			// In iOS 16+, there is a new jitbox related attribute
			taskJitboxAdjust = 0x18;
			if (strcmp(darwinVersion, "24.4.0") >= 0) {
				// In iOS 18.4+, there is yet another new jitbox related attribute
				taskJitboxAdjust = 0x20;
			}
		}
	}

	uint32_t pmapEl2Adjust = ((kconstant(kernel_el) == 2) ? 8 : 0);

	uint32_t pmapA11Adjust = 0;
	if (cpuFamily == CPUFAMILY_ARM_MONSOON_MISTRAL) {
		if (strcmp(darwinVersion, "21.0.0") >= 0) { // iOS 15+
			pmapA11Adjust = 1;
			if (strcmp(darwinVersion, "22.0.0") >= 0) { // iOS 16+
				pmapA11Adjust = 2;
			}
		}
	}

	int pmapA13A14TXMiOS27Adjust = 0;
	if (cpuFamily == CPUFAMILY_ARM_LIGHTNING_THUNDER || /* A13 */
		cpuFamily == CPUFAMILY_ARM_FIRESTORM_ICESTORM)  /* A14 */ {
		if (strcmp(darwinVersion, "27.0.0") >= 0) {
			pmapA13A14TXMiOS27Adjust = -8;
		}
	}

	gSystemInfo.kernelConstant.PVH_TYPE_MASK  = 0x3;
	gSystemInfo.kernelConstant.PVH_HIGH_FLAGS = 0x7F40000000000000;

	gSystemInfo.kernelConstant.VM_PAGE_PACKED_PTR_SHIFT = 6;
	gSystemInfo.kernelConstant.VM_PAGE_PACKED_PTR_BASE  = 0xFFFFFFE000000000;

	gSystemInfo.kernelConstant.TFRO_PLATFORM            = 0x400;
	gSystemInfo.kernelConstant.TFRO_HARDENED            = 0x0;

	gSystemInfo.kernelStruct.IOSurface.memoryDescriptor = 0x38;
	gSystemInfo.kernelStruct.IOMachPort.object = 0;

	// proc
	gSystemInfo.kernelStruct.proc.list_next =  0x0;
	gSystemInfo.kernelStruct.proc.list_prev =  0x8;
	gSystemInfo.kernelStruct.proc.task      = 0x10;
	gSystemInfo.kernelStruct.proc.pptr      = 0x18;
	gSystemInfo.kernelStruct.proc.pid       = 0x68;

	// filedesc
	gSystemInfo.kernelStruct.filedesc.ofiles_start = 0x20;

	// fileproc
	gSystemInfo.kernelStruct.fileproc.glob = 0x10;

	// fileglob
	gSystemInfo.kernelStruct.fileglob.data = 0x38;

	// vnode
	gSystemInfo.kernelStruct.vnode.un = 0x78;

	// ubc_info
	gSystemInfo.kernelStruct.ubc_info.cs_blobs = 0x50;

	// cs_blob
	gSystemInfo.kernelStruct.cs_blob.next        = 0x0;
	gSystemInfo.kernelStruct.cs_blob.cpu_type    = 0x8;
	gSystemInfo.kernelStruct.cs_blob.cpu_subtype = 0xc;
	gSystemInfo.kernelStruct.cs_blob.base_offset = 0x18;

	// task
	gSystemInfo.kernelStruct.task.map     = 0x28;
	gSystemInfo.kernelStruct.task.threads = 0x60;

	// ipc_space
	gSystemInfo.kernelStruct.ipc_space.table          = 0x20;
	gSystemInfo.kernelStruct.ipc_space.table_uses_smr = false;

	// ipc_entry
	gSystemInfo.kernelStruct.ipc_entry.object      = 0x0;
	gSystemInfo.kernelStruct.ipc_entry.struct_size = 0x18;

	// vm_map
	gSystemInfo.kernelStruct.vm_map.hdr = 0x10;

	// pmap
	gSystemInfo.kernelStruct.pmap.tte        = 0x0;
	gSystemInfo.kernelStruct.pmap.ttep       = 0x8;
	if (isArm64e) {
		gSystemInfo.kernelStruct.pmap.pmap_cs_main = 0x90;
		gSystemInfo.kernelStruct.pmap.sw_asid      = 0xBE + pmapEl2Adjust;
		gSystemInfo.kernelStruct.pmap.wx_allowed   = 0xC2 + pmapEl2Adjust;
		gSystemInfo.kernelStruct.pmap.type         = 0xC8 + pmapEl2Adjust;
	}
	else {
		gSystemInfo.kernelStruct.pmap.sw_asid    = 0x96;
		gSystemInfo.kernelStruct.pmap.wx_allowed = 0;
		gSystemInfo.kernelStruct.pmap.type       = 0x9c + pmapA11Adjust;
	}

	if (isArm64e) {
		// pmap_cs_region
		gSystemInfo.kernelStruct.pmap_cs_region.pmap_cs_region_next = 0x0;
		gSystemInfo.kernelStruct.pmap_cs_region.cd_entry            = 0x28;

		// pmap_cs_code_directory
		gSystemInfo.kernelStruct.pmap_cs_code_directory.pmap_cs_code_directory_next = 0x0;
		gSystemInfo.kernelStruct.pmap_cs_code_directory.main_binary                 = 0x50;
		gSystemInfo.kernelStruct.pmap_cs_code_directory.trust                       = 0x9C;
	}

	// pt_desc
	gSystemInfo.kernelStruct.pt_desc.pmap     = 0x10;
	gSystemInfo.kernelStruct.pt_desc.va       = 0x18;
	gSystemInfo.kernelStruct.pt_desc.ptd_info = koffsetof(pt_desc, va) + (kconstant(PT_INDEX_MAX) * sizeof(uint64_t));

	// vm_map_header
	gSystemInfo.kernelStruct.vm_map_header.last       = 0x0;
	gSystemInfo.kernelStruct.vm_map_header.first      = 0x8;
	gSystemInfo.kernelStruct.vm_map_header.min_offset = 0x10;
	gSystemInfo.kernelStruct.vm_map_header.max_offset = 0x18;
	gSystemInfo.kernelStruct.vm_map_header.nentries   = 0x20;

	// vm_map_entry
	gSystemInfo.kernelStruct.vm_map_entry.prev          = 0x0;
	gSystemInfo.kernelStruct.vm_map_entry.next          = 0x8;
	gSystemInfo.kernelStruct.vm_map_entry.start         = 0x10;
	gSystemInfo.kernelStruct.vm_map_entry.end           = 0x18;
	gSystemInfo.kernelStruct.vm_map_entry.flags         = 0x48;
	gSystemInfo.kernelStruct.vm_map_entry.flags_prot    = 7;
	gSystemInfo.kernelStruct.vm_map_entry.flags_maxprot = 11;

	// ucred
	gSystemInfo.kernelStruct.ucred.rw     = 0x0;
	gSystemInfo.kernelStruct.ucred.ref    = 0x10;
	uint32_t ucred_cr_posix = 0x18;
	gSystemInfo.kernelStruct.ucred.uid    = ucred_cr_posix +  0x0;
	gSystemInfo.kernelStruct.ucred.ruid   = ucred_cr_posix +  0x4;
	gSystemInfo.kernelStruct.ucred.svuid  = ucred_cr_posix +  0x8;
	gSystemInfo.kernelStruct.ucred.groups = ucred_cr_posix + 0x10;
	gSystemInfo.kernelStruct.ucred.rgid   = ucred_cr_posix + 0x50;
	gSystemInfo.kernelStruct.ucred.svgid  = ucred_cr_posix + 0x54;
	gSystemInfo.kernelStruct.ucred.label  = 0x78;

	// RBLink
	gSystemInfo.kernelStruct.RBLink.rbe_left   = 0x0;
	gSystemInfo.kernelStruct.RBLink.rbe_right  = 0x8;
	gSystemInfo.kernelStruct.RBLink.rbe_parent = 0x10;

	if (strcmp(darwinVersion, "21.0.0") >= 0) { // iOS 15+
		// proc
		gSystemInfo.kernelStruct.proc.svuid   =  0x3C;
		gSystemInfo.kernelStruct.proc.svgid   =  0x40;
		gSystemInfo.kernelStruct.proc.ucred   =  0xD8;
		gSystemInfo.kernelStruct.proc.fd      =  0xE0;
		gSystemInfo.kernelStruct.proc.flag    = 0x1BC;
		gSystemInfo.kernelStruct.proc.textvp  = 0x2A8;
		gSystemInfo.kernelStruct.proc.csflags = 0x300;

		// task
		if (isArm64e) {
			gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x5B0 + taskJitboxAdjust;
		}
		else {
			gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x590;
		}

		// ipc_port
		gSystemInfo.kernelStruct.ipc_port.kobject = 0x58;

		// vm_map
		gSystemInfo.kernelStruct.vm_map.flags = 0x11C;

		// trustcache
		gSystemInfo.kernelStruct.trustcache.nextptr        =  0x0;
		gSystemInfo.kernelStruct.trustcache.fileptr        =  0x8;
		gSystemInfo.kernelStruct.trustcache.struct_size    = 0x10;

		// inpcb
		gSystemInfo.kernelStruct.inpcb.list_next = 0x20;
		gSystemInfo.kernelStruct.inpcb.list_prev = 0x28;
		gSystemInfo.kernelStruct.inpcb.pcbinfo	 = 0x38;
		gSystemInfo.kernelStruct.inpcb.socket    = 0x40;
		gSystemInfo.kernelStruct.inpcb.icmp6filt = (0x138 + 0x18);
		gSystemInfo.kernelStruct.inpcb.chksum 	 = 0x158;

		// inpcbinfo
		gSystemInfo.kernelStruct.inpcbinfo.ipi_zone = 0x68;

		// kalloc_type_view
		gSystemInfo.kernelStruct.kalloc_type_view.kt_zv_zv_name = 0x10;

		// socket
		gSystemInfo.kernelStruct.socket.proto    = 0x18;
		gSystemInfo.kernelStruct.socket.usecount = 0x228;

		// proto
		gSystemInfo.kernelStruct.protosw.input = 0x28;

		if (strcmp(darwinVersion, "21.2.0") >= 0) { // iOS 15.2+
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
			gSystemInfo.kernelStruct.proc_ro.exists      = true;
			gSystemInfo.kernelStruct.proc_ro.csflags     = 0x1C;
			gSystemInfo.kernelStruct.proc_ro.ucred       = 0x20;
			gSystemInfo.kernelStruct.proc_ro.task_tokens = 0x40;

			// cs_blob
			gSystemInfo.kernelStruct.cs_blob.cpu_type    = 0x18;
			gSystemInfo.kernelStruct.cs_blob.cpu_subtype = 0x1c;
			gSystemInfo.kernelStruct.cs_blob.base_offset = 0x28;

			// task_token_ro_data
			gSystemInfo.kernelStruct.task_token_ro_data.audit_token = 0x8;

			// ucred_rw
			gSystemInfo.kernelStruct.ucred_rw.exists = true;
			gSystemInfo.kernelStruct.ucred_rw.weak_ref = 0x18;

			// task
			if (isArm64e) {
				gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x580 + taskJitboxAdjust;
			}
			else {
				gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x560;
			}

			if (strcmp(darwinVersion, "21.4.0") >= 0) { // iOS 15.4+
				// proc
				gSystemInfo.kernelStruct.proc.textvp = 0x350;

				// vm_map
				gSystemInfo.kernelStruct.vm_map.flags = 0x94;

				// ipc_port
				gSystemInfo.kernelStruct.ipc_port.kobject = 0x48;

				if (strcmp(darwinVersion, "22.0.0") >= 0) { // iOS 16+
					gSystemInfo.kernelConstant.smrBase = 3;

					// proc
					gSystemInfo.kernelStruct.proc.task    =   0x0; // Removed, task is now at (proc + sizeof(proc))
					gSystemInfo.kernelStruct.proc.pptr    =  0x10;
					gSystemInfo.kernelStruct.proc.proc_ro =  0x18;
					gSystemInfo.kernelStruct.proc.svuid   =  0x3C;
					gSystemInfo.kernelStruct.proc.svgid   =  0x40;
					gSystemInfo.kernelStruct.proc.pid     =  0x60;
					gSystemInfo.kernelStruct.proc.fd      =  0xD0;
					gSystemInfo.kernelStruct.proc.flag    = 0x25C;
					gSystemInfo.kernelStruct.proc.textvp  = 0x350;

					// proc_ro
					gSystemInfo.kernelStruct.proc_ro.syscall_filter_mask = 0x28;
					gSystemInfo.kernelStruct.proc_ro.mach_trap_filter_mask = 0x68;
					gSystemInfo.kernelStruct.proc_ro.mach_kobj_filter_mask = 0x70;

					// filedesc
					gSystemInfo.kernelStruct.filedesc.ofiles_start = 0x28;

					// socket
					gSystemInfo.kernelStruct.socket.usecount = 0x22c;

					// task
					if (isArm64e) {
						gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x548 + taskJitboxAdjust;
						gSystemInfo.kernelStruct.task.flags = 0x3b8 + taskJitboxAdjust;
					} else {
						gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x528;
						gSystemInfo.kernelStruct.task.flags = 0x3a0;
					}
					// vm_map
					gSystemInfo.kernelStruct.vm_map.flags = 0xB4;

					// vm_map_entry
					gSystemInfo.kernelStruct.vm_map_entry.flags_xnu_user_debug = 28;

					// ucred_rw
					gSystemInfo.kernelStruct.ucred_rw.weak_ref = 0x0;

					// trustcache
					gSystemInfo.kernelStruct.trustcache.nextptr = 0x0;
					gSystemInfo.kernelStruct.trustcache.prevptr = 0x8;
					gSystemInfo.kernelStruct.trustcache.type    = 0x10;
					gSystemInfo.kernelStruct.trustcache.size    = 0x18;
					gSystemInfo.kernelStruct.trustcache.fileptr = 0x20;
					gSystemInfo.kernelStruct.trustcache.struct_size = 0x28;

					// pmap
					if (isArm64e) {
						gSystemInfo.kernelStruct.pmap.sw_asid    = 0xB6 + pmapEl2Adjust;
						gSystemInfo.kernelStruct.pmap.wx_allowed = 0xBA + pmapEl2Adjust;
						gSystemInfo.kernelStruct.pmap.type       = 0xC0 + pmapEl2Adjust;
					} else {
						gSystemInfo.kernelStruct.pmap.sw_asid    = 0x8e;
						gSystemInfo.kernelStruct.pmap.wx_allowed = 0;
						gSystemInfo.kernelStruct.pmap.type       = 0x94 + pmapA11Adjust;
					}

					if (isArm64e) {
						// pmap_cs_code_directory
						gSystemInfo.kernelStruct.pmap_cs_code_directory.main_binary = 0x190;
						gSystemInfo.kernelStruct.pmap_cs_code_directory.trust       = 0x1DC;
					}

					if (strcmp(darwinVersion, "22.1.0") >= 0 && xnu_version_compare(xnuVersion, (struct xnu_version){.major = 8792, .minor = 42, .patch = 0}) >= 0) { // iOS 16.1+
						gSystemInfo.kernelStruct.ipc_space.table_uses_smr = true;

						// proc_ro
						gSystemInfo.kernelStruct.proc_ro.t_flags_ro = 0x78;

						if (strcmp(darwinVersion, "22.3.0") >= 0) { // iOS 16.3+
							gSystemInfo.kernelConstant.smrBase = 2;
							gSystemInfo.kernelConstant.VM_PAGE_PACKED_PTR_BASE = 0xFFFFFFDC00000000ULL;

							if (strcmp(darwinVersion, "22.4.0") >= 0) { // iOS 16.4+
								// proc
								gSystemInfo.kernelStruct.proc.flag   = 0x454;
								gSystemInfo.kernelStruct.proc.textvp = 0x548;

								if (isArm64e) {
									// pmap_cs_code_directory
									gSystemInfo.kernelStruct.pmap_cs_code_directory.trust = 0x1EC;
								}

								if (strcmp(darwinVersion, "22.4.0") == 0) { // iOS 16.4 ONLY 
									// iOS 16.4 beta 1-3 use the old proc struct, 16.4b4+ use new
									if (gSystemInfo.kernelStruct.proc.struct_size != 0x730) {
										gSystemInfo.kernelStruct.proc.flag    = 0x25C;
										gSystemInfo.kernelStruct.proc.textvp  = 0x350;
									}
								}

								// iOS 17+
								if (strcmp(darwinVersion, "23.0.0") >= 0) {
									if (hasSPTM) {
										gSystemInfo.kernelConstant.PVH_HIGH_FLAGS = 0x7400000000000000LL;

										gSystemInfo.kernelStruct.sptm_frame.type           = 0x2;
										gSystemInfo.kernelStruct.sptm_frame.level          = 0x4;
										gSystemInfo.kernelStruct.sptm_frame.nested_refcnt  = 0x6;
										gSystemInfo.kernelStruct.sptm_frame.mapping_refcnt = 0x8;

										gSystemInfo.kernelStruct.pt_desc.pmap = 0x0;
										gSystemInfo.kernelStruct.pt_desc.va   = 0x8;

										gSystemInfo.kernelStruct.TXMAddressSpace.allowsInvalidCode = 0x20;
										gSystemInfo.kernelStruct.TXMAddressSpace.codeRegions       = 0x30;

										gSystemInfo.kernelStruct.TXMCodeRegion.active        = 0x11;
										gSystemInfo.kernelStruct.TXMCodeRegion.type          = 0x12;
										gSystemInfo.kernelStruct.TXMCodeRegion.nestedSpace   = 0x18;
										gSystemInfo.kernelStruct.TXMCodeRegion.codeSignature = 0x20;
										gSystemInfo.kernelStruct.TXMCodeRegion.startAddr     = 0x28;
										gSystemInfo.kernelStruct.TXMCodeRegion.endAddr       = 0x30;
										gSystemInfo.kernelStruct.TXMCodeRegion.RBLink        = 0x38;

										gSystemInfo.kernelStruct.pmap.sw_asid           = 0;
										gSystemInfo.kernelStruct.pmap.txm_address_space = 0xB0;
										gSystemInfo.kernelStruct.pmap.asid              = 0x90;
										gSystemInfo.kernelStruct.pmap.type              = 0x9C;
									}
									else {
										// pmap
										gSystemInfo.kernelStruct.pmap.sw_asid    = 0xBE + pmapEl2Adjust;
										gSystemInfo.kernelStruct.pmap.wx_allowed = 0xC2 + pmapEl2Adjust;
										gSystemInfo.kernelStruct.pmap.type       = 0xC9 + pmapEl2Adjust;
									}

									// IOSurface
									gSystemInfo.kernelStruct.IOSurface.memoryDescriptor = 0x40;

									// IOMachPort
									gSystemInfo.kernelStruct.IOMachPort.object = 0x30;

									// vm_map
									gSystemInfo.kernelStruct.vm_map.flags = 0xC8;

									// ucred_rw
									gSystemInfo.kernelStruct.ucred_rw.weak_ref = 0x0;

									if (strcmp(darwinVersion, "23.1.0") >= 0) {	// iOS 17.1+
										// inpcb
										gSystemInfo.kernelStruct.inpcb.icmp6filt = 0x148;
										gSystemInfo.kernelStruct.inpcb.chksum 	 = 0x150;
										
										// socket
										gSystemInfo.kernelStruct.socket.usecount = 0x24c;

										if (strcmp(darwinVersion, "23.4.0") >= 0) { // iOS 17.4+
											gSystemInfo.kernelConstant.TFRO_HARDENED = 0x100;

											// IOSurface
											gSystemInfo.kernelStruct.IOSurface.memoryDescriptor = 0x30;
											
											// socket
											gSystemInfo.kernelStruct.socket.proto    = 0x20;
											gSystemInfo.kernelStruct.socket.usecount = 0x254;
											if (hasSPTM) {
												gSystemInfo.kernelConstant.PVH_HIGH_FLAGS = 0x7440000000000000LL;
											}

											// iOS 18+
											if (strcmp(darwinVersion, "24.0.0") >= 0) {
												if (hasSPTM) {
													gSystemInfo.kernelStruct.pmap.txm_address_space = 0xA8;
													gSystemInfo.kernelStruct.pmap.asid              = 0x88;
													gSystemInfo.kernelStruct.pmap.type              = 0x94;
												}
												else {
													gSystemInfo.kernelConstant.PVH_HIGH_FLAGS = 0x7F10000000000000LL;
												}

												// vm_map
												gSystemInfo.kernelStruct.vm_map.flags = 0xD8;

												// task
												if (isArm64e) {
													gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x568 + taskJitboxAdjust;
												}
												else {
													gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x548;
												}
												
												// iOS 18.1+ (beta 5 and up)
												if (strcmp(darwinVersion, "24.1.0") >= 0 && xnu_version_compare(xnuVersion, (struct xnu_version){.major = 11215, .minor = 40, .patch = 59}) >= 0) {
													// No more size
													gSystemInfo.kernelStruct.trustcache.size        = 0x0;
													gSystemInfo.kernelStruct.trustcache.fileptr     = 0x18;
													gSystemInfo.kernelStruct.trustcache.struct_size = 0x28;

													// iOS 18.4+
													if (strcmp(darwinVersion, "24.4.0") >= 0) {
														if (hasSPTM) {
															gSystemInfo.kernelConstant.PVH_HIGH_FLAGS = 0x74C0000000000000LL;
														}
														else {
															gSystemInfo.kernelConstant.PVH_HIGH_FLAGS = 0x7F90000000000000LL;
														}

														// task
														if (isArm64e) {
															gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x588 + taskJitboxAdjust;
														}
														else {
															gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x568;
														}
											
														// No more prev (Fully back to iOS 15 format, lol)
														gSystemInfo.kernelStruct.trustcache.prevptr = 0x0;

														// sptm_frame_type_descriptor
														gSystemInfo.kernelStruct.sptm_frame_type_descriptor.type = 0x1;

														// p_original_ppid was removed from proc
														gSystemInfo.kernelStruct.proc.svuid  = 0x38;
														gSystemInfo.kernelStruct.proc.svgid  = 0x3C;
														// starting at p_puniqueid, everything is the same as before again

														// pid_t p_orig_ppid;
														// int p_orig_ppidversion;
														// ^ Was added right before csflags, so everything after it shifted by 0x8
														gSystemInfo.kernelStruct.proc_ro.csflags               += 0x8;
														gSystemInfo.kernelStruct.proc_ro.ucred                 += 0x8;
														gSystemInfo.kernelStruct.proc_ro.syscall_filter_mask   += 0x8;
														gSystemInfo.kernelStruct.proc_ro.mach_trap_filter_mask += 0x8;
														gSystemInfo.kernelStruct.proc_ro.mach_kobj_filter_mask += 0x8;
														gSystemInfo.kernelStruct.proc_ro.t_flags_ro            += 0x8;
														gSystemInfo.kernelStruct.proc_ro.task_tokens           += 0x8;

														// iOS 26.0+
														if (strcmp(darwinVersion, "25.0.0") >= 0) {
															gSystemInfo.kernelConstant.TFRO_HARDENED = 0x0;
															gSystemInfo.kernelConstant.TFRO_PLATFORM = 0x80;
															
															// socket
															gSystemInfo.kernelStruct.socket.usecount = 0x23c;

															// task
															gSystemInfo.kernelStruct.task.task_can_transfer_memory_ownership = 0x560 + taskJitboxAdjust;
											
															if (hasSPTM) {
																// pmap
																gSystemInfo.kernelStruct.pmap.txm_address_space = 0x98;

																// TXMAddressSpace
																gSystemInfo.kernelStruct.TXMAddressSpace.codeRegions       = 0x28;
																gSystemInfo.kernelStruct.TXMAddressSpace.allowsInvalidCode = 0x30;
															}
															else {
																gSystemInfo.kernelConstant.PVH_HIGH_FLAGS = 0x7FC0000000000000LL;
															}

															// ipc_space
															gSystemInfo.kernelStruct.ipc_space.table = 0x48;

															// ipc_port
															gSystemInfo.kernelStruct.ipc_port.kobject = 0x50;

															// vm_map_entry
															gSystemInfo.kernelStruct.vm_map_entry.flags_xnu_user_debug = 27;

															// IOMachPort
															gSystemInfo.kernelStruct.IOMachPort.object = 0x20;

															// iOS 26.4+
															if (strcmp(darwinVersion, "25.4.0") >= 0) {
																if (hasSPTM) {
																	// pmap
																	gSystemInfo.kernelStruct.pmap.asid = 0x6c + pmapA13A14TXMiOS27Adjust;
																	gSystemInfo.kernelStruct.pmap.txm_address_space = 0x88 + pmapA13A14TXMiOS27Adjust;
																}

																// vm_map
																gSystemInfo.kernelStruct.vm_map.hdr   = 0x18;
																gSystemInfo.kernelStruct.vm_map.flags = 0xE8;

																// vm_map_header
																gSystemInfo.kernelStruct.vm_map_header.first    = 0x0;
																gSystemInfo.kernelStruct.vm_map_header.last     = 0x8;
																gSystemInfo.kernelStruct.vm_map_header.nentries = 0x28;
																
																// vm_map_entry
																gSystemInfo.kernelStruct.vm_map_entry.next =  0x0;
																gSystemInfo.kernelStruct.vm_map_entry.prev =  0x8;
																gSystemInfo.kernelStruct.vm_map_entry.flags = 0x38;

																// iOS 26.5+
																if (strcmp(darwinVersion, "25.4.0") >= 0) {
																	// proc_ro->task_tokens was removed in 26.5
																	gSystemInfo.kernelStruct.proc_ro.task_tokens            = 0;
																	gSystemInfo.kernelStruct.proc_ro.mach_trap_filter_mask -= 0x28;
																	gSystemInfo.kernelStruct.proc_ro.mach_kobj_filter_mask -= 0x28;
																	gSystemInfo.kernelStruct.proc_ro.t_flags_ro            -= 0x28;


																	// iOS 27.0+
																	if (strcmp(darwinVersion, "27.0.0") >= 0) {
																		gSystemInfo.kernelConstant.PVH_TYPE_MASK = 0x7;
																		gSystemInfo.kernelConstant.PVH_HIGH_FLAGS = 0x64C0000000000000;

																		// vm_map
																		gSystemInfo.kernelStruct.vm_map.hdr   = 0x0;
																		gSystemInfo.kernelStruct.vm_map.flags = 0xB0;

																		// vm_map_entry
																		gSystemInfo.kernelStruct.vm_map_entry.prev                 = 0x4;
																		gSystemInfo.kernelStruct.vm_map_entry.next                 = 0x8;
																		gSystemInfo.kernelStruct.vm_map_entry.start                = 0x10;
																		gSystemInfo.kernelStruct.vm_map_entry.end                  = 0x18;
																		gSystemInfo.kernelStruct.vm_map_entry.flags_prot           = 4;
																		gSystemInfo.kernelStruct.vm_map_entry.flags_maxprot        = 8;
																		gSystemInfo.kernelStruct.vm_map_entry.flags_xnu_user_debug = 23;

																		// proc
																		gSystemInfo.kernelStruct.proc.flag = 0x444;

																		// proc_ro
																		// proc_ro->p_fixed_vfs_resolve_flags was added before ucred
																		gSystemInfo.kernelStruct.proc_ro.ucred                 += 0x8;
																		gSystemInfo.kernelStruct.proc_ro.syscall_filter_mask   += 0x8;
																		gSystemInfo.kernelStruct.proc_ro.mach_trap_filter_mask += 0x8;
																		gSystemInfo.kernelStruct.proc_ro.mach_kobj_filter_mask += 0x8;
																		gSystemInfo.kernelStruct.proc_ro.t_flags_ro            += 0x8;

																		if (hasSPTM) {
																			// vm_page
																			gSystemInfo.kernelStruct.vm_page.pv_head = 0x30;
																			gSystemInfo.kernelStruct.vm_page.struct_size = 0x40;
																		}
																	}
																}
															}
														}
													}
												}
											}
										}
									}
								}
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

	if (ksymbol(SPTMArgs)) {
		uint64_t args = kread64(ksymbol(SPTMArgs));
		uint64_t debugHeaderAddr = kread64(args + 0x60);
		gSystemInfo.kernelConstant.sptmBase = kread64(debugHeaderAddr + 0x10);
		gSystemInfo.kernelConstant.txmBase = kread64(debugHeaderAddr + 0x20);
		gSystemInfo.kernelConstant.sptmSlide = kconstant(sptmBase) - kconstant(staticSptmBase);
		gSystemInfo.kernelConstant.txmSlide = kconstant(txmBase) - kconstant(staticTxmBase);
	}
}

xpc_object_t jbinfo_get_serialized(void)
{
	xpc_object_t systemInfo = xpc_dictionary_create_empty();
	SYSTEM_INFO_SERIALIZE(systemInfo);
	return systemInfo;
}

uint64_t get_vm_real_kernel_page_size(void)
{
	static uint64_t real_kernel_page_size = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		real_kernel_page_size = vm_kernel_page_size;

		// vm_kernel_page_size is WRONG on A8X
		// Screw Apple
		cpu_subtype_t cpuFamily = 0;
		size_t cpuFamilySize = sizeof(cpuFamily);
		sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
		if (cpuFamily == CPUFAMILY_ARM_TYPHOON) {
			real_kernel_page_size = 0x1000;
		}
	});
	return real_kernel_page_size;
}


uint64_t get_vm_real_kernel_page_shift(void)
{
	static uint64_t real_kernel_page_shift = 0;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		real_kernel_page_shift = vm_kernel_page_shift;

		// vm_kernel_page_shift is WRONG on A8X
		// Screw Apple
		cpu_subtype_t cpuFamily = 0;
		size_t cpuFamilySize = sizeof(cpuFamily);
		sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
		if (cpuFamily == CPUFAMILY_ARM_TYPHOON) {
			real_kernel_page_shift = 14;
		}
	});
	return real_kernel_page_shift;
}

uint64_t get_l1_block_size(void)
{
	switch (vm_real_kernel_page_size) {
		case 0x4000:
		return 0x1000000000;
		case 0x1000:
		return 0x40000000;
		default:
		return 0;
	}
}

uint64_t get_l1_block_mask(void)
{
	return get_l1_block_size() - 1;
}

uint64_t get_l1_block_count(void)
{
	switch (vm_real_kernel_page_size) {
		case 0x4000:
		return 8;
		case 0x1000:
		return 256;
		default:
		return 0;
	}
}

uint64_t get_l2_block_size(void)
{
	switch (vm_real_kernel_page_size) {
		case 0x4000:
		return 0x2000000;
		case 0x1000:
		return 0x200000;
		default:
		return 0;
	}
}

uint64_t get_l2_block_mask(void)
{
	return get_l2_block_size() - 1;
}

uint64_t get_l2_block_count(void)
{
	switch (vm_real_kernel_page_size) {
		case 0x4000:
		return 2048;
		case 0x1000:
		return 512;
		default:
		return 0;
	}
}
