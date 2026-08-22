#include <stdio.h>
#include <stdlib.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/getsect.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <paths.h>
#include <util.h>
#include <ptrauth.h>
#include <pthread.h>
#include <sys/proc_info.h>
#include <libproc.h>
#include <copyfile.h>

#import "krw-corellium.h"

#import <DOJailbreaker.h>
#import <DOBootstrapper.h>
#import <DOEnvironmentManager.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/basebin_gen.h>
#import <libjailbreak/kernel.h>
#import <libjailbreak/util.h>
#import <libjailbreak/primitives.h>
#import <libjailbreak/translation.h>
#import <libjailbreak/signatures.h>
#import <libjailbreak/trustcache.h>
#import <libjailbreak/primitives_IOSurface.h>
#import <libjailbreak/physrw.h>
#import <libjailbreak/physrw_pte.h>
#import <libjailbreak/info.h>
#import <libjailbreak/jbserver.h>

void uart_printf(const char *format, ...)
{
	va_list args;
	va_start(args, format);
	vprintf(format, args);
	va_end(args);
}

int reboot3(uint64_t flags, ...);
#define RB2_USERREBOOT (0x2000000000000000llu)

DOJailbreaker *gJb;

@interface DOJailbreaker (Private)
- (NSError *)showNonDefaultSystemApps;
- (NSError *)ensureDevModeEnabled;
- (NSError *)gatherSystemInformation;
- (NSError *)loadBasebinTrustcache;
- (NSError *)injectLaunchdHook;
- (NSError *)applyProtection;
- (NSError *)createFakeLib;
@end

void init_libjailbreak(void)
{	
	int r = corellium_krw_init();
	if (r != 0) {
		printf("Failed initializing krw: %d\n", r);
		exit(-1);
	}

	jbinfo_initialize_boot_constants();
	libjailbreak_translation_init();

	printf("Transferring primitive... "); fflush(stdout); usleep(1000);
	r = libjailbreak_physrw_pte_init(false, 0);
	if (r == 0) {
		printf("OK\n"); fflush(stdout); usleep(1000);
	}
	else {
		printf("Failed!\n"); fflush(stdout); usleep(1000);
		exit(-1);
	}
	usleep(1000);

#if BUILD_STANDALONE
	signal_krw_done();
#endif

	libjailbreak_IOSurface_primitives_init();
}

void install_basebin_gen(void)
{
	printf("Installing basebin...\n"); fflush(stdout); usleep(1000);

	NSString *usrLibPath = @"/usr/lib";
	NSString *existingBasebin = JBROOT_PATH(@"/basebin");
	NSString *targetBasebin = existingBasebin;

	int r = basebin_generate_internal(usrLibPath, existingBasebin, targetBasebin, false);
	if (r != 0) {
		printf("Failed installing basebin: %d\n", r); fflush(stdout); usleep(1000);
		exit(-1);
	}
}

void activate_basebin(NSString *basebinPath)
{
	printf("Activating %s basebin...\n", basebinPath.fileSystemRepresentation); fflush(stdout); usleep(1000);

	NSString *fakelibDyldPath = [basebinPath stringByAppendingPathComponent:@".fakelib/dyld"];

	cdhash_t *cdhashes = NULL;
	uint32_t cdhashesCount = 0;
	file_collect_untrusted_cdhashes_by_path(fakelibDyldPath.fileSystemRepresentation, &cdhashes, &cdhashesCount);
	if (cdhashesCount != 1) {
		printf("Activating basebin failed: cdhashesCount != 1\n");
		exit(-1);
	}
	
	trustcache_file_v1 *dyldTCFile = NULL;
	int r = trustcache_file_build_from_cdhashes(cdhashes, cdhashesCount, &dyldTCFile);
	free(cdhashes);
	if (r == 0) {
		r = trustcache_file_upload_with_uuid(dyldTCFile, DYLD_TRUSTCACHE_UUID);
		free(dyldTCFile);
		if (r != 0) {
			printf("Activating basebin failed: trustcache_file_upload_with_uuid returned %d\n", r);
			exit(-1);
		}
	}
	else {
		printf("Activating basebin failed: trustcache_file_build_from_cdhashes returned %d\n", r);
		exit(-1);
	}

	r = [[DOEnvironmentManager sharedManager] setFakelibMounted:YES];
	if (r != 0) {
		printf("Activating basebin failed: setFakelibMounted returned %d\n", r);
		exit(-1);
	}

	printf("Activated %s basebin!\n", basebinPath.fileSystemRepresentation); fflush(stdout); usleep(1000);
}

void find_offsets(void)
{
	NSError *error = [gJb gatherSystemInformation];
	if (error) {
		printf("offset finding failed with %s\n", error.description.UTF8String);
		exit(-1);
	}
}

void fix_non_default_apps(void)
{
	printf("Making non default system apps visible... "); fflush(stdout); usleep(1000);
	NSError *error = [gJb showNonDefaultSystemApps];
	if (error) {
		printf("\nMaking non default system apps visible failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
		exit(-1);
	}
	printf("OK\n"); fflush(stdout); usleep(1000);
}

void ensure_dev_mode_enabled(void)
{
	printf("Ensuring dev mode enabled... "); fflush(stdout); usleep(1000);
	NSError *error = [gJb ensureDevModeEnabled];
	if (error) {
		printf("\nEnsuring dev mode enabled failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
		exit(-1);
	}
	printf("OK\n"); fflush(stdout); usleep(1000);
}

void ensure_jailbreak_root_exists(void)
{
	printf("Ensuring jailbreak root existance... "); fflush(stdout); usleep(1000);
	gSystemInfo.jailbreakInfo.rootPath = NULL;
	NSError *error = [[DOEnvironmentManager sharedManager] ensureJailbreakRootExists];
	if (error) {
		printf("\nEnsuring jailbreak root existance failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
		exit(-1);
	}
	printf("OK\n"); fflush(stdout); usleep(1000);
}

void prepare_bootstrap(void)
{
	printf("Preparing bootstrap... "); fflush(stdout); usleep(1000);
	NSError *error = [[DOEnvironmentManager sharedManager] prepareBootstrap];
	if (error) {
		printf("\nPreparing bootstrap failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
		exit(-1);
	}
	printf("OK\n"); fflush(stdout); usleep(1000);
}

void update_var_jb_symlink(void)
{
	printf("Updating /var/jb symlink... "); fflush(stdout); usleep(1000);
	DOBootstrapper *bootstrapper = [[DOBootstrapper alloc] init];
	NSError *error = [bootstrapper updateVarJbSymlink];
	if (error) {
		printf("\nUpdating /var/jb symlink failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
		exit(-1);
	}
	printf("OK\n");
}

void load_basebin_trustcache(void)
{
	printf("Loading BaseBin Trustcache... "); fflush(stdout); usleep(1000);
	NSError *error = [gJb loadBasebinTrustcache];
	if (error) {
		printf("\nLoading basebin trustcache failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
		exit(-1);
	}
	printf("OK\n"); fflush(stdout); usleep(1000);
}

void inject_launchd_hook(void)
{
	printf("Injecting launchd hook... "); fflush(stdout); usleep(1000);
	NSError *error = [gJb injectLaunchdHook];
	if (error) {
		printf("\nInjecting launchd hook failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
		exit(-1);
	}
	printf("OK\n");
}

void apply_preboot_protection(void)
{
	printf("Applying protection... "); fflush(stdout); usleep(1000);
	NSError *error = [gJb applyProtection];
	if (error) {
		printf("\nApplying protection failed: %s\n", error.description.UTF8String); fflush(stdout); usleep(1000);
		exit(-1);
	}
	printf("OK\n");
}

int install_package(NSString *packagePath)
{
	return exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"), "-i", packagePath.UTF8String, NULL);
}

void load_var_jb_daemons(void)
{
	// For some reason, we cannot run 'launchctl load' from the stage2 dropbear environment
	// I spent a lot of time figuring out why and it's something related to us being considered the wrong session / domain
	// No clue how to fix that, but I also figured out that 'launchctl bootstrap system' works...
	// Supposedly because this command allows us to manually specifiy a session / domain (which in this case is 'system')
	exec_cmd_trusted(JBROOT_PATH("/usr/bin/launchctl"), "bootstrap", "system", JBROOT_PATH("/Library/LaunchDaemons"), NULL);
}

void install_builtin_packages(void)
{
	NSURL *packageDirURL = [NSURL fileURLWithPath:JBROOT_PATH(@"/prep")];
	if (![packageDirURL checkResourceIsReachableAndReturnError:nil]) {
		packageDirURL = [NSURL fileURLWithPath:[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Packages"]];
	}
	if ([packageDirURL checkResourceIsReachableAndReturnError:nil]) {
		NSArray<NSURL *> *packageURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:packageDirURL includingPropertiesForKeys:nil options:0 error:nil];
		for (NSURL *packageURL in packageURLs) {
			int r = install_package(packageURL.path);
			if (r != 0) {
				printf("WARNING: Failed to install %s (%d)\n", packageURL.path.fileSystemRepresentation, r);
			}
		}
		[[NSFileManager defaultManager] removeItemAtURL:packageDirURL error:nil];
		if (@available(iOS 19.0, *)) {
			// If we just installed prep packages on iOS 26+, load daemons now
			// This wasn't working before, since launchctl had to be updated first
			load_var_jb_daemons();
		}
	}
}

void finalize_bootstrap_if_needed(bool *finalized)
{
	char *pathBackup = getenv("PATH") ? strdup(getenv("PATH")) : NULL;
	char *shellBackup = getenv("SHELL") ? strdup(getenv("SHELL")) : NULL;

	setenv("NO_PASSWORD_PROMPT", "1", 1);
	setenv("PATH", "/sbin:/bin:/usr/sbin:/usr/bin:/rootfs/sbin:/rootfs/bin:/rootfs/usr/sbin:/rootfs/usr/bin", 1);
	setenv("TERM", "xterm-256color", 1);
	setenv("SHELL", JBROOT_PATH("/bin/sh"), 1);

	if ([[NSFileManager defaultManager] fileExistsAtPath:JBROOT_PATH(@"/prep_bootstrap.sh")]) {
		printf("Running prep_bootstrap script...\n");
		int r = exec_cmd_trusted(JBROOT_PATH("/bin/sh"), JBROOT_PATH("/prep_bootstrap.sh"), NULL);
		if (r != 0) {
			printf("prep_bootstrap failed: %d\n", r);
			exit(-1);
		}
		else {
			if (finalized) *finalized = true;
		}
	}

	install_builtin_packages();

	unsetenv("NO_PASSWORD_PROMPT");
	unsetenv("TERM");
	if (pathBackup) {
		setenv("PATH", pathBackup, 1);
		free(pathBackup);
	}
	else {
		unsetenv("PATH");
	}
	if (shellBackup) {
		setenv("SHELL", shellBackup, 1);
		free(shellBackup);
	}
	else {
		unsetenv("SHELL");
	}
}

void print_existing_procs(void)
{
	int proccount = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
	if (proccount == 0) return;

	pid_t *pids = malloc(proccount * sizeof(pid_t));
	proc_listpids(PROC_ALL_PIDS, 0, pids, proccount);

	for (int i = 0; i < proccount; i++) {
		pid_t pid = pids[i];

		char pidPath[4*MAXPATHLEN];
		if (proc_pidpath(pid, pidPath, sizeof(pidPath)) <= 0) {
			continue;
		}

		uint64_t proc = proc_find(pid);
		if (!proc) continue;
		uint64_t ucred = proc_ucred(proc);

		printf("%d: %s [proc=%#llx, ucred=%#llx]\n", pid, pidPath, proc, ucred);
	}
}

void activate_environment(bool applyProtection, bool prepareBootstrap)
{
	find_offsets();
	init_libjailbreak();

	fix_non_default_apps();

	ensure_dev_mode_enabled();

	ensure_jailbreak_root_exists();

	if (prepareBootstrap) {
		prepare_bootstrap();
	}
	else {
		update_var_jb_symlink();
	}

	load_basebin_trustcache();

	inject_launchd_hook();
	
	if (applyProtection) {
		apply_preboot_protection();
	}
}

void install_dopamine(void)
{
	activate_environment(false, true);

	install_basebin_gen();
	activate_basebin(JBROOT_PATH(@"/basebin"));

	// Now that fakelib is up, we want to make systemhook inject into any binary we spawn
	setenv("DYLD_INSERT_LIBRARIES", "/usr/lib/systemhook.dylib", 1);

	finalize_bootstrap_if_needed(NULL);
	load_var_jb_daemons();

	printf("Dopamine installed!\n");
}

void install_dopamine_from_tarball(const char *tarballPath, const char *bootstrapPath)
{
	[[NSFileManager defaultManager] removeItemAtPath:@"/private/preboot/dopamine_tmp" error:nil];
	[[NSFileManager defaultManager] createDirectoryAtPath:@"/private/preboot/dopamine_tmp" withIntermediateDirectories:NO attributes:nil error:nil];
	libarchive_unarchive(tarballPath, "/private/preboot/dopamine_tmp");
	if (bootstrapPath) {
		[[NSFileManager defaultManager] copyItemAtPath:[NSString stringWithUTF8String:bootstrapPath] toPath:@"/private/preboot/dopamine_tmp/bootstrap_1900.tar.zst" error:nil];
	}

	const char *newPath = "/private/preboot/dopamine_tmp/dopamine";
	extern char **environ;
	char *argv[] = (char *[]){
		(char *)newPath,
		(char *)"install",
		NULL,
	};
	execve(newPath, argv, environ);
}

void activate_dopamine(void)
{
	activate_environment(true, false);
	activate_basebin(JBROOT_PATH(@"/basebin"));
	
	// Now that fakelib is up, we want to make systemhook inject into any binary we spawn
	setenv("DYLD_INSERT_LIBRARIES", "/usr/lib/systemhook.dylib", 1);

	finalize_bootstrap_if_needed(NULL);
	load_var_jb_daemons();

	printf("Dopamine activated, see you on the other side!\n");
}

int main(int argc, char* argv[])
{
	gJb = [[DOJailbreaker alloc] init];

	if (argc >= 2) {
		if (!strcmp(argv[1], "install")) {
			if (argc >= 3) {
				const char *bootstrapPath = argc >= 4 ? argv[3] : NULL;
				install_dopamine_from_tarball(argv[2], bootstrapPath);
			}
			else {
				install_dopamine();
			}
		}
		else if (!strcmp(argv[1], "activate")) {
			activate_dopamine();
		}
	}

	return 0;
}