#include <stdlib.h>
#include <libjailbreak/util.h>
#include <libjailbreak/trustcache.h>
#include <libjailbreak/kcall_arm64.h>
#include <libjailbreak/signatures.h>
#include <libjailbreak/basebin_gen.h>
#include <xpc/xpc.h>
#include <dlfcn.h>

#import <Foundation/Foundation.h>

void abort_with_reason(uint32_t reason_namespace, uint64_t reason_code, const char *reason_string, uint64_t reason_flags);

int jbupdate_basebin(const char *basebinTarPath)
{
	@autoreleasepool {
		int r = 0;
		if (access(basebinTarPath, F_OK) != 0) return 1;

		NSString *prevVersion = [NSString stringWithContentsOfFile:JBROOT_PATH(@"/basebin/.version") encoding:NSUTF8StringEncoding error:nil] ?: @"2.0";

		// Extract basebin tar
		NSString *tmpExtractionPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
		r = libarchive_unarchive(basebinTarPath, tmpExtractionPath.fileSystemRepresentation);
		if (r != 0) {
			[[NSFileManager defaultManager] removeItemAtPath:tmpExtractionPath error:nil];
			return 2;
		}
		NSString *tmpBasebinPath = [tmpExtractionPath stringByAppendingPathComponent:@"basebin"];

		// Update basebin trustcache
		NSString *trustcachePath = [tmpBasebinPath stringByAppendingPathComponent:@"basebin.tc"];
		if (![[NSFileManager defaultManager] fileExistsAtPath:trustcachePath]) return 3;
		trustcache_file_v1 *basebinTcFile = NULL;
		if (trustcache_file_build_from_path(trustcachePath.fileSystemRepresentation, &basebinTcFile) != 0) {
			[[NSFileManager defaultManager] removeItemAtPath:tmpExtractionPath error:nil];
			return 4;
		}
		r = trustcache_file_upload_with_uuid(basebinTcFile, BASEBIN_TRUSTCACHE_UUID);
		free(basebinTcFile);
		if (r != 0) {
			[[NSFileManager defaultManager] removeItemAtPath:tmpExtractionPath error:nil];
			return 5;
		}
		else {
			[[NSFileManager defaultManager] removeItemAtPath:trustcachePath error:nil];
		}

		// Replace basebin content
		NSArray *newBasebinContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmpBasebinPath error:nil];
		for (NSString *basebinItem in newBasebinContents) {
			NSString *newBasebinPath = [tmpBasebinPath stringByAppendingPathComponent:basebinItem];
			NSString *oldBasebinPath = [JBROOT_PATH(@"/basebin") stringByAppendingPathComponent:basebinItem];
			if ([[NSFileManager defaultManager] fileExistsAtPath:oldBasebinPath]) {
				[[NSFileManager defaultManager] removeItemAtPath:oldBasebinPath error:nil];
			}
			[[NSFileManager defaultManager] copyItemAtPath:newBasebinPath toPath:oldBasebinPath error:nil];
		}
		[[NSFileManager defaultManager] removeItemAtPath:tmpExtractionPath error:nil];

		// Patch basebin plists
		NSURL *basebinDaemonsURL = [NSURL fileURLWithPath:JBROOT_PATH(@"/basebin/LaunchDaemons")];
		for (NSURL *basebinDaemonURL in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:basebinDaemonsURL includingPropertiesForKeys:nil options:0 error:nil]) {
			NSString *plistPath = basebinDaemonURL.path;
			NSMutableDictionary *plistDict = [NSMutableDictionary dictionaryWithContentsOfFile:plistPath];
			if (plistDict) {
				bool madeChanges = NO;
				NSMutableArray *programArguments = ((NSArray *)plistDict[@"ProgramArguments"]).mutableCopy;
				for (NSString *argument in [programArguments reverseObjectEnumerator]) {
					if ([argument containsString:@"@JBROOT@"]) {
						programArguments[[programArguments indexOfObject:argument]] = [argument stringByReplacingOccurrencesOfString:@"@JBROOT@" withString:JBROOT_PATH(@"/")];
						madeChanges = YES;
					}
				}
				if (madeChanges) {
					plistDict[@"ProgramArguments"] = programArguments.copy;
					[plistDict writeToFile:plistPath atomically:NO];
				}
			}
		}

		NSString *newVersion = [NSString stringWithContentsOfFile:JBROOT_PATH(@"/basebin/.version") encoding:NSUTF8StringEncoding error:nil];
		if (!newVersion) return 6;

		setenv("JBUPDATE_PREV_VERSION", prevVersion.UTF8String, 1);
		setenv("JBUPDATE_NEW_VERSION", newVersion.UTF8String, 1);
		return 0;
	}
}

void jbupdate_update_system_info(void)
{
	@autoreleasepool {
		// Load XPF
		void *xpfHandle = dlopen("@loader_path/libxpf.dylib", RTLD_NOW);
		if (!xpfHandle) {
			char msg[4000];
			snprintf(msg, 4000, "Dopamine: dlopening libxpf failed: (%s), cannot continue.", dlerror());
			abort_with_reason(7, 1, msg, 0);
			return;
		}
		int (*xpf_start_with_kernel_path)(const char *kernelPath) = dlsym(xpfHandle, "xpf_start_with_kernel_path");
		const char *(*xpf_get_error)(void) = dlsym(xpfHandle, "xpf_get_error");
		bool (*xpf_set_is_supported)(const char *name) = dlsym(xpfHandle, "xpf_set_is_supported");
		void (*xpf_stop)(void) = dlsym(xpfHandle, "xpf_stop");
		xpc_object_t (*xpf_construct_offset_dictionary)(const char *sets[]) = dlsym(xpfHandle, "xpf_construct_offset_dictionary");

		const char *kernelPath = prebootUUIDPath("/System/Library/Caches/com.apple.kernelcaches/kernelcache");
		xpc_object_t newSystemInfoXdict = NULL;

		// Rerun patchfinder
		int r = xpf_start_with_kernel_path(kernelPath);
		const char *error = NULL;
		if (r == 0) {
			char *sets[] = {
				"translation",
				"trustcache",
				"sandbox",
				"physmap",
				"struct",
				"physrw",
				NULL,
				NULL,
				NULL,
				NULL,
				NULL,
			};

			uint32_t idx = 0;
			while(sets[++idx]);

			if (xpf_set_is_supported("devmode")) {
				sets[idx++] = "devmode"; 
			}
			if (xpf_set_is_supported("badRecovery")) {
				sets[idx++] = "badRecovery"; 
			}
			if (xpf_set_is_supported("arm64kcall")) {
				sets[idx++] = "arm64kcall"; 
			}
			if (xpf_set_is_supported("perfkrw")) {
				sets[idx++] = "perfkrw";
			}

			newSystemInfoXdict = xpf_construct_offset_dictionary((const char **)sets);
			if (!newSystemInfoXdict) {
				error = xpf_get_error();
			}
			xpf_stop();
		}
		else {
			xpf_stop();
			error = xpf_get_error();
		}

		if (error) {
			char msg[4000];
			snprintf(msg, 4000, "Dopamine: Updating system info via XPF failed with error: (%s), cannot continue.", error);
			abort_with_reason(7, 1, msg, 0);
			return;
		}

		dlclose(xpfHandle);

		// Get old info and merge new info into it
		xpc_object_t systemInfoXdict = jbinfo_get_serialized();
		xpc_dictionary_apply(newSystemInfoXdict, ^_Bool(const char *key, xpc_object_t xobj) {
			xpc_dictionary_set_value(systemInfoXdict, key, xobj);
			return true;
		});

		// Rebuild gSystemInfo
		jbinfo_initialize_dynamic_offsets(systemInfoXdict);
		jbinfo_initialize_hardcoded_offsets();
	}
}

// Before primitives are retrieved
void jbupdate_finalize_stage1(const char *prevVersion, const char *newVersion)
{
	// Currently unused, reserved for the future
}

// After primitives are retrieved
void jbupdate_finalize_stage2(const char *prevVersion, const char *newVersion)
{
	jbupdate_update_system_info();

	if (strcmp(prevVersion, "2.4") < 0 && strcmp(newVersion, "2.4") >= 0) {
		// On Dopamine <= 2.3, dyld used to be a file on the fakelib mount
		// Due to that, the fakelib mount cannot be unmounted, or else the system will panic
		// Additionally it cannot be modified because bind mounts are weird and won't update correctly
		// In >= 2.4 dyld is a symlink to elsewhere, which allows it to be updated and the bind mount to be unmounted
		// But if we're coming from <= 2.3, we have no option other than to reboot the device
		reboot(0);
	}

	// Legacy, this file is no longer used
	if (!access(JBROOT_PATH("/basebin/.idownloadd_enabled"), F_OK)) {
		remove(JBROOT_PATH("/basebin/.idownloadd_enabled"));
	}

	if (strcmp(prevVersion, "2.1") < 0 && strcmp(newVersion, "2.1") >= 0) {
		// Default value for this pref is true
		// Set it during jbupdate if prev version is <2.1 and new version is >=2.1
		gSystemInfo.jailbreakSettings.markAppsAsDebugged = true;

#ifndef __arm64e__
		// Initialize kcall only after we have the offsets required for it
		arm64_kcall_init();
#endif
	}

	// Update patched dyld
	int r = basebin_generate(YES);
	if (r != 0) {
		char msg[4000];
		snprintf(msg, 4000, "Dopamine: Updating patched dyld failed with error %d, cannot continue.", r);
		abort_with_reason(7, 1, msg, 0);
	}

	// Update dyld trustcache
	cdhash_t *cdhashes = NULL;
	uint32_t cdhashesCount = 0;
	file_collect_untrusted_cdhashes_by_path(JBROOT_PATH("/basebin/.fakelib/dyld"), &cdhashes, &cdhashesCount);

	if (cdhashesCount > 1) {
		char msg[4000];
		snprintf(msg, 4000, "Dopamine: Updating patched dyld failed due to unexpected amount of cdhashes (%d), cannot continue.", cdhashesCount);
		abort_with_reason(7, 1, msg, 0);
	}
	else if (cdhashesCount == 1) {
		trustcache_file_v1 *dyldTCFile = NULL;
		r = trustcache_file_build_from_cdhashes(cdhashes, cdhashesCount, &dyldTCFile);
		free(cdhashes);
		if (r != 0) {
			char msg[4000];
			snprintf(msg, 4000, "Dopamine: Building dyld trustcache failed with error %d, cannot continue.", r);
			abort_with_reason(7, 1, msg, 0);
		}

		r = trustcache_file_upload_with_uuid(dyldTCFile, DYLD_TRUSTCACHE_UUID);
		if (r != 0) {
			char msg[4000];
			snprintf(msg, 4000, "Dopamine: Updating dyld trustcache failed with error %d, cannot continue.", r);
			abort_with_reason(7, 1, msg, 0);
		}

		free(dyldTCFile);
	}

	JBFixMobilePermissions();
}