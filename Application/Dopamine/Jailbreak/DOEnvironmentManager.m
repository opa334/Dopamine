//
//  EnvironmentManager.m
//  Dopamine
//
//  Created by Lars Fröder on 10.01.24.
//

#import "DOEnvironmentManager.h"
#import "UIImage+JPEG2000.h"

#import <sys/sysctl.h>
#import <sys/mount.h>
#import <sys/utsname.h>
#import <sys/stat.h>
#import <unistd.h>
#import <dirent.h>
#import <errno.h>
#import <mach-o/dyld.h>
#import <libgrabkernel2/libgrabkernel2.h>
#import <libjailbreak/info.h>
#import <libjailbreak/codesign.h>
#import <libjailbreak/util.h>
#import <libjailbreak/display.h>
#import <libjailbreak/machine_info.h>
#import <libjailbreak/carboncopy.h>

#import <IOKit/IOKitLib.h>
#import "DOUIManager.h"
#import "DOExploitManager.h"
#import "DOPreferenceManager.h"
#import "NSData+Hex.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <errno.h>
#import <string.h>

int reboot3(uint64_t flags, ...);
// ROOTHIDE FIX LỖI 1: RB2_USERREBOOT flag cho reboot3 syscall.
// Giá trị 0x2000000000000000 — yêu cầu userspace reboot (không hard reboot).
// Match giá trị trong jbctl/src/main.m line 11.
#define RB2_USERREBOOT (0x2000000000000000llu)
CFPropertyListRef MGCopyAnswer(CFStringRef);
extern char **environ;

@implementation DOEnvironmentManager

+ (instancetype)sharedManager
{
    static DOEnvironmentManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[DOEnvironmentManager alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _bootstrapNeedsMigration = NO;
        _bootstrapper = [[DOBootstrapper alloc] init];
        if ([self isJailbroken]) {
            gSystemInfo.jailbreakInfo.rootPath = strdup(jbclient_get_jbroot() ?: "");
        }
        else if ([self isInstalledThroughTrollStore]) {
            [self locateJailbreakRoot];
        }
    }
    return self;
}

- (NSString *)nightlyHash
{
#ifdef NIGHTLY
    return [NSString stringWithUTF8String:COMMIT_HASH];
#else
    return nil;
#endif
}

- (NSString *)appVersion
{
    return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
}

- (NSString *)appVersionDisplayString
{
    NSString *nightlyHash = [self nightlyHash];
    if (nightlyHash) {
        return [NSString stringWithFormat:@"%@~%@", self.appVersion, [nightlyHash substringToIndex:6]];
    }
    else {
        return [self appVersion];
    }
}

- (NSString *)privatePrebootPath
{
    return @"/private/preboot";
}

- (NSString *)activePrebootPath
{
    NSString *bootManifestString = [NSString stringWithUTF8String:boot_manifest_hash()];
    return [[self privatePrebootPath] stringByAppendingPathComponent:bootManifestString];
}

// ROOTHIDE FIX: Generate a JBRAND matching RootHide format.
// RootHide roothideinit.dylib requires jbroot dir name = ".jbroot-XXXXXXXXXXXXXXXX"
// (16 hex uppercase, byte 0 = XOR checksum of bytes 1..7).
static NSString *generateRootHideJBRAND(void)
{
    uint64_t value = ((uint64_t)arc4random()) | ((uint64_t)arc4random() << 32);
    uint8_t check = (value >> 8) ^ (value >> 16) ^ (value >> 24) ^
                    (value >> 32) ^ (value >> 40) ^ (value >> 48) ^ (value >> 56);
    uint64_t jbrand = (value & ~0xFFULL) | check;
    return [NSString stringWithFormat:@"%016llX", jbrand];
}

static BOOL checkRootHideJBRAND(NSString *str)
{
    if (str.length != 16) return NO;
    const char *cstr = str.UTF8String;
    char *endp = NULL;
    unsigned long long value = strtoull(cstr, &endp, 16);
    if (!endp || *endp != '\0') return NO;
    uint8_t check = (value >> 8) ^ (value >> 16) ^ (value >> 24) ^
                    (value >> 32) ^ (value >> 40) ^ (value >> 48) ^ (value >> 56);
    return check == (uint8_t)value;
}

- (void)locateJailbreakRoot
{
    if (!gSystemInfo.jailbreakInfo.rootPath) {
        // ROOTHIDE: jbroot is at /var/containers/Bundle/Application/.jbroot-XXXXXXXXXXXXXXXX
        // This path format is REQUIRED by roothideinit.dylib is_jbroot_name().
        NSString *jbrootSearchPath = @"/var/containers/Bundle/Application";
        NSString *randomizedJailbreakPath;

        // ROOTHIDE FIX (EPERM): spawning /bin/ls with a persona override
        // (posix_spawnattr_set_persona_np 99 OVERRIDE) fails with EPERM on
        // iOS 16.7.16 AND 17.5.1 ("locateJailbreakRoot: /bin/ls spawn failed: 1"
        // in user logs). Listing the directory in-process with opendir works
        // once the app is root + unsandboxed (elevatePrivileges +
        // runUnsandboxed both run before this on the jailbreak path), and is
        // what NSFileManager falls back to below anyway — so do the syscall
        // scan FIRST and only use the two fallbacks when it fails.
        NSLog(@"[RootHide] locateJailbreakRoot: scanning %@ in-process", jbrootSearchPath);

        // FIX: name length must be 24 (8 prefix `.jbroot-` + 16 hex jbrand),
        // not 23. With length==23, checkRootHideJBRAND() always returns NO
        // (it requires 16 hex chars), causing every jailbreak to create a NEW
        // .jbroot-XXX instead of reusing the existing one.
        DIR *scanDir = opendir(jbrootSearchPath.fileSystemRepresentation);
        if (scanDir) {
            struct dirent *de;
            while ((de = readdir(scanDir)) != NULL) {
                if (strlen(de->d_name) != 24 || strncmp(de->d_name, ".jbroot-", 8) != 0) continue;
                NSString *entryName = [NSString stringWithUTF8String:de->d_name];
                NSString *jbrandStr = [entryName substringFromIndex:8];
                BOOL valid = checkRootHideJBRAND(jbrandStr);
                NSLog(@"[RootHide] locateJailbreakRoot: .jbroot- found, jbrand=%@ valid=%d", jbrandStr, valid);
                if (valid) {
                    randomizedJailbreakPath = [jbrootSearchPath stringByAppendingPathComponent:entryName];
                    NSLog(@"[RootHide] locateJailbreakRoot: FOUND existing jbroot at %@", randomizedJailbreakPath);
                    break;
                }
            }
            closedir(scanDir);
        }
        else {
            NSLog(@"[RootHide] locateJailbreakRoot: opendir failed (errno %d), trying NSFileManager", errno);
            // Fallback 1: NSFileManager (equivalent scan through the framework)
            NSError *listError = nil;
            NSArray *fmItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:jbrootSearchPath error:&listError];
            if (listError) {
                NSLog(@"[RootHide] locateJailbreakRoot: NSFileManager also failed: %@", listError);
            } else if (fmItems) {
                for (NSString *subItem in fmItems) {
                    if (subItem.length == 24 && [subItem hasPrefix:@".jbroot-"]) {
                        NSString *jbrandStr = [subItem substringFromIndex:8];
                        if (checkRootHideJBRAND(jbrandStr)) {
                            randomizedJailbreakPath = [jbrootSearchPath stringByAppendingPathComponent:subItem];
                            NSLog(@"[RootHide] locateJailbreakRoot: FOUND via NSFileManager: %@", randomizedJailbreakPath);
                            break;
                        }
                    }
                }
            }
        }

        if (!randomizedJailbreakPath) {
            // Fallback 2 (kept for debugging): persona /bin/ls, which may still
            // work on some builds. Never fatal — just another data point.
            int pipefd[2];
            if (pipe(pipefd) == 0) {
                pid_t pid = 0;
                posix_spawn_file_actions_t action;
                posix_spawn_file_actions_init(&action);
                posix_spawn_file_actions_adddup2(&action, pipefd[1], STDOUT_FILENO);
                posix_spawn_file_actions_addclose(&action, pipefd[0]);
                posix_spawn_file_actions_addclose(&action, pipefd[1]);

                posix_spawnattr_t attr;
                posix_spawnattr_init(&attr);
                posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
                posix_spawnattr_set_persona_uid_np(&attr, 0);
                posix_spawnattr_set_persona_gid_np(&attr, 0);

                char *argv[] = {"/bin/ls", "-1a", (char *)jbrootSearchPath.UTF8String, NULL};
                int spawnErr = posix_spawn(&pid, "/bin/ls", &action, &attr, argv, NULL);
                posix_spawnattr_destroy(&attr);
                posix_spawn_file_actions_destroy(&action);
                close(pipefd[1]);

                if (spawnErr != 0) {
                    close(pipefd[0]);
                    NSLog(@"[RootHide] locateJailbreakRoot: /bin/ls spawn failed: %d", spawnErr);
                }
                else {
                    NSMutableData *outData = [NSMutableData dataWithCapacity:262144];
                    char chunk[8192];
                    ssize_t n;
                    while ((n = read(pipefd[0], chunk, sizeof(chunk))) > 0) {
                        [outData appendBytes:chunk length:(NSUInteger)n];
                        if (outData.length >= 4 * 1024 * 1024) break; // 4 MB hard cap
                    }
                    close(pipefd[0]);
                    int status = 0;
                    if (pid > 0) waitpid(pid, &status, 0);

                    NSString *output = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
                    for (NSString *subItem in [output componentsSeparatedByString:@"\n"]) {
                        NSString *trimmed = [subItem stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                        if (trimmed.length != 24 || ![trimmed hasPrefix:@".jbroot-"]) continue;
                        NSString *jbrandStr = [trimmed substringFromIndex:8];
                        if (checkRootHideJBRAND(jbrandStr)) {
                            randomizedJailbreakPath = [jbrootSearchPath stringByAppendingPathComponent:trimmed];
                            NSLog(@"[RootHide] locateJailbreakRoot: FOUND via /bin/ls: %@", randomizedJailbreakPath);
                            break;
                        }
                    }
                }
            }
        }

        // Legacy migration
        if (!randomizedJailbreakPath) {
            NSLog(@"[RootHide] locateJailbreakRoot: no .jbroot-XXX found, checking legacy /private/preboot");
            NSString *activePrebootPath = [self activePrebootPath];
            for (NSString *subItem in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:activePrebootPath error:nil]) {
                if (subItem.length == 15 && [subItem hasPrefix:@"dopamine-"]) {
                    NSString *legacyPath = [activePrebootPath stringByAppendingPathComponent:subItem];
                    NSString *legacyProcursus = [legacyPath stringByAppendingPathComponent:@"procursus"];
                    if ([[NSFileManager defaultManager] fileExistsAtPath:[legacyProcursus stringByAppendingPathComponent:@".installed_dopamine"]]) {
                        randomizedJailbreakPath = legacyPath;
                        _bootstrapNeedsMigration = YES;
                        NSLog(@"[RootHide] locateJailbreakRoot: found legacy dopamine path: %@", legacyPath);
                        break;
                    }
                }
            }
        }

        if (randomizedJailbreakPath) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:randomizedJailbreakPath]) {
                gSystemInfo.jailbreakInfo.rootPath = strdup(randomizedJailbreakPath.fileSystemRepresentation);
                NSLog(@"[RootHide] locateJailbreakRoot: set rootPath to %s", gSystemInfo.jailbreakInfo.rootPath);
            }
        } else {
            NSLog(@"[RootHide] locateJailbreakRoot: NO existing jbroot found — will create new");
        }
    }
}

- (NSError *)ensureJailbreakRootExists
{
    NSError *error = nil;

    // ROOTHIDE FIX: Clear rootPath and re-scan.
    // locateJailbreakRoot was called in init() BEFORE elevatePrivileges,
    // so it found the legacy /private/preboot path (not .jbroot-XXX).
    // Now that we ARE root, clear rootPath and re-scan so we can find
    // existing .jbroot-XXX via /bin/ls (which needs root for AMFI).
    if (gSystemInfo.jailbreakInfo.rootPath) {
        NSString *oldPath = [NSString stringWithUTF8String:gSystemInfo.jailbreakInfo.rootPath];
        // Only clear if it's the legacy path (contains /private/preboot)
        if ([oldPath containsString:@"/private/preboot/"]) {
            NSLog(@"[RootHide] ensureJailbreakRootExists: clearing legacy rootPath %@ to re-scan", oldPath);
            free(gSystemInfo.jailbreakInfo.rootPath);
            gSystemInfo.jailbreakInfo.rootPath = NULL;
        }
    }

    [self locateJailbreakRoot];

    // DOPACLEAN logic to move a corrupted dopamine directory to a different path to at least make jailbreaking work again
    // if (gSystemInfo.jailbreakInfo.rootPath) {
    //     NSString *randomizedJailbreakPath = [NSString stringWithUTF8String:gSystemInfo.jailbreakInfo.rootPath].stringByDeletingLastPathComponent;
    //     NSString *characterSet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    //     NSUInteger stringLen = 6;
    //     NSMutableString *randomString = [NSMutableString stringWithCapacity:stringLen];
    //     for (NSUInteger i = 0; i < stringLen; i++) {
    //         NSUInteger randomIndex = arc4random_uniform((uint32_t)[characterSet length]);
    //         unichar randomCharacter = [characterSet characterAtIndex:randomIndex];
    //         [randomString appendFormat:@"%C", randomCharacter];
    //     }
    //
    //     NSString *activePrebootPath = [self activePrebootPath];
    //     NSString *orphanedName = [NSString stringWithFormat:@"orphaned-%@", randomString];
    //     NSString *orphanedPath = [activePrebootPath stringByAppendingPathComponent:orphanedName];
    //     [[NSFileManager defaultManager] moveItemAtPath:randomizedJailbreakPath toPath:orphanedPath error:nil];
    // }

    // return [NSError errorWithDomain:@"Cleaned" code:1 userInfo:nil];

    if (!gSystemInfo.jailbreakInfo.rootPath || _bootstrapNeedsMigration) {
        // ROOTHIDE: Create jbroot at /var/containers/Bundle/Application/.jbroot-XXXXXXXXXXXXXXXX
        // This path format is REQUIRED by roothideinit.dylib is_jbroot_name().
        NSString *jbrandStr = generateRootHideJBRAND();
        NSString *randomJailbreakFolderName = [NSString stringWithFormat:@".jbroot-%@", jbrandStr];
        NSString *randomizedJailbreakPath = [@"/var/containers/Bundle/Application" stringByAppendingPathComponent:randomJailbreakFolderName];

        // If migrating from old Dopamine path, delete the old directory.
        if (_bootstrapNeedsMigration) {
            NSString *oldPath = [NSString stringWithUTF8String:gSystemInfo.jailbreakInfo.rootPath];
            NSString *oldDopamineDir = [oldPath stringByDeletingLastPathComponent];
            NSLog(@"[RootHide] Removing old Dopamine bootstrap at %@", oldDopamineDir);
            // ROOTHIDE FIX (remove-jailbreak / migration EPERM): exec_cmd_root
            // spawns /bin/rm with posix_spawnattr_set_persona_np(OVERRIDE, uid 0),
            // which returns EPERM on this fork on both 16.7.x and 17.5.x, so the
            // removal silently no-oped. The app is already uid 0 and unsandboxed
            // at this point, so remove in-process (same approach upstream 3.x
            // uses for /var/jb cleanup).
            if ([[NSFileManager defaultManager] removeItemAtPath:oldDopamineDir error:nil]) {
                NSLog(@"[RootHide] Removed old bootstrap directory in-process");
            }
            else {
                NSLog(@"[RootHide] In-process removal of %@ failed, falling back to /bin/rm", oldDopamineDir);
                exec_cmd("/bin/rm", "-rf", oldDopamineDir.fileSystemRepresentation, NULL);
            }
            free(gSystemInfo.jailbreakInfo.rootPath);
            gSystemInfo.jailbreakInfo.rootPath = NULL;
            _bootstrapNeedsMigration = NO;
        }

        // Create the new .jbroot-XXX directory.
        //
        // ROOTHIDE FIX (persona spawn EPERM): the previous order tried
        // exec_cmd_root("/bin/mkdir", ...) FIRST, but posix_spawn with
        // POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE returns EPERM on this fork on both
        // 16.7.x and 17.5.x, so every jbroot creation actually went through the
        // mkdir(2) fallback anyway. Do the direct syscall first — the app is
        // uid 0 and unsandboxed here — and only try the spawn as a fallback for
        // devices where persona spawning does work.
        const char *path = randomizedJailbreakPath.fileSystemRepresentation;
        NSLog(@"[RootHide] Creating jbroot at %@ via mkdir(2)", randomizedJailbreakPath);
        BOOL jbrootCreated = NO;
        if (mkdir(path, 0755) == 0 || errno == EEXIST) {
            jbrootCreated = YES;
        }
        else {
            NSLog(@"[RootHide] mkdir(2) failed (%s), falling back to /bin/mkdir spawn", strerror(errno));
            int mkdirRet = exec_cmd("/bin/mkdir", "-m", "0755", path, NULL);
            jbrootCreated = (mkdirRet == 0);
        }

        if (!jbrootCreated) {
            error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
                                   userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to create jbroot directory %s: %s", path, strerror(errno)]}];
            NSLog(@"[RootHide] jbroot creation failed for %@", randomizedJailbreakPath);
        }
        else {
            // ROOTHIDE FIX: chown via exec_cmd_root no-oped with EPERM (persona
            // spawn not permitted on this fork); the process is already uid 0,
            // so chown(2) directly. Keep the error visible instead of silent.
            if (chown(path, 0, 0) != 0) {
                NSLog(@"[RootHide] chown(0,0) on %@ failed: %s", randomizedJailbreakPath, strerror(errno));
            }
            NSLog(@"[RootHide] Created jbroot at %@", randomizedJailbreakPath);
            gSystemInfo.jailbreakInfo.rootPath = strdup(randomizedJailbreakPath.UTF8String);

            // ROOTHIDE FIX LỖI 2 (CRITICAL): Tạo .jbroot và rootfs symlinks tại jbroot root
            //
            // Phân tích RootHide Bootstrap gốc (bootstrap-1800.tar):
            //   ./.jbroot  ->  .         (symlink đến chính jbroot)
            //   ./rootfs   ->  /         (symlink đến rootfs thật)
            //   ./dev      ->  /dev       (symlink đến /dev)
            //
            // Mục đích của các symlinks này:
            //   1. `.jbroot -> .` cho phép relative paths hoạt động trong mọi subdir.
            //      Ví dụ: /usr/bin/.jbroot -> ../../.jbroot (relative) → trỏ về jbroot root.
            //      Khi một binary ở /usr/bin/ gọi dlopen("@loader_path/.jbroot/usr/lib/..."),
            //      @loader_path = /usr/bin/, .jbroot = ../../.jbroot = jbroot root, OK.
            //
            //   2. `rootfs -> /` cho phép tweaks truy cập system rootfs thật.
            //      Ví dụ: tweak cần đọc /System/Library/... → jbroot/rootfs/System/Library/...
            //
            //   3. `dev -> /dev` cho phép tạo device nodes.
            //
            // QUAN TRỌNG: RootHide Bootstrap GỐC KHÔNG bind mount /System, /usr!
            // Họ dùng libvroot (virtual rootfs) để intercept system calls thay vì bind mount.
            // Dopamine rootless port sang roothide lại vẫn bind mount /System, /usr, /usr/lib
            // → bị lộ qua getmntinfo() → RootHide app cảnh báo "Unknown Bindfs Mount(s)".
            //
            // FIX tạm thời (không thể remove bind mount vì Dopamine cần chúng):
            //   - Hook getmntinfo/statfs để filter out bind mount entries
            //   - Tạo .jbroot + rootfs symlinks để đảm bảo tương thích RootHide app
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *jbrootDotLink = [randomizedJailbreakPath stringByAppendingPathComponent:@".jbroot"];
            NSString *rootfsLink = [randomizedJailbreakPath stringByAppendingPathComponent:@"rootfs"];
            NSString *devLink = [randomizedJailbreakPath stringByAppendingPathComponent:@"dev"];

            // Remove existing symlinks if any (idempotent)
            [fm removeItemAtPath:jbrootDotLink error:nil];
            [fm removeItemAtPath:rootfsLink error:nil];
            [fm removeItemAtPath:devLink error:nil];

            // Create .jbroot -> . (self-reference, relative)
            // Phải dùng relative path "." chứ không phải absolute path, vì:
            //   - libvroot có thể remove absolute symlinks
            //   - relative path vẫn đúng khi jbroot được rename (re-randomize)
            NSError *linkErr = nil;
            if ([fm createSymbolicLinkAtPath:jbrootDotLink withDestinationPath:@"." error:&linkErr]) {
                NSLog(@"[RootHide] Created .jbroot -> . (self) at %@", jbrootDotLink);
            } else {
                NSLog(@"[RootHide] FAILED to create .jbroot symlink: %@", linkErr);
            }

            // Create rootfs -> / (system rootfs)
            linkErr = nil;
            if ([fm createSymbolicLinkAtPath:rootfsLink withDestinationPath:@"/" error:&linkErr]) {
                NSLog(@"[RootHide] Created rootfs -> / at %@", rootfsLink);
            } else {
                NSLog(@"[RootHide] FAILED to create rootfs symlink: %@", linkErr);
            }

            // Create dev -> /dev
            linkErr = nil;
            if ([fm createSymbolicLinkAtPath:devLink withDestinationPath:@"/dev" error:&linkErr]) {
                NSLog(@"[RootHide] Created dev -> /dev at %@", devLink);
            } else {
                NSLog(@"[RootHide] FAILED to create dev symlink: %@", linkErr);
            }
        }
    }

    return error;
}

- (BOOL)isArm64e
{
    cpu_subtype_t cpusubtype = 0;
    size_t len = sizeof(cpusubtype);
    if (sysctlbyname("hw.cpusubtype", &cpusubtype, &len, NULL, 0) == -1) return NO;
    return (cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E;
}

- (BOOL)isSPTM
{
    if (@available(iOS 17.0, *)) {
        io_registry_entry_t memory_map = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/chosen/memory-map");
        if (memory_map == IO_OBJECT_NULL)   return NO;

        CFArrayRef keys = (CFArrayRef)IORegistryEntryCreateCFProperty(memory_map, CFSTR(kIORegistryEntryPropertyKeysKey), kCFAllocatorDefault, 0);
        IOObjectRelease(memory_map);
        if (!keys)  return NO;

        CFRange range = CFRangeMake(0, CFArrayGetCount(keys));

        bool isSPTM = CFArrayContainsValue(keys, range, CFSTR("SPTM")) && CFArrayContainsValue(keys, range, CFSTR("TXM"));
        CFRelease(keys);

        return isSPTM;
    }
    return false;
}

- (NSString *)versionSupportString
{
    cpu_subtype_t cpuFamily = 0;
    size_t cpuFamilySize = sizeof(cpuFamily);
    sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
    
    if ([self isArm64e]) {
        if (cpuFamily == CPUFAMILY_ARM_VORTEX_TEMPEST || cpuFamily == CPUFAMILY_ARM_LIGHTNING_THUNDER) {
            return @"iOS 15.0 - 18.7.1, 26.0 - 26.0.1 (A12/A13, PPL)";
        }
        else if (![self isSPTM]) {
            return @"iOS 15.0 - 17.3.1 (PPL)";
        }
        else {
            return @"iOS 17.0 - 17.3.1 (SPTM)";
        }
    }
    else {
        return @"iOS 15.0 - 18.7.1 (arm64e)";
    }
}

- (BOOL)isInstalledThroughTrollStore
{
    static BOOL trollstoreInstallation = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* trollStoreMarkerPath = [[[NSBundle mainBundle].bundlePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"_TrollStore"];
        trollstoreInstallation = [[NSFileManager defaultManager] fileExistsAtPath:trollStoreMarkerPath];
    });
    return trollstoreInstallation;
}

- (void)updateJailbreakState
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        char *jbVersionC = NULL;
        _isJailbroken = jbclient_dopamine_is_jailbroken(&jbVersionC);
        if (jbVersionC) {
            _jailbrokenVersion = [NSString stringWithUTF8String:jbVersionC];
            free(jbVersionC);
        }
    });
}

- (BOOL)isJailbroken
{
    [self updateJailbreakState];
    return _isJailbroken;
}

- (void)setJailbroken:(BOOL)jailbroken withVersion:(NSString *)version
{
    _isJailbroken = jailbroken;
    if (_isJailbroken) _jailbrokenVersion = version;
}

- (BOOL)isJailbrokenWithOtherJailbreak
{
    if (![self isJailbroken]) {
        uint32_t csFlags = 0;
        csops(getpid(), CS_OPS_STATUS, &csFlags, sizeof(csFlags));
        
        // Palera1n
        if (csFlags & CS_PLATFORM_BINARY) return YES;
        
        // Older Dopamine build
        if (!access("/usr/lib/systemhook.dylib", F_OK)) return YES;
    }
    return NO;
}

- (NSString *)jailbrokenVersion
{
    [self updateJailbreakState];
    if (!_isJailbroken) return nil;
    return _jailbrokenVersion;
}

- (NSString *)systemVersion
{
    return (__bridge NSString *)MGCopyAnswer((__bridge CFStringRef)@"ProductVersion");
}

- (BOOL)isBootstrapped
{
    return (BOOL)jbinfo(rootPath);
}

// Trả về 0 nếu unsandbox thành công (hoặc không cần thiết), khác 0 nếu KHÔNG
// thể unsandbox. Caller PHẢI kiểm tra: chạy block khi sandboxed là nguyên nhân
// gốc của lỗi "Remove jailbreak failed ... (1)" (EPERM trên mọi unlink trong
// jbroot — app chỉ có extension read+execute trên jbroot thật; phần ghi duy
// nhất là <jbroot>/var/mobile).
//
// FIX REMOVE-JAILBREAK EPERM (Issue 2), 2 lớp:
//  1) Ưu tiên action unsandbox MỚI trong DOPAMINE domain
//     (jbclient_dopamine_set_mac_label): permission check là bundle ID của
//     app, KHÔNG phụ thuộc euid trong audit token. Action cũ
//     (jbclient_root_set_mac_label, ROOT domain) bị deny khi audit token
//     vẫn báo euid 501 vì proc_ro/task_tokens fixup không chạy trên kernel
//     đó — dispatcher deny KHÔNG gửi reply → client nhận NULL → trả -1 mà
//     code cũ BỎ QUA return value và chạy block trong sandbox.
//  2) Kiểm tra return value: nếu cả hai đường đều fail, KHÔNG chạy block
//     một cách mù quáng nữa — trả về mã lỗi để caller báo cho user thay vì
//     để rmrf xả ra EPERM từng file một.
- (int)runUnsandboxed:(void (^)(void))unsandboxBlock
{
    if ([self isInstalledThroughTrollStore]) {
        unsandboxBlock();
        return 0;
    }
    else if ([self isJailbroken]) {
        uint64_t labelBackup = 0;
        int r = jbclient_dopamine_set_mac_label(1, -1, &labelBackup);
        if (r != 0) {
            // Fallback đường cũ (ROOT domain) — cần euid đã được fixup trong
            // audit token; hoạt động trên các kernel có proc_ro task_tokens.
            NSLog(@"[RootHide] runUnsandboxed: dopamine-domain unsandbox failed (%d), trying ROOT domain", r);
            r = jbclient_root_set_mac_label(1, -1, &labelBackup);
        }
        if (r != 0) {
            NSLog(@"[RootHide] runUnsandboxed: FAILED to unsandbox (err %d) — NOT running the block sandboxed", r);
            return r == 0 ? -1 : r;
        }
        unsandboxBlock();
        int restoreR = jbclient_dopamine_set_mac_label(1, labelBackup, NULL);
        if (restoreR != 0) {
            jbclient_root_set_mac_label(1, labelBackup, NULL);
        }
        return 0;
    }
    else {
        // Hope that we are already unsandboxed
        unsandboxBlock();
        return 0;
    }
}

- (void)runAsRoot:(void (^)(void))rootBlock
{
    uint32_t orgUser = geteuid();
    uint32_t orgGroup = getegid();
    
    if (orgUser == 0 && orgGroup == 0) {
        rootBlock();
        return;
    }

    if (self.isJailbroken) {
        if (jbclient_dopamine_get_root() == 0) {
            rootBlock();
            jbclient_dopamine_drop_root();
        }
    }
}

- (int)spawnJbctlAsRootWithArgs:(NSArray *)args
{
    bool needsLegacySolution = false;
    if (self.jailbrokenVersion) {
        needsLegacySolution = (strcmp(self.jailbrokenVersion.UTF8String, "3.0.5") < 0);
    }

    char **argBuf = malloc((args.count + 4) * sizeof(char *));
    argBuf[0] = strdup(JBROOT_PATH("/basebin/uptime_helper"));
    int i = 1;
    for (NSString *arg in args) {
        argBuf[i++] = strdup(arg.UTF8String);
    }

    if (!needsLegacySolution) {
        argBuf[i++] = strdup("--waitfor");
        argBuf[i++] = strdup("3");
    }
    argBuf[i++] = NULL;
    
    posix_spawn_file_actions_t act = NULL;
        posix_spawn_file_actions_init(&act);
    posix_spawnattr_t attr = NULL;
    posix_spawnattr_init(&attr);
     
    int waitPipe[2];
    
    if (!needsLegacySolution) {
        pipe(waitPipe);
        posix_spawn_file_actions_adddup2(&act, waitPipe[0], 3);
    }
    else {
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_START_SUSPENDED);
    }

    __block int pid = 0;
    __block int r = -1;

    // Capture the jbctl path string BEFORE we free argBuf[] below so that
    // if posix_spawn fails we can log which path we tried (the user-reported
    // "app crashes at final step" is almost always posix_spawn returning
    // ENOENT because <jbroot>/basebin/jbctl doesn't exist or is the wrong
    // path; without this log it was impossible to diagnose).
    NSString *jbctlPathForLog = [NSString stringWithUTF8String:argBuf[0]];

    [self runAsRoot:^{
        [self runUnsandboxed:^{
            r = posix_spawn(&pid, argBuf[0], &act, &attr, (char *const *)argBuf, (char *const *)environ);
            if (needsLegacySolution) {
                // Legacy solution is a gamble, which is why it was removed and superseeded by --waitfor
                // But if jailbroken with <3.0.5, jbctl doesn't support --waitfor yet
                kill(pid, SIGCONT);
            }
        }];
        // We *NEED* to leave this block on iOS 17+ to avoid a panic, --waitfor ensures this always happens
    }];

    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&act);
    for (int y = 0; y < i; y++) {
        free(argBuf[y]);
    }
    free(argBuf);

    if (!needsLegacySolution) {
        if (r == 0) {
            // We left the root/unsandbox block, now resume jbctl by writing to pipe
            char w = 'w';
            write(waitPipe[1], &w, sizeof(w));
        }
        else {
            // FIX: posix_spawn FAILED. The previous code silently fell through
            // to `return cmd_wait_for_exit(pid)` with pid == 0 (still its
            // initial value because posix_spawn never overwrote it).
            // `cmd_wait_for_exit(0)` calls `waitpid(0, ...)` which on POSIX
            // means "wait for ANY child in the calling process group" —
            // this blocks forever, and the iOS watchdog eventually kills
            // the app. The user perceives this as "app crashes at the
            // final jailbreak step, no userspace reboot".
            //
            // Common causes of posix_spawn failure here:
            //   ENOENT — <jbroot>/basebin/jbctl doesn't exist (ensureJailbreakRootExists
            //             picked the wrong jbroot path, or bootstrap extraction failed)
            //   EACCES — AMFI rejected the binary (cdhash not in trustcache)
            //   E2BIG  — argv too long (shouldn't happen here)
            NSLog(@"[RootHide] spawnJbctlAsRootWithArgs: posix_spawn FAILED for '%@' (errno=%d: %s)",
                  jbctlPathForLog, r, strerror(r));
            close(waitPipe[0]);
            close(waitPipe[1]);
            return r;
        }

        close(waitPipe[0]);
        close(waitPipe[1]);
    }

    return cmd_wait_for_exit(pid);
}

- (int)runTrollStoreAction:(NSString *)action
{
    if (![self isInstalledThroughTrollStore]) return -1;
    
    uint32_t selfPathSize = PATH_MAX;
    char selfPath[selfPathSize];
    _NSGetExecutablePath(selfPath, &selfPathSize);
    return exec_cmd_root(selfPath, "trollstore", action.UTF8String, NULL);
}

- (void)respring
{
    [self spawnJbctlAsRootWithArgs:@[@"respring"]];
}

- (void)rebootUserspace
{
    // ROOTHIDE FIX LỖI 1 (CRITICAL, v5): REVERT về EXACT official roothide fork
    //
    // EVIDENCE các patch trước FAIL:
    //   - v1: spawnJbctlAsRootWithArgs với --waitfor pipe → race condition, app crash
    //   - v2: direct reboot3 từ app → EPERM (thiếu entitlement)
    //   - v3: jbctl spawn ngay sau Step 1 → apps không cài
    //   - v4: jbctl spawn sau Step 5 → vẫn fail (user báo 'như cũ')
    //
    // ROOT CAUSE: User code tự chế phức tạp. Fork gốc CHÍNH THỨC
    // (github.com/roothide/Dopamine) dùng exec_cmd_suspended + SIGCONT,
    // KHÔNG có --waitfor pipe, KHÔNG có retry loop, KHÔNG có fallback chain.
    //
    // FIX: Copy EXACT rebootUserspace từ fork gốc.
    // Đơn giản: runAsRoot → runUnsandboxed → exec_cmd_suspended(jbctl reboot_userspace)
    // → kill(pid, SIGCONT) → cmd_wait_for_exit(pid)
    [self runAsRoot:^{
        __block int pid = 0;
        // FIX REMOVE-JAILBREAK EPERM follow-up: r phải khởi tạo KHÁC 0 để
        // nếu runUnsandboxed từ chối chạy block (unsandbox fail), ta không
        // rơi vào cmd_wait_for_exit(pid=0) → waitpid(0) chờ mọi child → treo
        // vĩnh viễn (watchdog giết app). Chỉ khi block chạy và spawn thành
        // công thì r mới về 0.
        __block int r = -1;
        [self runUnsandboxed:^{
            r = exec_cmd_suspended(&pid, JBROOT_PATH("/basebin/uptime_helper"), "reboot_userspace", NULL);
            if (r == 0) {
                // the original plan was to have the process continue outside of this block
                // unfortunately sandbox blocks kill aswell, so it's a bit racy but works
                // we assume we leave this unsandbox block before the userspace reboot starts
                // to avoid leaking the label, this seems to work in practice
                // and even if it doesn't work, leaking the label is no big deal
                kill(pid, SIGCONT);
            }
        }];
        if (r == 0) {
            cmd_wait_for_exit(pid);
        } else {
            NSLog(@"[RootHide] rebootUserspace: unsandbox/spawn failed (r=%d) — NOT waiting", r);
        }
    }];
}


- (void)refreshJailbreakApps
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-a", NULL);
        }];
    }];
}

- (void)unregisterJailbreakApps
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSArray *jailbreakApps = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:JBROOT_PATH(@"/Applications") error:nil];
            if (jailbreakApps.count) {
                for (NSString *jailbreakApp in jailbreakApps) {
                    NSString *jailbreakAppPath = [JBROOT_PATH(@"/Applications") stringByAppendingPathComponent:jailbreakApp];
                    exec_cmd(JBROOT_PATH("/usr/bin/uicache"), "-u", jailbreakAppPath.fileSystemRepresentation, NULL);
                }
            }
        }];
    }];
}

- (void)reboot
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            reboot3(0x8000000000000000, 0);
        }];
    }];
}


- (void)changeMobilePassword:(NSString *)newPassword
{
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            // FIX: previously `pw usermod 501 -h 0` was used, but `pw usermod`
            // treats the first positional arg as a USERNAME, not a UID.
            // Looking up user "501" fails with "user '501' disappeared during update".
            // The correct syntax is `pw usermod -u 501 -h 0` (use -u flag for UID).
            //
            // Also escape single quotes in the password to prevent shell injection
            // (the password is passed via printf, so we only need to escape ' for the
            // outer single-quoted dash -c argument).
            NSString *escapedPassword = [newPassword stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
            NSString *dashCommand = [NSString stringWithFormat:@"printf \"%%s\\n\" '%@' | %@ usermod -u 501 -h 0", escapedPassword, JBROOT_PATH(@"/usr/sbin/pw")];
            NSLog(@"[RootHide] changeMobilePassword: running pw usermod -u 501 -h 0");
            int r = exec_cmd(JBROOT_PATH("/usr/bin/dash"), "-c", dashCommand.UTF8String, NULL);
            if (r != 0) {
                NSLog(@"[RootHide] changeMobilePassword: pw returned %d, trying chpasswd fallback", r);
                // FIX: bỏ `su -q passwd root` (su không có option -q trong Procursus,
                // và `echo '...' | su` truyền password vào stdin của su chứ không phải
                // passwd → không work). `|| true` cuối cũng nuốt hết error → user
                // tưởng đổi pass OK nhưng thực ra không.
                // Fallback chỉ dùng `chpasswd` (đúng syntax cho Procursus).
                // Lưu ý: chpasswd nhận input dạng "user:password" trên stdin.
                NSString *fallbackCmd = [NSString stringWithFormat:@"printf 'mobile:%@\\n' | %@ chpasswd 2>&1",
                    escapedPassword,
                    JBROOT_PATH(@"/usr/sbin/chpasswd")];
                int r2 = exec_cmd(JBROOT_PATH("/usr/bin/dash"), "-c", fallbackCmd.UTF8String, NULL);
                if (r2 != 0) {
                    NSLog(@"[RootHide] changeMobilePassword: chpasswd also failed (%d), password NOT changed", r2);
                } else {
                    NSLog(@"[RootHide] changeMobilePassword: chpasswd fallback OK");
                }
            }
        }];
    }];
}

- (NSError*)updateEnvironment
{
    NSString *newBasebinTarPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"basebin.tar"];
    int result = jbclient_platform_stage_jailbreak_update(newBasebinTarPath.fileSystemRepresentation);
    if (result == 0) {
        [self rebootUserspace];
        return nil;
    }
    return [NSError errorWithDomain:@"Dopamine" code:result userInfo:nil];
}

- (void)updateJailbreakFromTIPA:(NSString *)tipaPath
{
    [self spawnJbctlAsRootWithArgs:@[@"update", @"tipa", tipaPath]];
}

- (BOOL)isTweakInjectionEnabled
{
    return ![[NSFileManager defaultManager] fileExistsAtPath:JBROOT_PATH(@"/basebin/.safe_mode")];
}

- (void)setTweakInjectionEnabled:(BOOL)enabled
{
    NSString *safeModePath = JBROOT_PATH(@"/basebin/.safe_mode");
    if ([self isJailbroken]) {
        [self runAsRoot:^{
            [self runUnsandboxed:^{
                if (enabled) {
                    [[NSFileManager defaultManager] removeItemAtPath:safeModePath error:nil];
                }
                else {
                    [[NSData data] writeToFile:safeModePath atomically:YES];
                }
            }];
        }];
    }
}

- (BOOL)isIDownloadEnabled
{
    __block BOOL isEnabled = NO;
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            NSDictionary *disabledDict = [NSDictionary dictionaryWithContentsOfFile:@"/var/db/com.apple.xpc.launchd/disabled.plist"];
            NSNumber *idownloaddDisabledNum = disabledDict[@"com.opa334.Dopamine.idownloadd"];
            if (idownloaddDisabledNum) {
                isEnabled = ![idownloaddDisabledNum boolValue];
            }
            else {
                isEnabled = NO;
            }
        }];
    }];
    return isEnabled;
}

- (void)setIDownloadEnabled:(BOOL)enabled needsUnsandbox:(BOOL)needsUnsandbox
{
    void (^updateBlock)(void) = ^{
        if (enabled) {
            exec_cmd_trusted(JBROOT_PATH("/usr/bin/launchctl"), "enable", "system/com.opa334.Dopamine.idownloadd", NULL);
        }
        else {
            exec_cmd_trusted(JBROOT_PATH("/usr/bin/launchctl"), "disable", "system/com.opa334.Dopamine.idownloadd", NULL);
        }
    };

    if (needsUnsandbox) {
        [self runAsRoot:^{
            [self runUnsandboxed:updateBlock];
        }];
    }
    else {
        updateBlock();
    }
}

- (void)setIDownloadLoaded:(BOOL)loaded needsUnsandbox:(BOOL)needsUnsandbox
{
    if (loaded) {
        [self setIDownloadEnabled:loaded needsUnsandbox:needsUnsandbox];
    }
    
    void (^updateBlock)(void) = ^{
        if (loaded) {
            exec_cmd(JBROOT_PATH("/usr/bin/launchctl"), "load", JBROOT_PATH("/basebin/LaunchDaemons/com.opa334.Dopamine.idownloadd.plist"), NULL);
        }
        else {
            exec_cmd(JBROOT_PATH("/usr/bin/launchctl"), "unload", JBROOT_PATH("/basebin/LaunchDaemons/com.opa334.Dopamine.idownloadd.plist"), NULL);
        }
    };
    
    if (needsUnsandbox) {
        [self runAsRoot:^{
            [self runUnsandboxed:updateBlock];
        }];
    }
    else {
        updateBlock();
    }
    
    if (!loaded) {
        [self setIDownloadEnabled:loaded needsUnsandbox:needsUnsandbox];
    }
}

- (BOOL)isFakelibMounted
{
    struct statfs fsb;
    if (statfs("/usr/lib", &fsb) != 0) return NO;
    return strcmp(fsb.f_mntonname, "/usr/lib") == 0;
}

- (int)setFakelibMounted:(BOOL)mounted
{
    // RootHide port Build 3: the fakelib bindfs mount no longer exists -
    // systemhook and the patched dyld are published into /usr/lib via
    // kernel namecache injection instead (see DOJailbreaker
    // publishFakeLibNoMount). Mounting here would recreate the globally
    // visible bindfs entry ("Unknown Bindfs Mount(s)" detection), so this
    // method is now a no-op kept for API compatibility.
    //
    // Side effect (known limitation): the "hide jailbreak" toggle can no
    // longer disable injection by unmounting - the published namecache
    // entries cannot be removed without a reboot. Blacklisted apps are
    // unaffected (they are spawned clean via isBlacklistedPath).
    NSLog(@"[RootHide] Build 3: setFakelibMounted:%@ is a no-op (namecache publication, no bindfs mount)", mounted ? @"YES" : @"NO");
    return 0;
}

- (int)setPrivatePrebootProtected:(BOOL)protected
{
    NSString *arg = protected ? @"activate" : @"deactivate";
    return [self spawnJbctlAsRootWithArgs:@[@"internal", @"protection", arg]];
}

- (BOOL)isJailbreakHidden
{
    // RootHide does not use /var/jb
    // Check if jbroot is accessible instead
    NSString *jbrootPath = JBROOT_PATH(@"/");
    return ![[NSFileManager defaultManager] fileExistsAtPath:jbrootPath];
}

- (void)setJailbreakHidden:(BOOL)hidden
{
    if (hidden && ![self isJailbroken] && geteuid() != 0) {
        [self runTrollStoreAction:@"hide-jailbreak"];
        return;
    }
    
    void (^actionBlock)(void) = ^{
        BOOL alreadyHidden = [self isJailbreakHidden];
        if (hidden != alreadyHidden) {
            if (hidden) {
                if ([self isJailbroken]) {
                    [self unregisterJailbreakApps];
                    [self setPrivatePrebootProtected:NO];
                    [self setFakelibMounted:NO];
                    jbclient_platform_set_systemwide_domain_enabled(false);
                }
                // RootHide: Remove /var/jb if it exists (leftover from other JBs)
                [[NSFileManager defaultManager] removeItemAtPath:@"/var/jb" error:nil];
            }
            else {
                // RootHide: Do NOT create /var/jb symlink - uses randomized jbroot only
                if ([self isJailbroken]) {
                    jbclient_platform_set_systemwide_domain_enabled(true);
                    [self setFakelibMounted:YES];
                    [self setPrivatePrebootProtected:YES];
                    [self refreshJailbreakApps];
                }
            }
        }
    };
    
    if ([self isJailbroken]) {
        [self runAsRoot:^{
            [self runUnsandboxed:actionBlock];
        }];
    }
    else {
        actionBlock();
    }
}

- (NSString *)accessibleKernelPath
{
    if ([self isInstalledThroughTrollStore] || getuid() == 0) {
        NSString *kernelcachePath = [[self activePrebootPath] stringByAppendingPathComponent:@"System/Library/Caches/com.apple.kernelcaches/kernelcache"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:kernelcachePath]) {
            return kernelcachePath;
        }
        return @"/System/Library/Caches/com.apple.kernelcaches/kernelcache";
    }
    else {
        NSString *kernelInApp = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"kernelcache"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:kernelInApp]) {
            return kernelInApp;
        }
        
        [[DOUIManager sharedInstance] sendLog:@"Downloading Kernel" debug:NO];
        NSString *kernelcachePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/kernelcache"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:kernelcachePath]) {
            if (grab_images([NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]) == false) return nil;
        }
        return kernelcachePath;
    }
}

- (NSString *)accessibleSPTMPath
{
    NSString *sptmInAppPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"sptm.img4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:sptmInAppPath]) {
        return sptmInAppPath;
    }
    
    NSString *sptmInDocsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/sptm.img4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:sptmInDocsPath]) {
        return sptmInDocsPath;
    }
    
    sptmInDocsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/sptm.im4p"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:sptmInDocsPath]) {
        return sptmInDocsPath;
    }

    if ([self isInstalledThroughTrollStore] || getuid() == 0) {
        NSString *sptmPath = [[self activePrebootPath] stringByAppendingPathComponent:@"/usr/standalone/firmware/FUD/Ap,SecurePageTableMonitor.img4"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:sptmPath]) {
            return sptmPath;
        }
    }

    return nil;
}

- (NSString *)accessibleTXMPath
{
    NSString *txmInAppPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"txm.img4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:txmInAppPath]) {
        return txmInAppPath;
    }
    
    NSString *txmInDocsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/txm.img4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:txmInDocsPath]) {
        return txmInDocsPath;
    }
    
    txmInDocsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/txm.im4p"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:txmInDocsPath]) {
        return txmInDocsPath;
    }

    if ([self isInstalledThroughTrollStore] || getuid() == 0) {
        NSString *txmPath = [[self activePrebootPath] stringByAppendingPathComponent:@"/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:txmPath]) {
            return txmPath;
        }
    }

    return nil;
}


- (BOOL)isPACBypassRequired
{
    if (![self isArm64e]) return NO;
    
    if (@available(iOS 15.2, *)) {
        return NO;
    }
    return YES;
}

- (BOOL)isPPLBypassRequired
{
    return [self isArm64e];
}

- (BOOL)isSupported
{
    //cpu_subtype_t cpuFamily = 0;
    //size_t cpuFamilySize = sizeof(cpuFamily);
    //sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
    //if (cpuFamily == CPUFAMILY_ARM_TYPHOON) return false; // A8X is unsupported for now (due to 4k page size)
    
    DOExploitManager *exploitManager = [DOExploitManager sharedManager];
    if ([exploitManager availableExploitsForType:EXPLOIT_TYPE_KERNEL].count) {
        if (![self isPACBypassRequired] || [exploitManager availableExploitsForType:EXPLOIT_TYPE_PAC].count) {
            if (![self isPPLBypassRequired] || [exploitManager availableExploitsForType:EXPLOIT_TYPE_PPL].count) {
                return true;
            }
        }
    }
    
    return false;
}

- (BOOL)deviceSupportsFaceID
{
    if (![LAContext class]) return NO;

    LAContext *myContext = [[LAContext alloc] init];
    NSError *authError = nil;
    if (![myContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&authError]) {
        NSLog(@"%@", [authError localizedDescription]);
        return NO;
    }

    return myContext.biometryType == LABiometryTypeFaceID;
}

- (BOOL)deviceSupportsLandscapeBootLogo
{
    struct utsname u;
    uname(&u);
    const char *ipadString = "iPad";

    bool isPad = strncmp(u.machine, ipadString, strlen(ipadString)) == 0;
    return isPad && [self deviceSupportsFaceID];
}

- (NSError *)prepareBootstrap
{
    __block NSError *errOut;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [_bootstrapper prepareBootstrapWithCompletion:^(NSError *error) {
        errOut = error;
        dispatch_semaphore_signal(sema);
    }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return errOut;
}

- (NSError *)finalizeBootstrap
{
    return [_bootstrapper finalizeBootstrap];
}

- (NSError *)deleteBootstrap
{
    if (![self isJailbroken] && getuid() != 0) {
        int r = [self runTrollStoreAction:@"delete-bootstrap"];
        if (r != 0) {
            // TODO: maybe handle error
        }
        return nil;
    }
    else if ([self isJailbroken]) {
        // FIX 2 lỗi trong 1 (vấn đề gỡ jailbreak khi đang jailbroken):
        //
        // (a) `__block NSError *error` trước đây KHÔNG được khởi tạo. Nếu
        //     runAsRoot bỏ qua block (get_root != 0) hoặc runUnsandboxed từ
        //     chối chạy block (xem dưới), `return error` trả về JUNK POINTER
        //     → crash ngẫu nhiên hoặc error rác trong UI.
        // (b) rmrf trước đây chạy cả khi unsandbox THẤT BẠI (runUnsandboxed
        //     cũ bỏ qua return value) → app vẫn sandboxed, extension duy nhất
        //     trên jbroot thật là read+execute → mọi unlink/rmdir EPERM(1).
        //     Đây chính xác là lỗi trong ảnh: "rm /var/containers/Bundle/
        //     Application/.jbroot-XXXX (1)". Giờ runUnsandboxed trả int và
        //     KHÔNG chạy block khi không unsandbox được — phải truyền lỗi đó
        //     ra ngoài để UI hiển thị lý do thật thay vì EPERM từng file.
        __block NSError *error = nil;
        __block int unsandboxErr = 0;
        __block BOOL blockRan = NO;
        [self runAsRoot:^{
            unsandboxErr = [self runUnsandboxed:^{
                blockRan = YES;
                error = [self->_bootstrapper deleteBootstrap];
            }];
        }];
        if (!blockRan) {
            // runAsRoot đã bỏ qua block (get_root != 0 và geteuid() != 0)
            // → KHÔNG có gì bị xóa. Báo lỗi rõ ràng thay vì return nil ("thành công").
            error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EPERM
                                    userInfo:@{NSLocalizedDescriptionKey:@"Failed to elevate privileges to root (jbserver get_root refused) — the jailbreak files were left in place. Try respringing or rebooting userspace, then remove again."}];
        }
        else if (unsandboxErr != 0 && !error) {
            error = [NSError errorWithDomain:NSPOSIXErrorDomain code:unsandboxErr
                                    userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Failed to unsandbox the app (error %d) — the jailbreak files were left in place on purpose. Try respringing or rebooting userspace, then remove again.", unsandboxErr]}];
        }
        return error;
    }
    else {
        // Let's hope for the best
        return [_bootstrapper deleteBootstrap];
    }
}

- (NSError *)reinstallPackageManagers
{
    // FIX (đồng bộ với deleteBootstrap): khởi tạo error = nil để không bao giờ
    // trả về junk pointer; nếu unsandbox fail, block không chạy → trả về
    // lỗi mô tả thay vì nil im lặng.
    __block NSError *error = nil;
    __block BOOL blockRan = NO;
    [self runAsRoot:^{
        [self runUnsandboxed:^{
            blockRan = YES;
            error = [self->_bootstrapper installPackageManagers];
        }];
    }];
    if (!blockRan) {
        error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EPERM
                                userInfo:@{NSLocalizedDescriptionKey:@"Failed to elevate/unsandbox to reinstall package managers. Try respringing or rebooting userspace, then try again."}];
    }
    return error;
}

- (NSError *)updateBootLogo
{
    const char *bootLogoPath = JBROOT_PATH("/basebin/bootlogo.jp2");
    if ([[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"bootlogoEnabled" fallback:YES]) {
        UIImage *bootLogoImage;

        if ([[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"customBootlogoEnabled" fallback:NO]) {
            bootLogoImage = [NSClassFromString(@"UIImage") imageWithContentsOfFile:[DOUIManager sharedInstance].bootlogoPath];
        }

        if (!bootLogoImage) {
            bootLogoImage = [[DOUIManager sharedInstance] renderBootLogo];
        }

        [self runAsRoot:^{
            [self runUnsandboxed:^{
                unlink(bootLogoPath);
                [[bootLogoImage jp2DataWithCompressionQuality:0.9] writeToFile:[NSString stringWithUTF8String:bootLogoPath] atomically:NO];
            }];
        }];

        return nil;
    }
    else {
        [self runAsRoot:^{
            [self runUnsandboxed:^{
                unlink(bootLogoPath);
            }];
        }];
        return nil;
    }
}

@end
