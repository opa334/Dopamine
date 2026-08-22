//
//  Bootstrapper.m
//  Dopamine
//
//  Created by Lars Fröder on 09.01.24.
//

#import "DOBootstrapper.h"
#import "DOBootstrapper+zstd.h"
#import "DOEnvironmentManager.h"
#import "DOUIManager.h"
#import <libjailbreak/info.h>
#import <libjailbreak/util.h>
#import <libjailbreak/jbclient_xpc.h>
#import <sys/mount.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import "NSString+Version.h"

#define LIBKRW_DOPAMINE_BUNDLED_VERSION @"2.0.3"
#define LIBROOT_DOPAMINE_BUNDLED_VERSION @"1.0.1"
#define BASEBIN_LINK_BUNDLED_VERSION @"1.0.0"
#define LAUNCHCTL_BUNDLED_VERSION @"1:1.2.0"

static NSDictionary *gBundledPackages = @{
    @"libkrw0-dopamine" : LIBKRW_DOPAMINE_BUNDLED_VERSION,
    @"libroot-dopamine" : LIBROOT_DOPAMINE_BUNDLED_VERSION,
    @"dopamine-basebin-link" : BASEBIN_LINK_BUNDLED_VERSION,
    @"launchctl" : LAUNCHCTL_BUNDLED_VERSION,
};

struct hfs_mount_args {
    char    *fspec;
    uid_t    hfs_uid;        /* uid that owns hfs files (standard HFS only) */
    gid_t    hfs_gid;        /* gid that owns hfs files (standard HFS only) */
    mode_t    hfs_mask;        /* mask to be applied for hfs perms  (standard HFS only) */
    uint32_t hfs_encoding;        /* encoding for this volume (standard HFS only) */
    struct    timezone hfs_timezone;    /* user time zone info (standard HFS only) */
    int        flags;            /* mounting flags, see below */
    int     journal_tbuffer_size;   /* size in bytes of the journal transaction buffer */
    int        journal_flags;          /* flags to pass to journal_open/create */
    int        journal_disable;        /* don't use journaling (potentially dangerous) */
};

NSString *const bootstrapErrorDomain = @"BootstrapErrorDomain";

@implementation DOBootstrapper

- (instancetype)init
{
    self = [super init];
    if (self) {
        /*NSURLSessionConfiguration *config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"com.opa334.bootstrapper.background-session"];
        _urlSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];*/
    }
    return self;
}

- (NSError *)extractTar:(NSString *)tarPath toPath:(NSString *)destinationPath
{
    int r = libarchive_unarchive(tarPath.fileSystemRepresentation, destinationPath.fileSystemRepresentation);
    if (r != 0) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedExtracting userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"libarchive returned %d", r]}];
    }
    return nil;
}

- (BOOL)deleteSymlinkAtPath:(NSString *)path error:(NSError **)error
{
    NSDictionary<NSFileAttributeKey, id> *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:error];
    if (!attributes) return YES;
    if (attributes[NSFileType] == NSFileTypeSymbolicLink) {
        return [[NSFileManager defaultManager] removeItemAtPath:path error:error];
    }
    return NO;
}

- (BOOL)fileOrSymlinkExistsAtPath:(NSString *)path
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return YES;
    
    NSDictionary<NSFileAttributeKey, id> *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (attributes) {
        if (attributes[NSFileType] == NSFileTypeSymbolicLink) {
            return YES;
        }
    }
    
    return NO;
}

- (NSError *)createSymlinkAtPath:(NSString *)path toPath:(NSString *)destinationPath createIntermediateDirectories:(BOOL)createIntermediate
{
    NSError *error;
    NSString *parentPath = [path stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:parentPath]) {
        if (!createIntermediate) return [NSError errorWithDomain:bootstrapErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed create %@->%@ symlink: Parent dir does not exists", path, destinationPath]}];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:parentPath withIntermediateDirectories:YES attributes:nil error:&error]) return error;
    }
    
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:path withDestinationPath:destinationPath error:&error];
    return error;
}

- (BOOL)isPrivatePrebootMountedWritable
{
    struct statfs ppStfs;
    statfs([[DOEnvironmentManager sharedManager] privatePrebootPath].fileSystemRepresentation, &ppStfs);
    return !(ppStfs.f_flags & MNT_RDONLY);
}

- (int)remountPrivatePrebootWritable:(BOOL)writable
{
    const char *ppPath = [[DOEnvironmentManager sharedManager] privatePrebootPath].fileSystemRepresentation;

    struct statfs ppStfs;
    int r = statfs(ppPath, &ppStfs);
    if (r != 0) return r;
    
    uint32_t flags = MNT_UPDATE;
    if (!writable) {
        flags |= MNT_RDONLY;
    }
    struct hfs_mount_args mntargs =
    {
        .fspec = ppStfs.f_mntfromname,
        .hfs_mask = 0,
    };
    return mount("apfs", ppPath, flags, &mntargs);
}

- (NSError *)ensurePrivatePrebootIsWritable
{
    if (![self isPrivatePrebootMountedWritable]) {
        int r = [self remountPrivatePrebootWritable:YES];
        if (r != 0) {
            return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedRemount userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Remounting /private/preboot as writable failed with error: %s", strerror(errno)]}];
        }
    }
    return nil;
}

- (void)fixupPathPermissions
{
    // Ensure the following paths are owned by root:wheel and have permissions of 755:
    // /private
    // /private/preboot
    // /private/preboot/UUID
    // /private/preboot/UUID/dopamine-<UUID>
    // /private/preboot/UUID/dopamine-<UUID>/procursus

    NSString *tmpPath = JBROOT_PATH(@"/");
    while (![tmpPath isEqualToString:@"/"]) {
        struct stat s;
        stat(tmpPath.fileSystemRepresentation, &s);
        if (s.st_uid != 0 || s.st_gid != 0) {
            chown(tmpPath.fileSystemRepresentation, 0, 0);
        }
        if ((s.st_mode & S_IRWXU) != 0755) {
            chmod(tmpPath.fileSystemRepresentation, 0755);
        }
        tmpPath = [tmpPath stringByDeletingLastPathComponent];
    }
}

- (void)patchBasebinDaemonPlist:(NSString *)plistPath
{
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

- (void)patchBasebinDaemonPlists
{
    NSURL *basebinDaemonsURL = [NSURL fileURLWithPath:JBROOT_PATH(@"/basebin/LaunchDaemons")];
    for (NSURL *basebinDaemonURL in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:basebinDaemonsURL includingPropertiesForKeys:nil options:0 error:nil]) {
        [self patchBasebinDaemonPlist:basebinDaemonURL.path];
    }
}

- (NSString *)bootstrapVersion
{
    uint64_t cfver = (((uint64_t)kCFCoreFoundationVersionNumber / 100) * 100);
    if (cfver >= 2000) {
        return @"1900";
    }
    return [NSString stringWithFormat:@"%llu", cfver];
}

- (NSURL *)bootstrapURL
{
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://apt.procurs.us/bootstraps/%@/bootstrap-ssh-iphoneos-arm64.tar.zst", [self bootstrapVersion]]];
}

/*- (void)downloadBootstrapWithCompletion:(void (^)(NSString *path, NSError *error))completion
{
    NSURL *bootstrapURL = [self bootstrapURL];
    if (!bootstrapURL) {
        completion(nil, [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedToGetURL userInfo:@{NSLocalizedDescriptionKey : @"Failed to obtain bootstrap URL"}]);
        return;
    }
    
    _downloadCompletionBlock = ^(NSURL * _Nullable location, NSError * _Nullable error) {
        NSError *ourError;
        if (error) {
            ourError = [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedToDownload userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to download bootstrap: %@", error.localizedDescription]}];
        }
        completion(location.path, ourError);
    };
    
    _bootstrapDownloadTask = [_urlSession downloadTaskWithURL:bootstrapURL];
    [_bootstrapDownloadTask resume];
}*/

- (void)extractBootstrap:(NSString *)path withCompletion:(void (^)(NSError *))completion
{
    NSString *bootstrapTar = [@"/var/tmp" stringByAppendingPathComponent:@"bootstrap.tar"];
    NSError *decompressionError = [self decompressZstd:path toTar:bootstrapTar];
    if (decompressionError) {
        completion(decompressionError);
        return;
    }
    
    decompressionError = [self extractTar:bootstrapTar toPath:@"/"];
    if (decompressionError) {
        completion(decompressionError);
        return;
    }
    
    [[NSData data] writeToFile:JBROOT_PATH(@"/.installed_dopamine") atomically:YES];
    completion(nil);
}

#if 0 /* replaced by RootHide category */
- (NSError *)updateVarJbSymlink
{
    // Remove /var/jb as it might be wrong
    NSError *error;
    if (![self deleteSymlinkAtPath:@"/var/jb" error:&error]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
            if (![[NSFileManager defaultManager] removeItemAtPath:@"/var/jb" error:&error]) {
                return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedReplacing userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Removing /var/jb directory failed with error: %@", error]}];
            }
        }
        else {
            return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedReplacing userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Removing /var/jb symlink failed with error: %@", error]}];
        }
    }

    return [self createSymlinkAtPath:@"/var/jb" toPath:JBROOT_PATH(@"/") createIntermediateDirectories:YES];;
}
#endif

#if 0 /* replaced by RootHide category */
- (void)prepareBootstrapWithCompletion:(void (^)(NSError *))completion
{
    [[DOUIManager sharedInstance] sendLog:@"Updating BaseBin" debug:NO];

    // Ensure /private/preboot is mounted writable (Not writable by default on iOS <=15)
    NSError *error = [self ensurePrivatePrebootIsWritable];
    if (error) {
        completion(error);
        return;
    }
    
    [self fixupPathPermissions];
    
    // Clean up xinaA15 v1 leftovers if desired
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/.keep_symlinks"]) {
        NSArray *xinaLeftoverSymlinks = @[
            @"/var/alternatives",
            @"/var/ap",
            @"/var/apt",
            @"/var/bin",
            @"/var/bzip2",
            @"/var/cache",
            @"/var/dpkg",
            @"/var/etc",
            @"/var/gzip",
            @"/var/lib",
            @"/var/Lib",
            @"/var/libexec",
            @"/var/Library",
            @"/var/LIY",
            @"/var/Liy",
            @"/var/local",
            @"/var/newuser",
            @"/var/profile",
            @"/var/sbin",
            @"/var/suid_profile",
            @"/var/sh",
            @"/var/sy",
            @"/var/share",
            @"/var/ssh",
            @"/var/sudo_logsrvd.conf",
            @"/var/suid_profile",
            @"/var/sy",
            @"/var/usr",
            @"/var/zlogin",
            @"/var/zlogout",
            @"/var/zprofile",
            @"/var/zshenv",
            @"/var/zshrc",
            @"/var/log/dpkg",
            @"/var/log/apt",
        ];
        NSArray *xinaLeftoverFiles = @[
            @"/var/lib",
            @"/var/master.passwd"
        ];
        
        for (NSString *xinaLeftoverSymlink in xinaLeftoverSymlinks) {
            [self deleteSymlinkAtPath:xinaLeftoverSymlink error:nil];
        }
        
        for (NSString *xinaLeftoverFile in xinaLeftoverFiles) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:xinaLeftoverFile]) {
                [[NSFileManager defaultManager] removeItemAtPath:xinaLeftoverFile error:nil];
            }
        }
    }
    
    NSString *basebinPath = JBROOT_PATH(@"/basebin");
    NSString *installedPath = JBROOT_PATH(@"/.installed_dopamine");
    error = [self updateVarJbSymlink];
    if (error) {
        completion(error);
        return;
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:basebinPath]) {
        if (![[NSFileManager defaultManager] removeItemAtPath:basebinPath error:&error]) {
            BOOL recovered = NO;

            NSString *corruptedFilePath = JBROOT_PATH(@"/basebin/gen/dyld.old");
            if ([[NSFileManager defaultManager] fileExistsAtPath:corruptedFilePath]) {
                if (![[NSFileManager defaultManager] removeItemAtPath:corruptedFilePath error:nil]) {
                    // Try to recover from file system corruption
                    // In Dopamine 3.0 - 3.0.6 there was an OOB kwritebuf in jbupdate that could cause a panic
                    // This would sometimes leave /var/jb/basebin/gen/dyld.old behind in a corrupted state
                    // We cannot delete this file unfortunately, but we can move it

                    NSString *activePrebootPath = [[DOEnvironmentManager sharedManager] activePrebootPath];

                    NSString *characterSet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
                    NSUInteger stringLen = 6;
                    NSMutableString *randomString = [NSMutableString stringWithCapacity:stringLen];
                    for (NSUInteger i = 0; i < stringLen; i++) {
                        NSUInteger randomIndex = arc4random_uniform((uint32_t)[characterSet length]);
                        unichar randomCharacter = [characterSet characterAtIndex:randomIndex];
                        [randomString appendFormat:@"%C", randomCharacter];
                    }

                    NSString *orphanedName = [NSString stringWithFormat:@"orphaned-%@", randomString];
                    NSString *orphanedPath = [activePrebootPath stringByAppendingPathComponent:orphanedName];
                    [[NSFileManager defaultManager] moveItemAtPath:corruptedFilePath toPath:orphanedPath error:nil];

                    if ([[NSFileManager defaultManager] removeItemAtPath:basebinPath error:&error]) {
                        // If now that the file is moved, we can remove the basebin dir, consider the issue solved
                        recovered = YES;
                        error = nil;
                    }
                }
            }

            if (!recovered) {
                completion([NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedExtracting userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed deleting existing basebin file with error: %@", error.localizedDescription]}]);
                return;
            }
        }
    }
    error = [self extractTar:[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"basebin.tar"] toPath:JBROOT_PATH(@"/")];
    if (error) {
        completion(error);
        return;
    }
    [self patchBasebinDaemonPlists];
    
    void (^bootstrapFinishedCompletion)(NSError *) = ^(NSError *error){
        if (error) {
            completion(error);
            return;
        }
        
        NSString *defaultSources = @"Types: deb\n"
            @"URIs: https://repo.chariz.com/\n"
            @"Suites: ./\n"
            @"Components:\n"
            @"\n"
            @"Types: deb\n"
            @"URIs: https://havoc.app/\n"
            @"Suites: ./\n"
            @"Components:\n"
            @"\n"
            @"Types: deb\n"
            @"URIs: http://apt.thebigboss.org/repofiles/cydia/\n"
            @"Suites: stable\n"
            @"Components: main\n"
            @"\n"
            @"Types: deb\n"
            @"URIs: https://ellekit.space/\n"
            @"Suites: ./\n"
            @"Components:\n";
        [defaultSources writeToFile:JBROOT_PATH(@"/etc/apt/sources.list.d/default.sources") atomically:NO encoding:NSUTF8StringEncoding error:nil];
        
        NSString *mobilePreferencesPath = JBROOT_PATH(@"/var/mobile/Library/Preferences");
        if (![[NSFileManager defaultManager] fileExistsAtPath:mobilePreferencesPath]) {
            NSDictionary<NSFileAttributeKey, id> *attributes = @{
                NSFilePosixPermissions : @0755,
                NSFileOwnerAccountID : @501,
                NSFileGroupOwnerAccountID : @501,
            };
            [[NSFileManager defaultManager] createDirectoryAtPath:mobilePreferencesPath withIntermediateDirectories:YES attributes:attributes error:nil];
        }
        
        JBFixMobilePermissions();

        completion(nil);
    };
    
    
    BOOL needsBootstrap = ![[NSFileManager defaultManager] fileExistsAtPath:installedPath];
    if (needsBootstrap) {
        // First, wipe any existing content that's not basebin
        for (NSURL *subItemURL in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:JBROOT_PATH(@"/")] includingPropertiesForKeys:nil options:0 error:nil]) {
            if (![subItemURL.lastPathComponent isEqualToString:@"basebin"]) {
                [[NSFileManager defaultManager] removeItemAtURL:subItemURL error:nil];
            }
        }
        
        /*void (^bootstrapDownloadCompletion)(NSString *, NSError *) = ^(NSString *path, NSError *error) {
            if (error) {
                completion(error);
                return;
            }
            [self extractBootstrap:path withCompletion:bootstrapFinishedCompletion];
        };*/
        
        [[DOUIManager sharedInstance] sendLog:@"Extracting Bootstrap" debug:NO];

        NSString *bootstrapZstdPath = [NSString stringWithFormat:@"%@/bootstrap_%@.tar.zst", [NSBundle mainBundle].bundlePath, [self bootstrapVersion]];
        [self extractBootstrap:bootstrapZstdPath withCompletion:bootstrapFinishedCompletion];

        /*NSString *documentsCandidate = @"/var/mobile/Documents/bootstrap.tar.zstd";
        NSString *bundleCandidate = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"bootstrap.tar.zstd"];
        // Check if the user provided a bootstrap
        if ([[NSFileManager defaultManager] fileExistsAtPath:documentsCandidate]) {
            bootstrapDownloadCompletion(documentsCandidate, nil);
        }
        else if ([[NSFileManager defaultManager] fileExistsAtPath:bundleCandidate]) {
            bootstrapDownloadCompletion(bundleCandidate, nil);
        }
        else {
            [[DOUIManager sharedInstance] sendLog:@"Downloading Bootstrap" debug:NO];
            [self downloadBootstrapWithCompletion:bootstrapDownloadCompletion];
        }*/
    }
    else {
        bootstrapFinishedCompletion(nil);
    }
}
#endif

- (int)installPackage:(NSString *)packagePath
{
    if (getuid() == 0) {
        return exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"), "-i", packagePath.fileSystemRepresentation, NULL);
    }
    else {
        // idk why but waitpid sometimes fails and this returns -1, so we just ignore the return value
        exec_cmd(JBROOT_PATH("/basebin/jbctl"), "internal", "install_pkg", packagePath.fileSystemRepresentation, NULL);
        return 0;
    }
}

- (int)uninstallPackageWithIdentifier:(NSString *)identifier
{
    return exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"), "-r", identifier.UTF8String, NULL);
}

- (NSString *)installedVersionForPackageWithIdentifier:(NSString *)identifier
{
    NSString *dpkgStatus = [NSString stringWithContentsOfFile:JBROOT_PATH(@"/var/lib/dpkg/status") encoding:NSUTF8StringEncoding error:nil];
    NSString *packageStartLine = [NSString stringWithFormat:@"Package: %@", identifier];
    
    NSArray *packageInfos = [dpkgStatus componentsSeparatedByString:@"\n\n"];
    for (NSString *packageInfo in packageInfos) {
        if ([packageInfo hasPrefix:packageStartLine]) {
            __block NSString *version = nil;
            [packageInfo enumerateLinesUsingBlock:^(NSString * _Nonnull line, BOOL * _Nonnull stop) {
                if ([line hasPrefix:@"Version: "]) {
                    version = [line substringFromIndex:9];
                }
            }];
            return version;
        }
    }
    return nil;
}

- (NSError *)installPackageManagers
{
    NSArray *enabledPackageManagers = [[DOUIManager sharedInstance] enabledPackageManagers];
    for (NSDictionary *packageManagerDict in enabledPackageManagers) {
        NSString *path = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:packageManagerDict[@"Package"]];
        NSString *name = packageManagerDict[@"Display Name"];
        int r = [self installPackage:path];
        if (r != 0) {
            return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to install %@: %d\n", name, r]}];
        }
    }
    return nil;
}

- (BOOL)shouldInstallPackage:(NSString *)identifier
{
    NSString *bundledVersion = gBundledPackages[identifier];
    if (!bundledVersion) return NO;
    
    NSString *installedVersion = [self installedVersionForPackageWithIdentifier:identifier];
    if (!installedVersion) return YES;
    
    return [installedVersion numericalVersionRepresentation] < [bundledVersion numericalVersionRepresentation];
}

#if 0 /* replaced by RootHide category */
- (NSError *)finalizeBootstrap
{
    // Initial setup on first jailbreak
    if ([[NSFileManager defaultManager] fileExistsAtPath:JBROOT_PATH(@"/prep_bootstrap.sh")]) {
        [[DOUIManager sharedInstance] sendLog:@"Finalizing Bootstrap" debug:NO];
        int r = exec_cmd_trusted(JBROOT_PATH("/bin/sh"), JBROOT_PATH("/prep_bootstrap.sh"), NULL);
        if (r != 0) {
            return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"prep_bootstrap.sh returned %d\n", r]}];
        }
        
        NSError *error = [self installPackageManagers];
        if (error) return error;
    }
    
    BOOL shouldInstallLibroot = [self shouldInstallPackage:@"libroot-dopamine"];
    BOOL shouldInstallLibkrw = [self shouldInstallPackage:@"libkrw0-dopamine"];
    BOOL shouldInstallBasebinLink = [self shouldInstallPackage:@"dopamine-basebin-link"];
    BOOL shouldInstallLaunchctl = NO;
    if (__builtin_available(iOS 19.0, *)) {
        shouldInstallLaunchctl = [self shouldInstallPackage:@"launchctl"];
    }
    
    if (shouldInstallLibroot || shouldInstallLibkrw || shouldInstallBasebinLink || shouldInstallLaunchctl) {
        [[DOUIManager sharedInstance] sendLog:@"Updating Bundled Packages" debug:NO];

        if (shouldInstallLaunchctl) {
            NSString *launchctlPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"launchctl_1_1.2.0_iphoneos-arm64.deb"];
            int r = [self installPackage:launchctlPath];
            if (r != 0) return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to install launchctl: %d\n", r]}];
        }

        if (shouldInstallLibroot) {
            NSString *librootPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"libroot.deb"];
            int r = [self installPackage:librootPath];
            if (r != 0) return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to install libroot: %d\n", r]}];
        }
        
        if (shouldInstallLibkrw) {
            NSString *libkrwPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"libkrw-dopamine.deb"];
            int r = [self installPackage:libkrwPath];
            if (r != 0) return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to install the libkrw plugin: %d\n", r]}];
        }
        
        if (shouldInstallBasebinLink) {
            // Clean symlinks from earlier Dopamine versions
            if ([self fileOrSymlinkExistsAtPath:JBROOT_PATH(@"/usr/bin/opainject")]) {
                [[NSFileManager defaultManager] removeItemAtPath:JBROOT_PATH(@"/usr/bin/opainject") error:nil];
            }
            if ([self fileOrSymlinkExistsAtPath:JBROOT_PATH(@"/usr/bin/jbctl")]) {
                [[NSFileManager defaultManager] removeItemAtPath:JBROOT_PATH(@"/usr/bin/jbctl") error:nil];
            }
            if ([self fileOrSymlinkExistsAtPath:JBROOT_PATH(@"/usr/lib/libjailbreak.dylib")]) {
                [[NSFileManager defaultManager] removeItemAtPath:JBROOT_PATH(@"/usr/lib/libjailbreak.dylib") error:nil];
            }
            if ([self fileOrSymlinkExistsAtPath:JBROOT_PATH(@"/usr/bin/libjailbreak.dylib")]) {
                // Yes this exists >.< was a typo
                [[NSFileManager defaultManager] removeItemAtPath:JBROOT_PATH(@"/usr/bin/libjailbreak.dylib") error:nil];
            }
            
            NSString *basebinLinkPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"basebin-link.deb"];
            int r = [self installPackage:basebinLinkPath];
            if (r != 0) return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to install basebin link: %d\n", r]}];
        }
    }

    return nil;
}
#endif

#if 0 /* replaced by RootHide category */
- (NSError *)deleteBootstrap
{
    NSError *error = [self ensurePrivatePrebootIsWritable];
    if (error) return error;
    NSString *path = [[NSString stringWithUTF8String:gSystemInfo.jailbreakInfo.rootPath] stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
    if (error) return error;
    [[NSFileManager defaultManager] removeItemAtPath:@"/var/jb" error:nil];
    return error;
}
#endif

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    if (downloadTask == _bootstrapDownloadTask) {
        NSString *sizeString = [NSByteCountFormatter stringFromByteCount:totalBytesWritten countStyle:NSByteCountFormatterCountStyleFile];
        NSString *writtenBytesString = [NSByteCountFormatter stringFromByteCount:totalBytesExpectedToWrite countStyle:NSByteCountFormatterCountStyleFile];
        
        [[DOUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"Downloading Bootstrap (%@/%@)", sizeString, writtenBytesString] debug:NO update:YES];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    _downloadCompletionBlock(nil, error);
}

- (void)URLSession:(nonnull NSURLSession *)session downloadTask:(nonnull NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(nonnull NSURL *)location
{
    _downloadCompletionBlock(location, nil);
}

@end

/************************* roothide specific *******************/

////////////////////////
uint64_t jbrand_new();
uint64_t jbrand_current();
int is_jbroot_name(char* name);
NSString* find_jbroot(BOOL force);
////////////////////////////////////////
NSString* jbrootPrefix(NSString *path);
NSString* rootfsPrefix(NSString* path);
///////////////////////////////////////////////////////

uint64_t jbrand_new()
{
    uint64_t value = ((uint64_t)arc4random()) | ((uint64_t)arc4random())<<32;
    uint8_t check = value>>8 ^ value >> 16 ^ value>>24 ^ value>>32 ^ value>>40 ^ value>>48 ^ value>>56;
    return (value & ~0xFF) | check;
}

int is_jbrand_value(uint64_t value)
{
   uint8_t check = value>>8 ^ value >> 16 ^ value>>24 ^ value>>32 ^ value>>40 ^ value>>48 ^ value>>56;
   return check == (uint8_t)value;
}

#define JB_ROOT_PREFIX ".jbroot-"
#define JB_RAND_LENGTH  (sizeof(uint64_t)*sizeof(char)*2)

int is_jbroot_name(char* name)
{
    if(strlen(name) != (sizeof(JB_ROOT_PREFIX)-1+JB_RAND_LENGTH))
        return 0;
    
    if(strncmp(name, JB_ROOT_PREFIX, sizeof(JB_ROOT_PREFIX)-1) != 0)
        return 0;
    
    char* endp=NULL;
    uint64_t value = strtoull(name+sizeof(JB_ROOT_PREFIX)-1, &endp, 16);
    if(!endp || *endp!='\0')
        return 0;
    
    if(!is_jbrand_value(value))
        return 0;
    
    return 1;
}

uint64_t resolve_jbrand_value(const char* name)
{
    if(strlen(name) != (sizeof(JB_ROOT_PREFIX)-1+JB_RAND_LENGTH))
        return 0;
    
    if(strncmp(name, JB_ROOT_PREFIX, sizeof(JB_ROOT_PREFIX)-1) != 0)
        return 0;
    
    char* endp=NULL;
    uint64_t value = strtoull(name+sizeof(JB_ROOT_PREFIX)-1, &endp, 16);
    if(!endp || *endp!='\0')
        return 0;
    
    if(!is_jbrand_value(value))
        return 0;
    
    return value;
}

NSString* find_jbroot(BOOL force)
{
    static NSString* cached_jbroot = nil;
    if(!force && cached_jbroot) {
        return cached_jbroot;
    }
    @synchronized(@"find_jbroot_lock")
    {
        //jbroot path may change when re-randomize it
        NSString * jbroot = nil;
        NSArray *subItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/var/containers/Bundle/Application/" error:nil];
        for (NSString *subItem in subItems) {
            if (is_jbroot_name(subItem.UTF8String))
            {
                NSString* path = [@"/var/containers/Bundle/Application/" stringByAppendingPathComponent:subItem];
                jbroot = path;
                break;
            }
        }
        cached_jbroot = jbroot;
    }
    return cached_jbroot;
}
////////////////////////////////////////////
uint64_t jbrand_current()
{
    NSString* jbroot = find_jbroot(NO);
    assert(jbroot != NULL);
    return resolve_jbrand_value([jbroot lastPathComponent].UTF8String);
}

NSString* jbrootPrefix(NSString *path)
{
    if(!path || path.UTF8String[0]!='/') {
        return path;
    }
    NSString* jbroot = find_jbroot(NO);
    assert(jbroot != NULL); //to avoid [nil stringByAppendingString:
    return [jbroot stringByAppendingPathComponent:path];
}

NSString* rootfsPrefix(NSString* path)
{
    if(!path || path.UTF8String[0]!='/') {
        return path;
    }
    return [@"/rootfs/" stringByAppendingPathComponent:path];
}
/////////////////////////////////////////////////////////////////////

#define DOPAMINE_INSTALL_VERSION    2

#define DEFAULT_SOURCES "\
Types: deb\n\
URIs: https://yourepo.com/\n\
Suites: ./\n\
Components:\n\
\n\
Types: deb\n\
URIs: https://repo.chariz.com/\n\
Suites: ./\n\
Components:\n\
\n\
Types: deb\n\
URIs: https://havoc.app/\n\
Suites: ./\n\
Components:\n\
\n\
Types: deb\n\
URIs: http://apt.thebigboss.org/repofiles/cydia/\n\
Suites: stable\n\
Components: main\n\
\n\
Types: deb\n\
URIs: https://roothide.github.io/\n\
Suites: ./\n\
Components:\n\
\n\
Types: deb\n\
URIs: https://roothide.github.io/procursus\n\
Suites: iphoneos-arm64e/%d\n\
Components: main\n\
\n\
Types: deb\n\
URIs: https://github.com/roothide/roothide.github.io/releases/download/%d/\n\
Suites: ./\n\
Components:\n\
"

// #define ALT_SOURCES "\
// Types: deb\n\
// URIs: https://iosjb.top/\n\
// Suites: ./\n\
// Components:\n\
// \n\
// Types: deb\n\
// URIs: https://iosjb.top/procursus\n\
// Suites: iphoneos-arm64e/%d\n\
// Components: main\n\
// "

#define ZEBRA_SOURCES "\
# Zebra Sources List\n\
deb https://getzbra.com/repo/ ./\n\
deb https://repo.chariz.com/ ./\n\
deb https://yourepo.com/ ./\n\
deb https://havoc.app/ ./\n\
deb https://roothide.github.io/ ./\n\
deb https://roothide.github.io/procursus iphoneos-arm64e/%d main\n\
deb https://github.com/roothide/roothide.github.io/releases/download/%d/ ./\n\
\n\
"

int getCFMajorVersion(void)
{
    if(@available(iOS 16.0, *)) {
        return 1900;
    }
    
    return ((int)kCFCoreFoundationVersionNumber / 100) * 100;
}
/////////////////////////////////////////////////////////////////////

@implementation DOBootstrapper(roothide)

#define STRAPLOG(...)   [[DOUIManager sharedInstance] sendLog:[NSString stringWithFormat:@__VA_ARGS__] debug:YES];
#define ASSERT(...)     do{if(!(__VA_ARGS__)) {completion([NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedExtracting userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"ABORT: %s (%d): %s", __FILE_NAME__, __LINE__, #__VA_ARGS__]}]);return -1;}} while(0)

- (NSString *)bootstrapVersion
{
    return [NSString stringWithFormat:@"%d", getCFMajorVersion()];
}

-(int) buildPackageSources:(void (^)(NSError *))completion
{
    NSFileManager* fm = NSFileManager.defaultManager;
    
    ASSERT([[NSString stringWithFormat:@(DEFAULT_SOURCES), getCFMajorVersion(), getCFMajorVersion()] writeToFile:jbrootPrefix(@"/etc/apt/sources.list.d/default.sources") atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    
    // //Users in some regions seem to be unable to access github.io
    // if([NSLocale.currentLocale.countryCode isEqualToString:@"CN"]) {
    //     ASSERT([[NSString stringWithFormat:@(ALT_SOURCES), getCFMajorVersion()] writeToFile:jbrootPrefix(@"/etc/apt/sources.list.d/sileo.sources") atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    // }
    
    if(![fm fileExistsAtPath:jbrootPrefix(@"/var/mobile/Library/Application Support/xyz.willy.Zebra")])
    {
        NSDictionary* attr = @{NSFilePosixPermissions:@(0755), NSFileOwnerAccountID:@(501), NSFileGroupOwnerAccountID:@(501)};
        ASSERT([fm createDirectoryAtPath:jbrootPrefix(@"/var/mobile/Library/Application Support/xyz.willy.Zebra") withIntermediateDirectories:YES attributes:attr error:nil]);
    }
    
    ASSERT([[NSString stringWithFormat:@(ZEBRA_SOURCES), getCFMajorVersion(), getCFMajorVersion()] writeToFile:jbrootPrefix(@"/var/mobile/Library/Application Support/xyz.willy.Zebra/sources.list") atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    
    return 0;
}

-(int) InstallBootstrap:(NSString*)installPath WithCompletion:(void (^)(NSError *))completion
{
    [[DOUIManager sharedInstance] sendLog:@"Extracting Bootstrap" debug:NO];

    NSFileManager* fm = NSFileManager.defaultManager;
    
    NSString* jbroot_path = installPath;
    
    ASSERT(mkdir(jbroot_path.fileSystemRepresentation, 0755) == 0);
    ASSERT(chown(jbroot_path.fileSystemRepresentation, 0, 0) == 0);

    find_jbroot(YES); //refresh
    
    //jbrootPrefix() and jbrand_current() available now
    
    NSString* bootstrapZstFile = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"bootstrap_%d.tar.zst", getCFMajorVersion()]];

    ASSERT([fm fileExistsAtPath:bootstrapZstFile]);
    
    NSString* bootstrapTarFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"bootstrap.tar"];
    if([fm fileExistsAtPath:bootstrapTarFile])
        ASSERT([fm removeItemAtPath:bootstrapTarFile error:nil]);
    
    NSError* error = [self decompressZstd:bootstrapZstFile toTar:bootstrapTarFile];
    if(error) {
        completion(error);
        return -1;
    }
    
    NSError* decompressionError = [self extractTar:bootstrapTarFile toPath:jbroot_path];
    if (decompressionError) {
        completion(decompressionError);
        return -1;
    }
    
    NSString* jbroot_secondary = [NSString stringWithFormat:@"/var/mobile/Containers/Shared/AppGroup/.jbroot-%016llX", jbrand_current()];
    ASSERT(mkdir(jbroot_secondary.fileSystemRepresentation, 0755) == 0);
    ASSERT(chown(jbroot_secondary.fileSystemRepresentation, 0, 0) == 0);
    
    ASSERT([fm moveItemAtPath:jbrootPrefix(@"/var") toPath:[jbroot_secondary stringByAppendingPathComponent:@"/var"] error:nil]);
    ASSERT([fm createSymbolicLinkAtPath:jbrootPrefix(@"/var") withDestinationPath:@"private/var" error:nil]);
    
    ASSERT([fm removeItemAtPath:jbrootPrefix(@"/private/var") error:nil]);
    ASSERT([fm createSymbolicLinkAtPath:jbrootPrefix(@"/private/var") withDestinationPath:[jbroot_secondary stringByAppendingPathComponent:@"/var"] error:nil]);
    
    ASSERT([fm removeItemAtPath:[jbroot_secondary stringByAppendingPathComponent:@"/var/tmp"] error:nil]);
    ASSERT([fm moveItemAtPath:jbrootPrefix(@"/tmp") toPath:[jbroot_secondary stringByAppendingPathComponent:@"/var/tmp"] error:nil]);
    ASSERT([fm createSymbolicLinkAtPath:jbrootPrefix(@"/tmp") withDestinationPath:@"var/tmp" error:nil]);
    
    ASSERT([fm createSymbolicLinkAtPath:[jbroot_secondary stringByAppendingPathComponent:@".jbroot"]
                    withDestinationPath:jbroot_path error:nil]);

    if(![fm fileExistsAtPath:jbrootPrefix(@"/var/mobile/Library/Preferences")])
    {
        NSDictionary* attr = @{NSFilePosixPermissions:@(0755), NSFileOwnerAccountID:@(501), NSFileGroupOwnerAccountID:@(501)};
        ASSERT([fm createDirectoryAtPath:jbrootPrefix(@"/var/mobile/Library/Preferences") withIntermediateDirectories:YES attributes:attr error:nil]);
    }
    
    if([self buildPackageSources:completion] != 0) {
        return -1;
    }
    
    STRAPLOG("Status: Bootstrap Installed");
    
    return 0;
}

-(int) ReRandomizeBootstrap:(void (^)(NSError *))completion
{
    [[DOUIManager sharedInstance] sendLog:@"ReRandomizing Bootstrap" debug:NO];
    
    uint64_t new_jbrand = jbrand_new();
    uint64_t prev_jbrand = jbrand_current();

    //jbrootPrefix() and jbrand_current() unavailable
    
    NSFileManager* fm = NSFileManager.defaultManager;
    
    ASSERT( [fm moveItemAtPath:[NSString stringWithFormat:@"/var/containers/Bundle/Application/.jbroot-%016llX", prev_jbrand]
                        toPath:[NSString stringWithFormat:@"/var/containers/Bundle/Application/.jbroot-%016llX", new_jbrand] error:nil] );
    
    ASSERT([fm moveItemAtPath:[NSString stringWithFormat:@"/var/mobile/Containers/Shared/AppGroup/.jbroot-%016llX", prev_jbrand]
                       toPath:[NSString stringWithFormat:@"/var/mobile/Containers/Shared/AppGroup/.jbroot-%016llX", new_jbrand] error:nil]);
    
    
    NSString* jbroot_path = [NSString stringWithFormat:@"/var/containers/Bundle/Application/.jbroot-%016llX", new_jbrand];
    NSString* jbroot_secondary = [NSString stringWithFormat:@"/var/mobile/Containers/Shared/AppGroup/.jbroot-%016llX", new_jbrand];
    
    ASSERT([fm removeItemAtPath:[jbroot_path stringByAppendingPathComponent:@"/private/var"] error:nil]);
    ASSERT([fm createSymbolicLinkAtPath:[jbroot_path stringByAppendingPathComponent:@"/private/var"]
                    withDestinationPath:[jbroot_secondary stringByAppendingPathComponent:@"/var"] error:nil]);
    
    ASSERT([fm removeItemAtPath:[jbroot_secondary stringByAppendingPathComponent:@".jbroot"] error:nil]);
    ASSERT([fm createSymbolicLinkAtPath:[jbroot_secondary stringByAppendingPathComponent:@".jbroot"]
                    withDestinationPath:jbroot_path error:nil]);
    
    find_jbroot(YES); //refresh
    
    //jbrootPrefix() and jbrand_current() available now

    return 0;
}

-(int) doBootstrap:(void (^)(NSError *))completion {
    
    NSFileManager* fm = NSFileManager.defaultManager;
    
    int installedCount=0;
    NSString* dirpath = @"/var/containers/Bundle/Application/";
    NSArray *subItems = [fm contentsOfDirectoryAtPath:dirpath error:nil];
    for (NSString *subItem in subItems)
    {
        if (!is_jbroot_name(subItem.UTF8String)) continue;
        
        NSString* jbroot_path = [dirpath stringByAppendingPathComponent:subItem];
        
        if([fm fileExistsAtPath:[jbroot_path stringByAppendingPathComponent:@"/.bootstrapped"]]
           || [fm fileExistsAtPath:[jbroot_path stringByAppendingPathComponent:@"/.thebootstrapped"]]) {
            completion([NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedExtracting userInfo:@{NSLocalizedDescriptionKey : @"\n\n\n\nYour device has been bootstrapped through the roothide Bootstrap app, please uninject for all apps in the AppList of Bootstrap and unisntall it in the Settings of Bootstrap before jailbreaking with Dopamine.\n\n\n"}]);
            return -1;
        }

        if([fm fileExistsAtPath:[jbroot_path stringByAppendingPathComponent:@"/.installed_dopamine"]]) {
            installedCount++;
            continue;
        }


        STRAPLOG("remove unknown/unfinished jbroot %@", subItem);

        NSString* jbroot_secondary = [NSString stringWithFormat:@"/var/mobile/Containers/Shared/AppGroup/%@", subItem];
        if([fm fileExistsAtPath:jbroot_secondary]) {
            ASSERT([fm removeItemAtPath:jbroot_secondary error:nil]);
        }
        
        ASSERT([fm removeItemAtPath:jbroot_path error:nil]);
    }

    if(installedCount > 1) {
        completion([NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedExtracting userInfo:@{NSLocalizedDescriptionKey : @"\n\nThere are multi jbroot in /var/containers/Bundle/Applicaton/\n\n\n"}]);
        return -1;
    }
    
    NSString* jbroot_path = find_jbroot(YES);
    
    if(!jbroot_path) {
        STRAPLOG("device is not strapped...");
        
        jbroot_path = [NSString stringWithFormat:@"/var/containers/Bundle/Application/.jbroot-%016llX", jbrand_new()];
        
        STRAPLOG("bootstrap @ %@", jbroot_path);
        
        if([self InstallBootstrap:jbroot_path WithCompletion:completion] != 0) {
            return -1;
        }
        
    } else {
        STRAPLOG("device is strapped: %@", jbroot_path);
        
        ASSERT([fm fileExistsAtPath:jbrootPrefix(@"/.installed_dopamine")]);
        
        STRAPLOG("Status: Rerandomize jbroot");
        
        if([self ReRandomizeBootstrap:completion] != 0) {
            return -1;
        }
    }
    
    STRAPLOG("Status: Bootstrap Successful");

    return 0;
}

- (void)prepareBootstrapWithCompletion:(void (^)(NSError *))completion
{

    // Remove /var/jb as it might be wrong
    NSError *error=nil;
    if (![self deleteSymlinkAtPath:@"/var/jb" error:&error]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
            if (![[NSFileManager defaultManager] removeItemAtPath:@"/var/jb" error:&error]) {
                completion([NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedReplacing userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Removing /var/jb directory failed with error: %@", error]}]);
                return;
            }
        }
        else {
            completion([NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedReplacing userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Removing /var/jb symlink failed with error: %@", error]}]);
            return;
        }
    }
    
    // Clean up xinaA15 v1 leftovers if desired
        NSArray *xinaLeftoverSymlinks = @[
            @"/var/alternatives",
            @"/var/ap",
            @"/var/apt",
            @"/var/bin",
            @"/var/bzip2",
            @"/var/cache",
            @"/var/dpkg",
            @"/var/etc",
            @"/var/gzip",
            @"/var/lib",
            @"/var/Lib",
            @"/var/libexec",
            @"/var/Library",
            @"/var/LIY",
            @"/var/Liy",
            @"/var/local",
            @"/var/newuser",
            @"/var/profile",
            @"/var/sbin",
            @"/var/suid_profile",
            @"/var/sh",
            @"/var/sy",
            @"/var/share",
            @"/var/ssh",
            @"/var/sudo_logsrvd.conf",
            @"/var/suid_profile",
            @"/var/sy",
            @"/var/usr",
            @"/var/zlogin",
            @"/var/zlogout",
            @"/var/zprofile",
            @"/var/zshenv",
            @"/var/zshrc",
            @"/var/log/dpkg",
            @"/var/log/apt",
        ];
        NSArray *xinaLeftoverFiles = @[
            @"/var/lib",
            @"/var/master.passwd",
            @"/var/.keep_symlinks",
        ];
        
        for (NSString *xinaLeftoverSymlink in xinaLeftoverSymlinks) {
            [self deleteSymlinkAtPath:xinaLeftoverSymlink error:nil];
        }
        
        for (NSString *xinaLeftoverFile in xinaLeftoverFiles) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:xinaLeftoverFile]) {
                [[NSFileManager defaultManager] removeItemAtPath:xinaLeftoverFile error:nil];
            }
        }
    
    if([self doBootstrap:completion] == 0) {
        
        //update jailbreakInfo.rootPath and jailbreakInfo.jbrand
        [[DOEnvironmentManager sharedManager] locateJailbreakRoot];
        
        [[DOUIManager sharedInstance] sendLog:@"Updating BaseBin" debug:NO];
        
        NSError* error=nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:jbrootPrefix(@"/basebin")]) {
            if (![[NSFileManager defaultManager] removeItemAtPath:jbrootPrefix(@"/basebin") error:&error]) {
                completion([NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedExtracting userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed deleting existing basebin file with error: %@", error.localizedDescription]}]);
                return;
            }
        }
        error = [self extractTar:[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"basebin.tar"] toPath:jbrootPrefix(@"/")];
        if (error) {
            completion(error);
            return;
        }
        [self patchBasebinDaemonPlists];
        [[NSFileManager defaultManager] removeItemAtPath:jbrootPrefix(@"/basebin/basebin.tc") error:nil];
        
        JBFixMobilePermissions();
        
        completion(nil);
    }
}

-(int) fixBootstrapSymlink:(NSString*)path
{
    const char* jbpath = jbrootPrefix(path).fileSystemRepresentation;
    
    struct stat st={0};
    int r = lstat(jbpath, &st);
    if(r != 0) {
        assert(errno != 0);
        return errno;
    }
    
    if (!S_ISLNK(st.st_mode)) {
        return 0;
    }
    
    char link[PATH_MAX+1] = {0};
    assert(readlink(jbpath, link, sizeof(link)-1) > 0);
    if(link[0] != '/') {
        return 0;
    }

    //stringByStandardizingPath won't remove /private/ prefix if the path does not exist on disk
    NSString* _link = @(link).stringByStandardizingPath.stringByResolvingSymlinksInPath;
    
    NSString *pattern = @"^(?:/private)?/var/containers/Bundle/Application/\\.jbroot-[0-9A-Z]{16}(/.+)$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:_link options:0 range:NSMakeRange(0, [_link length])];
    assert(match != nil);
    
    NSString* target = [_link substringWithRange:[match rangeAtIndex:1]];
    NSString* newlink = [@".jbroot" stringByAppendingPathComponent:target];
    
    assert(unlink(jbpath) == 0);
    assert(symlink(newlink.fileSystemRepresentation, jbpath) == 0);
    assert(access(jbpath, F_OK) == 0);
    
    return 0;
}

- (NSError *)finalizeBootstrap
{
    // Initial setup on first jailbreak
    if ([[NSFileManager defaultManager] fileExistsAtPath:jbrootPrefix(@"/prep_bootstrap.sh")]) {
        [[DOUIManager sharedInstance] sendLog:@"Finalizing Bootstrap" debug:NO];
        int r = exec_cmd_trusted(JBROOT_PATH("/bin/sh"), "/prep_bootstrap.sh", NULL);
        if (r != 0) {
            return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"prep_bootstrap.sh returned %d\n", r]}];
        }
        
        NSError *error = [self installPackageManagers];
        if (error) return error;
        
        NSString *roothideManager = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"roothideapp.deb"];
         r = [self installPackage:roothideManager];
        if (r != 0) return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to install roothideManager: %d\n", r]}];

        //Remove the shits triggered by uicache before first jailbreak is fully activated.
        [NSFileManager.defaultManager removeItemAtPath:@"/var/mobile/Library/SplashBoard/Snapshots/xyz.willy.Zebra" error:nil];
        [NSFileManager.defaultManager removeItemAtPath:@"/var/mobile/Library/SplashBoard/Snapshots/com.roothide.manager" error:nil];
        [NSFileManager.defaultManager removeItemAtPath:@"/var/mobile/Library/SplashBoard/Snapshots/org.coolstar.SileoStore" error:nil];
    }
    else
    {
        [[DOUIManager sharedInstance] sendLog:@"Updating Symlinks" debug:NO];

        NSArray* bootstrapSymlinks = @[@"/bin/sh", @"/usr/bin/sh"];
        for(NSString* slink in bootstrapSymlinks)
        {
            int r = [self fixBootstrapSymlink:slink];
            if(r != 0) {
                return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"fixBootstrapSymlink(%@) returned %d\n", slink, r]}];
            }
        }
        
        int r = exec_cmd_trusted(JBROOT_PATH("/bin/sh"), "/usr/libexec/updatelinks.sh", NULL);
        if (r != 0) {
            return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"updatelinks.sh returned %d\n", r]}];
        }
    }
    
    BOOL shouldInstallLibkrw = [self shouldInstallPackage:@"libkrw0-dopamine"];
    BOOL shouldInstallBasebinLink = [self shouldInstallPackage:@"dopamine-basebin-link"];
    
    if (shouldInstallLibkrw || shouldInstallBasebinLink) {
        [[DOUIManager sharedInstance] sendLog:@"Updating Bundled Packages" debug:NO];
        
        if (shouldInstallLibkrw) {
            NSString *libkrwPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"libkrw-dopamine.deb"];
            int r = [self installPackage:libkrwPath];
            if (r != 0) return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to install the libkrw plugin: %d\n", r]}];
        }
        
        if (shouldInstallBasebinLink) {
            // Clean symlinks from earlier Dopamine versions
            if ([self fileOrSymlinkExistsAtPath:jbrootPrefix(@"/usr/bin/opainject")]) {
                [[NSFileManager defaultManager] removeItemAtPath:jbrootPrefix(@"/usr/bin/opainject") error:nil];
            }
            if ([self fileOrSymlinkExistsAtPath:jbrootPrefix(@"/usr/bin/jbctl")]) {
                [[NSFileManager defaultManager] removeItemAtPath:jbrootPrefix(@"/usr/bin/jbctl") error:nil];
            }
            if ([self fileOrSymlinkExistsAtPath:jbrootPrefix(@"/usr/lib/libjailbreak.dylib")]) {
                [[NSFileManager defaultManager] removeItemAtPath:jbrootPrefix(@"/usr/lib/libjailbreak.dylib") error:nil];
            }
            if ([self fileOrSymlinkExistsAtPath:jbrootPrefix(@"/usr/bin/libjailbreak.dylib")]) {
                // Yes this exists >.< was a typo
                [[NSFileManager defaultManager] removeItemAtPath:jbrootPrefix(@"/usr/bin/libjailbreak.dylib") error:nil];
            }

            NSString *basebinLinkPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"basebin-link.deb"];
            int r = [self installPackage:basebinLinkPath];
            if (r != 0) return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to install basebin link: %d\n", r]}];
        }
    }


    if ([self fileOrSymlinkExistsAtPath:jbrootPrefix(@"/usr/lib/libroot.dylib")]) {
        [[NSFileManager defaultManager] removeItemAtPath:jbrootPrefix(@"/usr/lib/libroot.dylib") error:nil];
    }
    NSString *librootPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"libroot.deb"];
    NSString* unpackedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    int ret = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg-deb"), "-R", rootfsPrefix(librootPath).fileSystemRepresentation, rootfsPrefix(unpackedPath).fileSystemRepresentation, NULL);
    if (ret != 0) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedFinalising userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Failed to unpack deb: %d\n", ret]}];
    }
    NSError* error=nil;
    [[NSFileManager defaultManager] copyItemAtPath:[unpackedPath stringByAppendingPathComponent:@"/var/jb/usr/lib/libroot.dylib"] toPath:jbrootPrefix(@"/usr/lib/libroot.dylib") error:&error];
    if(error) {
        return error;
    }
    if(![[NSFileManager defaultManager] removeItemAtPath:unpackedPath error:&error]) {
        return error;
    }

    
    [[NSString stringWithFormat:@"%d",DOPAMINE_INSTALL_VERSION] writeToFile:jbrootPrefix(@"/.installed_dopamine") atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    if(jbclient_palehide_present()) {
        [@"" writeToFile:jbrootPrefix(@"/.installed_palera1n") atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [[NSFileManager defaultManager] removeItemAtPath:jbrootPrefix(@"/.installed_palera1n") error:nil];
    }

    return nil;
}

- (NSError *)updateVarJbSymlink
{
    /* RootHide: delete public /var/jb, never recreate. */
    NSError *error = nil;
    if (![self deleteSymlinkAtPath:@"/var/jb" error:&error]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
            [[NSFileManager defaultManager] removeItemAtPath:@"/var/jb" error:&error];
        }
    }
    return nil;
}

- (NSError *)deleteBootstrap
{
    //jbrootPrefix() and jbrand_current() unavailable now
    
    NSError* error=nil;
    NSFileManager* fm = NSFileManager.defaultManager;
    
    NSString* dirpath = @"/var/containers/Bundle/Application/";
    for(NSString* item in [fm directoryContentsAtPath:dirpath])
    {
        if(is_jbroot_name(item.UTF8String)) {
            STRAPLOG("remove %@ @ %@", item, dirpath);
            if(![fm removeItemAtPath:[dirpath stringByAppendingPathComponent:item] error:&error])
                return error;
        }
    }
    
    dirpath = @"/var/mobile/Containers/Shared/AppGroup/";
    for(NSString* item in [fm directoryContentsAtPath:dirpath])
    {
        if(is_jbroot_name(item.UTF8String)) {
            STRAPLOG("remove %@ @ %@", item, dirpath);
            if(![fm removeItemAtPath:[dirpath stringByAppendingPathComponent:item] error:&error])
                return error;
        }
    }
    
    return nil;
}

@end

/////////////////////////////////////////////////////////////////

@implementation DOEnvironmentManager(roothide)
- (void)locateJailbreakRoot
{
    if(gSystemInfo.jailbreakInfo.rootPath) free(gSystemInfo.jailbreakInfo.rootPath);
    
    NSString* jbroot_path = find_jbroot(YES);
    if(jbroot_path) {
        gSystemInfo.jailbreakInfo.rootPath = strdup(jbroot_path.fileSystemRepresentation);
        gSystemInfo.jailbreakInfo.jbrand = jbrand_current();
    }
}
- (NSError *)ensureJailbreakRootExists
{
    return nil;
}
@end

/************************************** roothide specific *******************************************/
