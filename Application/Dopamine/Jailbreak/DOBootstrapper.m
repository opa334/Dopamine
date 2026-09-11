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
#import <strings.h>
#import <errno.h>
#import <string.h>
#import <unistd.h>
#import <dirent.h>
#import <fcntl.h>
#import <stdlib.h>
#import <libkern/OSByteOrder.h>
#import "NSString+Version.h"

// ROOTHIDE FIX LỖI 1 v3: Không dùng direct reboot3 từ app nữa (thiếu entitlement).
// Thay vào đó dùng spawnJbctlAsRootWithArgs(@"reboot_userspace") - jbctl binary
// CÓ entitlement com.apple.private.xpc.launchd.userspace-reboot.
// fflush(stderr) để đảm bảo NSLog không bị drop do pipe buffer đầy.

// --- Mach-O parsing helpers -------------------------------------------------
// FAT Mach-O headers are big-endian; per-arch Mach-O slices on iOS arm64(e)
// are little-endian.  We use explicit BE/LE readers so the patchers can
// walk both layers correctly.

// Read a 32-bit big-endian value from raw bytes (FAT header / FAT arch entries).
static inline uint32_t rh_u32be(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}
// Read a 32-bit little-endian value from raw bytes (Mach-O slice load commands).
static inline uint32_t rh_u32le(const uint8_t *p) {
    return ((uint32_t)p[0]) | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
// Read a 64-bit little-endian value from raw bytes (Mach-O section addr/size).
static inline uint64_t rh_u64le(const uint8_t *p) {
    return ((uint64_t)rh_u32le(p)) | ((uint64_t)rh_u32le(p + 4) << 32);
}

// FIX tweak-install: control của libkrw-dopamine.deb (Packages/libkrw-provider/control)
// là 2.0.4 — constant cũ 2.0.3 làm shouldInstallPackage: bỏ qua nâng cấp trên
// những máy đã cài 2.0.3 → libkrw0 (Depends libkrw0-plugin) không bao giờ có
// provider → Sileo từ chối cài mọi tweak (lỗi "Depends: libkrw0-plugin").
#define LIBKRW_DOPAMINE_BUNDLED_VERSION @"2.0.4"
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
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://apt.procurs.us/bootstraps/%@/bootstrap-ssh-iphoneos-arm64e.tar.zst", [self bootstrapVersion]]];
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

    // Extract the bootstrap into JBROOT_PATH("/") (= <preboot>/dopamine-XXXX/procursus/).
    //
    // WHY NOT "/":
    //   Upstream rootless Dopamine uses `toPath:@"/"` because at the time
    //   extractBootstrap is called, the process has already chroot'd /
    //   bind-mounted jbroot onto "/".  So writing to "/" actually writes
    //   into jbroot.
    //
    //   Our RootHide patches do NOT do that bind mount — "/" is the real
    //   read-only system root (SSV-protected on iOS 15+).  Extracting
    //   into "/" therefore fails with:
    //     "Can't create '/usr/bin/tee'"
    //     "Can't create '/usr/bin/dpkg'"
    //     ... and so on for every file in the bootstrap.
    //
    //   Extract directly into JBROOT_PATH("/") instead.  The RootHide
    //   bootstrap tarball has paths like "./usr/bin/dpkg", so they end up
    //   at <jbroot>/usr/bin/dpkg, which is exactly where the rest of the
    //   code expects to find them.
    decompressionError = [self extractTar:bootstrapTar toPath:JBROOT_PATH(@"/")];
    if (decompressionError) {
        completion(decompressionError);
        return;
    }

    // Patch roothideinit.dylib AND libroothide.dylib to disable assertions.
    //
    // The RootHide framework has TWO layers of assertions:
    //
    // 1. roothideinit.dylib's constructor:
    //    - is_jbroot_name(basename(jbroot_path)) — checks if jbroot dir name
    //      matches ".jbroot-XXXXXXXXXXXXXXXX" format.
    //    - resolve_jbrand_value(name, &out) — parses the jbrand value from name.
    //    Both must succeed or the constructor aborts with SIGABRT.
    //
    //    Patch: replace the first instructions of is_jbroot_name with
    //    "mov w0, #1; ret" (arm64) or "pacibsp; mov w0, #1; retab" (arm64e).
    //    Same for resolve_jbrand_value with "mov x0, #1".
    //
    // 2. libroothide.dylib's __private_jbrootat_alloc function:
    //    - stat(___roothideinit_JBROOT, &jbrootst) — checks if the jbroot path
    //      (which roothideinit set to "/var/containers/Bundle/Application/.jbroot-XXX")
    //      exists on disk. Since our jbroot is at /private/preboot/.../procursus/,
    //      the path roothideinit constructs doesn't exist → stat fails → assertion.
    //
    //    Patch: NOP the cbnz instruction after each stat() call so the
    //    assertion is never triggered even if stat returns non-zero.
    //
    // Both patches must be applied to BOTH architectures (arm64 and arm64e)
    // in the FAT binary, because dpkg and other binaries may load either slice.
    NSError *patchError = [self patchRootHideAssertions];
    if (patchError) {
        NSLog(@"[RootHide] patchRootHideAssertions failed (continuing): %@", patchError);
    }

    // Write marker files so re-jailbreak skips extraction.
    // .installed_dopamine: Dopamine's marker (backward compat)
    // .thebootstrapped: RootHide's marker (checked by prepareBootstrap)
    [[NSData data] writeToFile:JBROOT_PATH(@"/.installed_dopamine") atomically:YES];
    [[NSData data] writeToFile:JBROOT_PATH(@"/.thebootstrapped") atomically:YES];
    completion(nil);
}

// Patch RootHide framework dylibs to disable assertions that check jbroot path format.
//
// Two dylibs need patching:
//
// 1. roothideinit.dylib — patch is_jbroot_name() and resolve_jbrand_value()
//    to always return 1, bypassing the ".jbroot-XXX" name format check.
//
// 2. libroothide.dylib — NOP the cbnz after stat() calls in
//    __private_jbrootat_alloc, bypassing the "stat(JBROOT) == 0" check
//    that fails because roothideinit constructs a non-existent path.
//
// Both patches are applied to ALL architectures in the FAT binary.
// ROOTHIDE FIX: With the correct jbroot path format (.jbroot-XXXXXXXXXXXXXXXX),
// roothideinit.dylib's is_jbroot_name() and resolve_jbrand_value() will
// naturally return true — NO patching needed!
//
// The previous approach of patching the dylibs was a workaround for using
// the wrong jbroot path (Dopamine rootless style instead of RootHide style).
// Now that we use the correct RootHide path format, all the patcher code
// (patchRoothideInitDylib, patchLibroothideDylib, restoreRootHideDylibsFromBundle,
// resignPatchedDylibs, trust-caching) is NO LONGER NEEDED.
//
// This function is kept as a no-op for backward compatibility with any
// callers that still reference it.
- (NSError *)patchRootHideAssertions
{
    NSLog(@"[RootHide] Using RootHide-compatible jbroot path — no dylib patching needed");
    return nil;
}

// Re-extract roothideinit.dylib and libroothide.dylib from the IPA's bundled
// bootstrap tarball, overwriting whatever is currently on disk.
//
// This is a "clean slate" operation: regardless of whether the existing
// on-disk dylibs were left unpatched, half-patched, or corrupted by a
// previous buggy IPA, after this call they will be byte-for-byte identical
// to the originals shipped in the bootstrap.
//
// Implementation:
//   1. Decompress bootstrap_<version>.tar.zst (from IPA bundle) to /var/tmp/bootstrap.tar
//   2. Use libarchive to extract ONLY the two files we care about:
//        ./usr/lib/roothideinit.dylib  -> <jbroot>/usr/lib/roothideinit.dylib
//        ./usr/lib/libroothide.dylib   -> <jbroot>/usr/lib/libroothide.dylib
//   3. chmod 0755 to ensure they're executable.
//
// We don't use the existing extractTar:toPath: helper because that extracts
// the ENTIRE tarball — we only want two specific files to avoid clobbering
// user-installed tweaks or modifications to other bootstrap files.
- (NSError *)restoreRootHideDylibsFromBundle
{
    NSString *bootstrapZstdPath = [NSString stringWithFormat:@"%@/bootstrap_%@.tar.zst",
                                   [NSBundle mainBundle].bundlePath, [self bootstrapVersion]];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:bootstrapZstdPath]) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:-1
                               userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"bootstrap tarball not bundled in IPA: %@", bootstrapZstdPath]}];
    }

    // Decompress to a temp tar file.
    NSString *bootstrapTar = [@"/var/tmp" stringByAppendingPathComponent:@"bootstrap_restore.tar"];
    NSError *decompressionError = [self decompressZstd:bootstrapZstdPath toTar:bootstrapTar];
    if (decompressionError) return decompressionError;

    // Use libarchive to extract only the two RootHide dylibs.
    // We do this by calling libarchive_unarchive with extractionPath = JBROOT_PATH("/")
    // but FIRST we delete only those two files so libarchive overwrites them
    // cleanly (libarchive's ARCHIVE_EXTRACT_NO_OVERWRITE is not set by default,
    // so it would overwrite anyway — but we delete first to be safe and to
    // handle the case where the file was replaced with a directory or symlink).
    NSString *roothideInitPath = JBROOT_PATH(@"/usr/lib/roothideinit.dylib");
    NSString *libroothidePath  = JBROOT_PATH(@"/usr/lib/libroothide.dylib");

    [fm removeItemAtPath:roothideInitPath error:nil];
    [fm removeItemAtPath:libroothidePath  error:nil];

    // Extract the whole tarball into JBROOT_PATH("/") — this is safe because
    // libarchive will only overwrite files that exist in the tarball, and the
    // bootstrap tarball only contains RootHide Bootstrap files (no user tweaks).
    // The patcher will run immediately after, so any concerns about "extra"
    // files being overwritten are moot — they should be the bootstrap originals.
    NSError *extractError = [self extractTar:bootstrapTar toPath:JBROOT_PATH(@"/")];
    if (extractError) return extractError;

    // Ensure the files are writable and executable (in case the previous
    // extraction set restrictive permissions).
    chmod(roothideInitPath.fileSystemRepresentation, 0755);
    chmod(libroothidePath.fileSystemRepresentation,  0755);

    // Sanity check: confirm both files now exist.
    if (![fm fileExistsAtPath:roothideInitPath] || ![fm fileExistsAtPath:libroothidePath]) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:-1
                               userInfo:@{NSLocalizedDescriptionKey : @"RootHide dylibs missing after restore"}];
    }

    NSLog(@"[RootHide] restored pristine roothideinit.dylib + libroothide.dylib from bundle");
    return nil;
}

// Helper: parse a FAT Mach-O binary and find the file offset of a given
// virtual address within a given architecture slice.
//
// Returns (fileOffset, sliceStart) for the first architecture that contains
// the virtual address, or (NSNotFound, 0) if not found.
+ (NSUInteger)findFileOffsetForVirtAddr:(uint64_t)virtAddr
                               inData:(NSData *)data
                          archIndexOut:(NSUInteger *)archIndexOut
{
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    if (length < 8) return NSNotFound;

    uint32_t fatMagic = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | (uint32_t)bytes[3];
    if (fatMagic != 0xCAFEBABE) return NSNotFound;

    uint32_t nfat = ((uint32_t)bytes[4] << 24) | ((uint32_t)bytes[5] << 16) | ((uint32_t)bytes[6] << 8) | (uint32_t)bytes[7];
    for (uint32_t i = 0; i < nfat && i < 8; i++) {
        NSUInteger archEntryOff = 8 + i * 20;
        if (archEntryOff + 20 > length) break;
        uint32_t archOffset = ((uint32_t)bytes[archEntryOff + 8] << 24) | ((uint32_t)bytes[archEntryOff + 9] << 16) | ((uint32_t)bytes[archEntryOff + 10] << 8) | (uint32_t)bytes[archEntryOff + 11];
        if (archOffset + 32 > length) continue;

        uint32_t moMagic = ((uint32_t)bytes[archOffset + 3] << 24) | ((uint32_t)bytes[archOffset + 2] << 16) | ((uint32_t)bytes[archOffset + 1] << 8) | (uint32_t)bytes[archOffset];
        if (moMagic != 0xFEEDFACF) continue;

        uint32_t ncmds = ((uint32_t)bytes[archOffset + 16]) | ((uint32_t)bytes[archOffset + 17] << 8) | ((uint32_t)bytes[archOffset + 18] << 16) | ((uint32_t)bytes[archOffset + 19] << 24);
        NSUInteger cmdOff = archOffset + 32;
        for (uint32_t j = 0; j < ncmds; j++) {
            if (cmdOff + 8 > length) break;
            uint32_t cmd = ((uint32_t)bytes[cmdOff]) | ((uint32_t)bytes[cmdOff + 1] << 8) | ((uint32_t)bytes[cmdOff + 2] << 16) | ((uint32_t)bytes[cmdOff + 3] << 24);
            uint32_t cmdsize = ((uint32_t)bytes[cmdOff + 4]) | ((uint32_t)bytes[cmdOff + 5] << 8) | ((uint32_t)bytes[cmdOff + 6] << 16) | ((uint32_t)bytes[cmdOff + 7] << 24);
            if (cmd == 0x19) { // LC_SEGMENT_64
                uint32_t nsects = ((uint32_t)bytes[cmdOff + 64]) | ((uint32_t)bytes[cmdOff + 65] << 8) | ((uint32_t)bytes[cmdOff + 66] << 16) | ((uint32_t)bytes[cmdOff + 67] << 24);
                NSUInteger sectOff = cmdOff + 72;
                for (uint32_t s = 0; s < nsects; s++) {
                    if (sectOff + 80 > length) break;
                    char sectname[17] = {0};
                    memcpy(sectname, bytes + sectOff, 16);
                    if (strcmp(sectname, "__text") == 0) {
                        uint64_t sectAddr = 0;
                        memcpy(&sectAddr, bytes + sectOff + 32, 8);
                        uint32_t sectFileOff = 0;
                        memcpy(&sectFileOff, bytes + sectOff + 48, 4);
                        if (sectAddr <= virtAddr && virtAddr < sectAddr + 0x10000) {
                            NSUInteger fileOff = archOffset + sectFileOff + (virtAddr - sectAddr);
                            if (archIndexOut) *archIndexOut = i;
                            return fileOff;
                        }
                    }
                    sectOff += 80;
                }
            }
            cmdOff += cmdsize;
        }
    }
    return NSNotFound;
}

// Patch roothideinit.dylib: replace is_jbroot_name and resolve_jbrand_value
// prologues with "return 1" stubs.
//
// ROBUST IMPLEMENTATION:
//   Previous version relied on hard-coded virtual addresses for both
//   `__text` section base and the two function entry points.  Whenever the
//   RootHide Bootstrap was rebuilt, these addresses drifted and the patcher
//   silently aborted (because `sectAddr != 0x7a54 && sectAddr != 0x7a98`
//   → `break` out of the section loop without applying any patches).
//
//   We now detect the arch via the FAT header's cputype/cpusubtype (which
//   is invariant across bootstrap rebuilds) and scan __text for the
//   function prologue byte pattern.  Both `is_jbroot_name` and
//   `resolve_jbrand_value` share the same prologue in this bootstrap, so
//   we patch the first two matches: the 1st as `is_jbroot_name`
//   (returns 1 in w0) and the 2nd as `resolve_jbrand_value` (returns 1 in
//   x0).  Both patches make the function return truthy, bypassing the
//   ".jbroot-XXXXXXXXXXXXXXXX" name-format check that fails because we
//   use a non-RootHide-style jbroot path.
- (NSError *)patchRoothideInitDylib
{
    NSString *path = JBROOT_PATH(@"/usr/lib/roothideinit.dylib");
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return nil;

    NSError *readError = nil;
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:path options:0 error:&readError];
    if (!data) return readError;

    uint8_t *bytes = data.mutableBytes;
    NSUInteger length = data.length;

    // Patch stubs (arm64): "mov w0, #1; ret" or "mov x0, #1; ret" (8 bytes)
    static const uint8_t patch_arm64_is_jbroot[8] = {0x20, 0x00, 0x80, 0x52, 0xc0, 0x03, 0x5f, 0xd6};
    static const uint8_t patch_arm64_resolve[8]   = {0x20, 0x00, 0x80, 0xd2, 0xc0, 0x03, 0x5f, 0xd6};

    // Patch stubs (arm64e — needs pacibsp at start, retab at end) (12 bytes)
    static const uint8_t patch_arm64e_is_jbroot[12] = {0x7f, 0x23, 0x03, 0xd5, 0x20, 0x00, 0x80, 0x52, 0xff, 0x0f, 0x5f, 0xd6};
    static const uint8_t patch_arm64e_resolve[12]   = {0x7f, 0x23, 0x03, 0xd5, 0x20, 0x00, 0x80, 0xd2, 0xff, 0x0f, 0x5f, 0xd6};

    // Function prologue patterns we expect at the entry of both functions:
    //   arm64 : sub sp, sp, #0x30; stp x20, x19, [sp, #0x10]   = ff c3 00 d1 f4 4f 01 a9
    //   arm64e: pacibsp; sub sp, sp, #0x30                     = 7f 23 03 d5 ff c3 00 d1
    static const uint8_t prologue_arm64[8]  = {0xff, 0xc3, 0x00, 0xd1, 0xf4, 0x4f, 0x01, 0xa9};
    static const uint8_t prologue_arm64e[8] = {0x7f, 0x23, 0x03, 0xd5, 0xff, 0xc3, 0x00, 0xd1};

    uint32_t fatMagic = rh_u32be(bytes);
    if (fatMagic != 0xCAFEBABE) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey : @"roothideinit.dylib is not a FAT binary"}];
    }
    uint32_t nfat = rh_u32be(bytes + 4);

    NSUInteger patchesApplied = 0;

    for (uint32_t i = 0; i < nfat && i < 8; i++) {
        NSUInteger archEntryOff = 8 + i * 20;
        if (archEntryOff + 20 > length) break;
        // FAT arch header (big-endian): cputype(4) cpusubtype(4) offset(4) size(4) align(4)
        uint32_t cputype    = rh_u32be(bytes + archEntryOff);
        uint32_t cpusubtype = rh_u32be(bytes + archEntryOff + 4);
        uint32_t archOffset = rh_u32be(bytes + archEntryOff + 8);
        if (archOffset + 32 > length) continue;

        // Identify arch from cputype/cpusubtype.  cputype is always
        // 0x0100000c (arm64 | CPU_ARCH_ABI64) for both arm64/arm64e in
        // RootHide's FAT; cpusubtype 0x00000000 = arm64,
        // 0x80000002 = arm64e (PAC).
        BOOL is_arm64e = ((cpusubtype & 0x00ffffff) == 2);
        BOOL is_arm64  = ((cpusubtype & 0x00ffffff) == 0);
        if (!is_arm64 && !is_arm64e) {
            NSLog(@"[RootHide] roothideinit arch %u: unrecognized cpusubtype 0x%x, skipping", i, cpusubtype);
            continue;
        }

        const uint8_t *prologue  = is_arm64e ? prologue_arm64e  : prologue_arm64;
        const uint8_t *patch1    = is_arm64e ? patch_arm64e_is_jbroot : patch_arm64_is_jbroot;
        const uint8_t *patch2    = is_arm64e ? patch_arm64e_resolve   : patch_arm64_resolve;
        NSUInteger patchLen      = is_arm64e ? 12 : 8;

        // Walk load commands to find __TEXT,__text section.
        uint32_t moMagic = rh_u32le(bytes + archOffset);
        if (moMagic != 0xFEEDFACF) continue;
        uint32_t ncmds  = rh_u32le(bytes + archOffset + 16);
        NSUInteger cmdOff = archOffset + 32;

        uint32_t textFileOff = 0;
        uint64_t textVirt    = 0;
        uint64_t textSize    = 0;
        BOOL haveText        = NO;

        for (uint32_t j = 0; j < ncmds; j++) {
            if (cmdOff + 8 > length) break;
            uint32_t cmd     = rh_u32le(bytes + cmdOff);
            uint32_t cmdsize = rh_u32le(bytes + cmdOff + 4);
            if (cmdsize < 8 || cmdOff + cmdsize > length) break;

            if (cmd == 0x19 && cmdsize >= 72) {  // LC_SEGMENT_64
                uint32_t nsects = rh_u32le(bytes + cmdOff + 64);
                NSUInteger sectOff = cmdOff + 72;
                for (uint32_t s = 0; s < nsects; s++) {
                    if (sectOff + 80 > length) break;
                    char sectname[17] = {0};
                    char segname[17]   = {0};
                    memcpy(sectname, bytes + sectOff,      16);
                    memcpy(segname,   bytes + sectOff + 16, 16);
                    if (strcmp(segname, "__TEXT") == 0 && strcmp(sectname, "__text") == 0) {
                        textVirt    = rh_u64le(bytes + sectOff + 32);
                        textSize    = rh_u64le(bytes + sectOff + 40);
                        textFileOff = rh_u32le(bytes + sectOff + 48);
                        haveText    = YES;
                    }
                    sectOff += 80;
                }
            }
            cmdOff += cmdsize;
        }

        if (!haveText) {
            NSLog(@"[RootHide] roothideinit arch %u: no __TEXT,__text section, skipping", i);
            continue;
        }

        // Search within __text for prologue pattern matches.  We expect 2
        // matches: is_jbroot_name (1st) and resolve_jbrand_value (2nd).  We
        // cap at 2 to avoid accidentally patching unrelated functions that
        // happen to share the same prologue.
        NSUInteger textStart = archOffset + textFileOff;
        NSUInteger textEnd   = textStart + (NSUInteger)textSize;
        if (textEnd > length) textEnd = length;

        NSUInteger matchCount = 0;
        NSUInteger firstMatchOff  = 0;
        NSUInteger secondMatchOff = 0;

        for (NSUInteger off = textStart; off + 8 <= textEnd; off += 4) {
            if (memcmp(bytes + off, prologue, 8) == 0) {
                matchCount++;
                if (matchCount == 1) {
                    firstMatchOff = off;
                } else if (matchCount == 2) {
                    secondMatchOff = off;
                    break;  // we have both — no need to scan further
                }
            }
        }

        if (matchCount < 2) {
            NSLog(@"[RootHide] roothideinit arch %u (%s): found only %lu prologue match(es), expected 2 — skipping",
                  i, is_arm64e ? "arm64e" : "arm64", (unsigned long)matchCount);
            continue;
        }

        // Bounds check
        if (firstMatchOff + patchLen > length || secondMatchOff + patchLen > length) {
            NSLog(@"[RootHide] roothideinit arch %u: patch offset OOB", i);
            continue;
        }

        // Verify prologue bytes (sanity check — already done above but explicit)
        if (memcmp(bytes + firstMatchOff,  prologue, 8) != 0 ||
            memcmp(bytes + secondMatchOff, prologue, 8) != 0) {
            NSLog(@"[RootHide] roothideinit arch %u: prologue verification failed at last moment, skipping", i);
            continue;
        }

        // Apply patches
        memcpy(bytes + firstMatchOff,  patch1, patchLen);
        memcpy(bytes + secondMatchOff, patch2, patchLen);

        patchesApplied++;
        NSLog(@"[RootHide] roothideinit arch %u (%s): patched is_jbroot_name@%lx + resolve@%lx (vaddr 0x%llx + 0x%llx)",
              i, is_arm64e ? "arm64e" : "arm64",
              (unsigned long)firstMatchOff, (unsigned long)secondMatchOff,
              (unsigned long long)(textVirt + (firstMatchOff  - textStart)),
              (unsigned long long)(textVirt + (secondMatchOff - textStart)));
    }

    if (patchesApplied == 0) {
        // No patches applied in this run.  Check whether the dylib has
        // ALREADY been patched (idempotent re-entry) by scanning __text
        // for the patch stubs we would have written.  If found, this
        // means a previous jailbreak already patched the dylib — return
        // success so the caller doesn't abort.
        BOOL alreadyPatched = NO;
        for (uint32_t i = 0; i < nfat && i < 8 && !alreadyPatched; i++) {
            NSUInteger archEntryOff2 = 8 + i * 20;
            if (archEntryOff2 + 20 > length) break;
            uint32_t archOffset2 = rh_u32be(bytes + archEntryOff2 + 8);
            if (archOffset2 + 32 > length) continue;
            uint32_t ncmds2 = rh_u32le(bytes + archOffset2 + 16);
            NSUInteger cmdOff2 = archOffset2 + 32;
            for (uint32_t j = 0; j < ncmds2; j++) {
                if (cmdOff2 + 8 > length) break;
                uint32_t cmd2     = rh_u32le(bytes + cmdOff2);
                uint32_t cmdsize2 = rh_u32le(bytes + cmdOff2 + 4);
                if (cmdsize2 < 8 || cmdOff2 + cmdsize2 > length) break;
                if (cmd2 == 0x19 && cmdsize2 >= 72) {
                    uint32_t nsects2 = rh_u32le(bytes + cmdOff2 + 64);
                    NSUInteger sectOff2 = cmdOff2 + 72;
                    for (uint32_t s = 0; s < nsects2; s++) {
                        if (sectOff2 + 80 > length) break;
                        char sn[17] = {0}, sg[17] = {0};
                        memcpy(sn, bytes + sectOff2, 16);
                        memcpy(sg, bytes + sectOff2 + 16, 16);
                        if (strcmp(sg, "__TEXT") == 0 && strcmp(sn, "__text") == 0) {
                            uint32_t textFileOff2 = rh_u32le(bytes + sectOff2 + 48);
                            uint64_t textSize2    = rh_u64le(bytes + sectOff2 + 40);
                            NSUInteger start = archOffset2 + textFileOff2;
                            NSUInteger end   = start + (NSUInteger)textSize2;
                            if (end > length) end = length;
                            // Search for the arm64 patch stub "mov w0,#1; ret" = 20 00 80 52 c0 03 5f d6
                            // or arm64e stub "pacibsp; mov w0,#1; retab" = 7f 23 03 d5 20 00 80 52 ff 0f 5f d6
                            for (NSUInteger p = start; p + 8 <= end; p++) {
                                if (memcmp(bytes + p, patch_arm64_is_jbroot, 8) == 0) {
                                    alreadyPatched = YES;
                                    break;
                                }
                                if (p + 12 <= end && memcmp(bytes + p, patch_arm64e_is_jbroot, 12) == 0) {
                                    alreadyPatched = YES;
                                    break;
                                }
                            }
                            break;
                        }
                        sectOff2 += 80;
                    }
                }
                cmdOff2 += cmdsize2;
            }
        }
        if (alreadyPatched) {
            NSLog(@"[RootHide] roothideinit.dylib already patched (idempotent), returning success");
            return nil;
        }
        return [NSError errorWithDomain:bootstrapErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey : @"Failed to patch any architecture in roothideinit.dylib"}];
    }

    NSError *writeError = nil;
    [data writeToFile:path options:NSDataWritingAtomic error:&writeError];
    if (writeError) return writeError;

    // NOTE: ldid re-sign is NOT called here.  ldid is itself a RootHide
    // binary that loads libroothide.dylib.  If libroothide.dylib is not
    // yet patched (or is patched but unsigned), ldid will SIGABRT.
    // Re-signing is done later in resignPatchedDylibs (finalizeBootstrap),
    // after BOTH dylibs are patched AND trust-cached.
    chmod(path.fileSystemRepresentation, 0755);

    NSLog(@"[RootHide] patched %lu architectures in roothideinit.dylib", (unsigned long)patchesApplied);
    return nil;
}

// Patch libroothide.dylib: NOP the cbnz instructions after stat() calls
// in __private_jbrootat_alloc to bypass the "stat(JBROOT) == 0" assertion.
//
// ROBUST IMPLEMENTATION:
//   Previous version relied on hard-coded virtual addresses that drifted
//   whenever the RootHide Bootstrap was rebuilt (e.g. text_virt changed
//   from 0x6d78 → 0x6d84 for arm64 and from 0x6c5c → 0x6c64 for arm64e
//   in the 2025-08 bootstrap release).  This caused "No architectures
//   patched" → assertion `stat(JBROOT, &jbrootst) == 0` still fired →
//   jailbreak abort at prep_bootstrap.sh.
//
//   We now locate `_jbrootat_alloc` via LC_SYMTAB by name (the symbol is
//   exported in every shipping RootHide Bootstrap build), then scan the
//   function body for the pattern:
//        bl  <stat_addr>          ; 4 bytes, opcode 0x94/0x97
//        cbnz w0, <assert_lbl>    ; 4 bytes, opcode 0x35xxxxxx
//   and NOP each matching cbnz.  This is invariant to address drift as
//   long as the assertion logic itself isn't restructured.
//   (Helper functions rh_u32be / rh_u32le / rh_u64le are defined near the
//   top of this file, before patchRoothideInitDylib.)

- (NSError *)patchLibroothideDylib
{
    NSString *path = JBROOT_PATH(@"/usr/lib/libroothide.dylib");
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) return nil;

    NSError *readError = nil;
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:path options:0 error:&readError];
    if (!data) return readError;

    uint8_t *bytes = data.mutableBytes;
    NSUInteger length = data.length;

    // NOP instruction = 0xd503201f (bytes: 1f 20 03 d5)
    static const uint8_t nop[4] = {0x1f, 0x20, 0x03, 0xd5};

    uint32_t fatMagic = rh_u32be(bytes);
    if (fatMagic != 0xCAFEBABE) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey : @"libroothide.dylib is not a FAT binary"}];
    }
    uint32_t nfat = rh_u32be(bytes + 4);

    NSUInteger patchesApplied = 0;
    NSUInteger patchesTotal   = 0;  // total cbnz NOPs written across all arches

    for (uint32_t i = 0; i < nfat && i < 8; i++) {
        NSUInteger archEntryOff = 8 + i * 20;
        if (archEntryOff + 20 > length) break;
        uint32_t archOffset = rh_u32be(bytes + archEntryOff + 8);
        if (archOffset + 32 > length) continue;

        uint32_t moMagic = rh_u32le(bytes + archOffset);
        if (moMagic != 0xFEEDFACF) continue;
        uint32_t ncmds   = rh_u32le(bytes + archOffset + 16);
        NSUInteger cmdOff = archOffset + 32;

        // Walk load commands to find:
        //   - __TEXT,__text section (file offset + vaddr + size)
        //   - LC_SYMTAB (symtab offset, nsyms, strtab offset)
        uint64_t textVirt  = 0;
        uint32_t textOff   = 0;
        uint64_t textSize  = 0;
        BOOL haveText      = NO;
        uint32_t symtabOff = 0, symtabNsyms = 0, strtabOff = 0;
        BOOL haveSymtab    = NO;

        for (uint32_t j = 0; j < ncmds; j++) {
            if (cmdOff + 8 > length) break;
            uint32_t cmd     = rh_u32le(bytes + cmdOff);
            uint32_t cmdsize = rh_u32le(bytes + cmdOff + 4);
            if (cmdsize < 8 || cmdOff + cmdsize > length) break;

            if (cmd == 0x19 && cmdsize >= 72) {  // LC_SEGMENT_64
                uint32_t nsects = rh_u32le(bytes + cmdOff + 64);
                NSUInteger sectOff = cmdOff + 72;
                for (uint32_t s = 0; s < nsects; s++) {
                    if (sectOff + 80 > length) break;
                    char sectname[17] = {0};
                    char segname[17]   = {0};
                    memcpy(sectname, bytes + sectOff,      16);
                    memcpy(segname,   bytes + sectOff + 16, 16);
                    if (strcmp(segname, "__TEXT") == 0 && strcmp(sectname, "__text") == 0) {
                        textVirt = rh_u64le(bytes + sectOff + 32);
                        textSize = rh_u64le(bytes + sectOff + 40);
                        textOff  = rh_u32le(bytes + sectOff + 48);
                        haveText = YES;
                    }
                    sectOff += 80;
                }
            } else if (cmd == 0x02 && cmdsize >= 24) {  // LC_SYMTAB
                symtabOff   = rh_u32le(bytes + cmdOff + 8);
                symtabNsyms = rh_u32le(bytes + cmdOff + 12);
                strtabOff   = rh_u32le(bytes + cmdOff + 16);
                haveSymtab  = YES;
            }
            cmdOff += cmdsize;
        }

        if (!haveText) {
            NSLog(@"[RootHide] libroothide arch %u: no __TEXT,__text section, skipping", i);
            continue;
        }

        // --- Step 1: locate _jbrootat_alloc by symbol name -----------------
        // The symbol may be exported as `_jbrootat_alloc` or
        // `__private_jbrootat_alloc` (leading-underscore convention varies).
        // We accept any defined symbol whose name contains "jbrootat_alloc".
        //
        // IMPORTANT: In a FAT Mach-O, the LC_SYMTAB symoff/stroff fields
        // are RELATIVE TO THE SLICE START (archOffset), NOT absolute file
        // offsets.  We must add archOffset whenever we dereference them.
        uint64_t funcVirt = 0;
        BOOL foundFunc = NO;
        if (haveSymtab) {
            NSUInteger symtabAbs = archOffset + (NSUInteger)symtabOff;
            NSUInteger strtabAbs = archOffset + (NSUInteger)strtabOff;
            for (uint32_t k = 0; k < symtabNsyms; k++) {
                NSUInteger nlistOff = symtabAbs + (NSUInteger)k * 16;
                if (nlistOff + 16 > length) break;
                uint32_t strx    = rh_u32le(bytes + nlistOff);
                uint8_t  n_type  = bytes[nlistOff + 4];
                uint8_t  n_sect  = bytes[nlistOff + 5];
                uint64_t n_value = rh_u64le(bytes + nlistOff + 8);

                // N_TYPE mask = 0x0e → N_SECT (defined in some section).
                if ((n_type & 0x0e) != 0x0e) continue;
                if (n_value == 0) continue;
                if (strtabAbs + strx >= length) continue;

                NSUInteger nameStart = strtabAbs + strx;
                NSUInteger nameEnd = nameStart;
                while (nameEnd < length && bytes[nameEnd] != 0) nameEnd++;
                if (nameEnd <= nameStart) continue;

                NSUInteger nameLen = nameEnd - nameStart;
                // Quick filter to avoid strstr'ing every symbol.
                if (nameLen < 14) continue;  // "jbrootat_alloc" is 14 chars
                // Case-insensitive substring search for "jbrootat_alloc".
                BOOL match = NO;
                for (NSUInteger p = 0; p + 14 <= nameLen; p++) {
                    if (strncasecmp((const char *)(bytes + nameStart + p), "jbrootat_alloc", 14) == 0) {
                        match = YES;
                        break;
                    }
                }
                if (!match) continue;

                funcVirt  = n_value;
                foundFunc = YES;
                NSLog(@"[RootHide] libroothide arch %u: found symbol '%.*s' @ 0x%llx (sec=%u)",
                      i, (int)nameLen, bytes + nameStart, (unsigned long long)n_value, n_sect);
                break;
            }
        }

        // Compute the function's file offset & a conservative scan window.
        NSUInteger funcFileOff = 0;
        NSUInteger scanBytes   = 0;
        if (foundFunc) {
            if (funcVirt < textVirt || funcVirt >= textVirt + textSize) {
                NSLog(@"[RootHide] libroothide arch %u: func vaddr 0x%llx outside __text [0x%llx, 0x%llx), skipping",
                      i, (unsigned long long)funcVirt,
                      (unsigned long long)textVirt, (unsigned long long)(textVirt + textSize));
                continue;
            }
            funcFileOff = archOffset + textOff + (NSUInteger)(funcVirt - textVirt);
            // Scan up to 0x400 bytes (256 instructions). The function is
            // typically ~0x140 bytes; we leave ample margin for evolution.
            scanBytes = 0x400;
            if (funcFileOff + scanBytes > length) scanBytes = length - funcFileOff;
        } else {
            // Fallback: scan entire __text section for the bl+cbnz pattern.
            // This is more expensive but works even if the symbol was stripped.
            NSLog(@"[RootHide] libroothide arch %u: symbol _jbrootat_alloc not found, falling back to full __text scan", i);
            funcFileOff = archOffset + textOff;
            scanBytes   = (NSUInteger)textSize;
            if (funcFileOff + scanBytes > length) scanBytes = length - funcFileOff;
        }

        // --- Step 2: scan for `bl <addr> ; cbnz w0, <offset>` pattern -------
        // arm64 instruction encodings (little-endian, 4 bytes each):
        //   bl   <imm26>        : 0b100101 << 26 = 0x94000000 | imm26  → top byte 0x94..0x97
        //   cbnz w0, <imm19>    : 0b00110101 << 24 = 0x35000000 | imm19 → top byte 0x35
        //   cbnz x0, <imm19>    : 0b10110101 << 24 = 0xb5000000 | imm19 → top byte 0xb5
        // We NOP any cbnz w0/x0 that immediately follows a bl, regardless
        // of operands — within the small jbrootat_alloc function these are
        // always the post-stat() assertion guards, never false positives.
        NSUInteger nopsThisArch = 0;
        for (NSUInteger off = 0; off + 8 <= scanBytes; off += 4) {
            uint32_t prev = rh_u32le(bytes + funcFileOff + off);
            uint32_t curr = rh_u32le(bytes + funcFileOff + off + 4);

            BOOL prevIsBl   = ((prev >> 26) == 0x25);  // 0b100101
            BOOL currIsCbnz = ((curr >> 24) == 0x35) || ((curr >> 24) == 0xb5);
            if (!prevIsBl || !currIsCbnz) continue;

            // NOP the cbnz in-place.
            memcpy(bytes + funcFileOff + off + 4, nop, 4);
            nopsThisArch++;
            NSLog(@"[RootHide] libroothide arch %u: NOP'd cbnz@0x%llx (after bl@0x%llx)",
                  i,
                  (unsigned long long)(funcVirt ? funcVirt + off + 4 : 0),
                  (unsigned long long)(funcVirt ? funcVirt + off     : 0));
        }

        if (nopsThisArch > 0) {
            patchesApplied++;
            patchesTotal += nopsThisArch;
        } else {
            NSLog(@"[RootHide] libroothide arch %u: no bl+cbnz pattern found%s, skipping",
                  i, foundFunc ? " in _jbrootat_alloc" : " in __text");
        }
    }

    if (patchesApplied == 0 || patchesTotal == 0) {
        NSLog(@"[RootHide] No architectures patched in libroothide.dylib (continuing)");
        return nil;  // Non-fatal
    }

    NSError *writeError = nil;
    [data writeToFile:path options:NSDataWritingAtomic error:&writeError];
    if (writeError) return writeError;

    // NOTE: ldid re-sign is NOT called here.  See patchRoothideInitDylib
    // for explanation.  Re-signing is done in resignPatchedDylibs.
    chmod(path.fileSystemRepresentation, 0755);

    NSLog(@"[RootHide] patched %lu architectures (%lu total NOPs) in libroothide.dylib",
          (unsigned long)patchesApplied, (unsigned long)patchesTotal);
    return nil;
}

- (NSError *)updateVarJbSymlink
{
    // RootHide does NOT use /var/jb symlink
    // Instead, we ensure the old /var/jb is removed if it exists (from other jailbreaks)
    // and verify that our jbroot path is accessible
    NSError *error;
    
    // Remove /var/jb if it exists (leftover from other jailbreaks)
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/jb" error:nil];
    }
    
    // Verify jbroot is accessible
    NSString *jbrootPath = JBROOT_PATH(@"/");
    if (![[NSFileManager defaultManager] fileExistsAtPath:jbrootPath]) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:BootstrapErrorCodeFailedReplacing 
            userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"jbroot path not accessible: %@", jbrootPath]}];
    }
    
    return nil;
}

- (void)prepareBootstrapWithCompletion:(void (^)(NSError *))completion
{
    [[DOUIManager sharedInstance] sendLog:@"Updating BaseBin" debug:NO];

    // Ensure /private/preboot is mounted writable (Not writable by default on iOS <=15)
    NSError *error = [self ensurePrivatePrebootIsWritable];
    if (error) {
        completion(error);
        return;
    }
    
    // Clean up xinaA15 v1 leftovers if desired
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/.keep_symlinks"]) {
        NSArray *xinaLeftoverSymlinks = @[
            @"/var/jb",  // RootHide does not use /var/jb - remove if exists
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

        // ROOTHIDE: With the correct jbroot path format (.jbroot-XXX),
        // roothideinit.dylib's is_jbroot_name() returns true naturally.
        // No patching needed.  This is a no-op.
        NSError *patchError = [self patchRootHideAssertions];
        if (patchError) {
            NSLog(@"[RootHide] patchRootHideAssertions (post-bootstrap) failed: %@", patchError);
        }

        // Default repositories written on first bootstrap extraction (also
        // refreshed on every full re-extraction). Two files, two formats:
        //
        //   default.sources  — deb822 format, consumed by Sileo (and apt).
        //   default.list     — one-line "deb URI suite component" format,
        //                      consumed by Zebra (older Zebra builds do not
        //                      parse deb822 .sources files).
        //
        // Both carry the same repos. The "1900" suite entries track the
        // RootHide Bootstrap iOS 19 series (Procursus-compatible suites):
        //   - apt.procurs.us          → upstream Procursus bootstraps
        //   - roothide.github.io      → RootHide repo index
        //   - roothide/procursus      → RootHide's own Procursus mirror
        //                                (iphoneos-arm64e/1900)
        //   - RootHide GitHub release → direct-download package root used by
        //                                RootHide releases (1900 strapfiles)
        //   - yourepo.com             → general community repo
        //   - chariz / havoc / bigboss→ standard package repos
        //   - ellekit.space           → ElleKit (tweak hooking runtime)
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
            @"URIs: https://apt.procurs.us/\n"
            @"Suites: 1900\n"
            @"Components: main\n"
            @"\n"
            @"Types: deb\n"
            @"URIs: https://roothide.github.io/procursus/\n"
            @"Suites: iphoneos-arm64e/1900\n"
            @"Components: main\n"
            @"\n"
            @"Types: deb\n"
            @"URIs: https://github.com/roothide/roothide.github.io/releases/download/1900/\n"
            @"Suites: ./\n"
            @"Components:\n"
            @"\n"
            @"Types: deb\n"
            @"URIs: https://roothide.github.io/\n"
            @"Suites: ./\n"
            @"Components:\n"
            @"\n"
            @"Types: deb\n"
            @"URIs: https://yourepo.com/\n"
            @"Suites: ./\n"
            @"Components:\n"
            @"\n"
            @"Types: deb\n"
            @"URIs: https://ellekit.space/\n"
            @"Suites: ./\n"
            @"Components:\n";
        [defaultSources writeToFile:JBROOT_PATH(@"/etc/apt/sources.list.d/default.sources") atomically:NO encoding:NSUTF8StringEncoding error:nil];

        // Zebra-format mirror of the same list. Zebra's SourcesManager reads
        // /etc/apt/sources.list.d/*.list with the classic one-line syntax;
        // writing ONLY a deb822 .sources file leaves Zebra with zero sources
        // on a fresh bootstrap, so keep both files in sync.
        NSString *defaultSourcesList = @"deb https://repo.chariz.com/ ./\n"
            @"deb https://havoc.app/ ./\n"
            @"deb http://apt.thebigboss.org/repofiles/cydia/ stable main\n"
            @"deb https://apt.procurs.us/ 1900 main\n"
            @"deb https://roothide.github.io/procursus/ iphoneos-arm64e/1900 main\n"
            @"deb https://github.com/roothide/roothide.github.io/releases/download/1900/ ./\n"
            @"deb https://roothide.github.io/ ./\n"
            @"deb https://yourepo.com/ ./\n"
            @"deb https://ellekit.space/ ./\n";
        [defaultSourcesList writeToFile:JBROOT_PATH(@"/etc/apt/sources.list.d/default.list") atomically:NO encoding:NSUTF8StringEncoding error:nil];
        
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

        // ROOTHIDE PATCHER FIX: pre-create the Patcher work dirs + enforce
        // mobile ownership + verify patch.sh tools. Delegated to the shared
        // idempotent helper (see ensureRootHidePatcherSupport) which also runs
        // on every finalizeBootstrap and after every dpkg install — previously
        // this block ONLY ran on first-extract, so re-jailbreaks (which skip
        // extraction via .thebootstrapped) never re-applied it and a
        // root-owned patch.sh directory broke folderCheck() again.
        [self ensureRootHidePatcherSupport];

        completion(nil);
    };
    
    
    // Determine whether we need to (re-)extract the bootstrap.
    //
    // ROOTHIDE: RootHide uses .thebootstrapped as the marker file.
    // If .thebootstrapped exists in the jbroot, the bootstrap was already
    // installed in a previous jailbreak → SKIP extraction entirely.
    // This preserves user-installed packages (Sileo, Zebra, tweaks, etc.)
    // across re-jailbreaks.
    //
    // We also check .installed_dopamine for backward compatibility.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dpkgPath = JBROOT_PATH(@"/usr/bin/dpkg");
    BOOL dpkgExists = [fm fileExistsAtPath:dpkgPath];
    NSString *bootstrappedPath = JBROOT_PATH(@"/.thebootstrapped");
    BOOL isBootstrapped = [fm fileExistsAtPath:bootstrappedPath];
    BOOL installedExists = [fm fileExistsAtPath:installedPath];
    BOOL needsBootstrap = !isBootstrapped && !installedExists;
    NSLog(@"[RootHide] prepareBootstrap: .thebootstrapped=%d .installed_dopamine=%d dpkg=%d needsBootstrap=%d",
          isBootstrapped, installedExists, dpkgExists, needsBootstrap);

    // CASE 2: bootstrap was extracted before but with the wrong structure.
    // Force re-extraction so the new RootHide bootstrap replaces the old one.
    if (!needsBootstrap && !dpkgExists) {
        NSString *oldDpkgPath = JBROOT_PATH(@"/var/jb/usr/bin/dpkg");
        if ([fm fileExistsAtPath:oldDpkgPath]) {
            NSLog(@"[RootHide] Detected old Procursus bootstrap structure (dpkg at /var/jb/usr/bin/dpkg). Forcing re-extraction of RootHide bootstrap.");
            [[DOUIManager sharedInstance] sendLog:@"Migrating bootstrap to RootHide structure" debug:NO];

            // Wipe everything except basebin (we keep basebin because the
            // new IPA's basebin.tar will be extracted again anyway in
            // prepareBootstrap, and removing it here could break the
            // currently-running launchdhook).  The bootstrap extraction
            // will overwrite any conflicting files.
            for (NSURL *subItemURL in [fm contentsOfDirectoryAtURL:[NSURL fileURLWithPath:JBROOT_PATH(@"/")] includingPropertiesForKeys:nil options:0 error:nil]) {
                NSString *name = subItemURL.lastPathComponent;
                if (![name isEqualToString:@"basebin"]) {
                    [fm removeItemAtURL:subItemURL error:nil];
                }
            }

            // Remove the marker so the code below re-extracts the bootstrap.
            [fm removeItemAtPath:installedPath error:nil];
            needsBootstrap = YES;
        }
    }

    if (needsBootstrap) {
        // First, wipe any existing content that's not basebin
        for (NSURL *subItemURL in [fm contentsOfDirectoryAtURL:[NSURL fileURLWithPath:JBROOT_PATH(@"/")] includingPropertiesForKeys:nil options:0 error:nil]) {
            if (![subItemURL.lastPathComponent isEqualToString:@"basebin"]) {
                [fm removeItemAtURL:subItemURL error:nil];
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

- (int)installPackage:(NSString *)packagePath
{
    return [self installPackage:packagePath captureError:nil];
}

// Install a .deb package via dpkg -i, capturing BOTH stdout and stderr so we
// can show the user a meaningful error message when dpkg fails.
//
// Why both stdout AND stderr:
//   dpkg writes progress information to stdout and errors/warnings to stderr.
//   The previous version only captured stderr, but stderr was empty in the
//   user's log — meaning either dpkg failed before writing anything, OR it
//   wrote to stdout instead.  We capture both with `> file 2>&1`.
//
// Why --force-all:
//   dpkg exit code 2 = fatal error.  Most common cause when the .deb itself
//   is valid is a dependency/conflict check failure.  RootHide Bootstrap
//   ships its own libiosexec1 / libkrw0 etc., and our bundled packages
//   (libroot-dopamine, libkrw0-dopamine) might have version conflicts with
//   the pre-installed ones.  --force-all bypasses all dependency/conflict
//   checks so installation succeeds even if versions don't match exactly.
//   This matches what Sileo/Zebra do when force-installing a package.
//
// Why we no longer pass --admindir:
//   RootHide Bootstrap ships its dpkg database at
//     <jbroot>/var/lib/dpkg -> .jbroot/Library/dpkg
//   (relative symlink).  When dpkg is launched from a process whose CWD
//   is <jbroot> (which is the case after launchdhook chdirs there), the
//   relative symlink resolves correctly.  Passing --admindir=<absolute path>
//   actually broke things because the absolute path went through the
//   symlink twice.  We let dpkg find its admindir the default way.
- (int)installPackage:(NSString *)packagePath captureError:(NSString **)errorOut
{
    NSString *dpkgPath = [NSString stringWithUTF8String:JBROOT_PATH("/usr/bin/dpkg")];

    // Use /tmp/ instead of NSTemporaryDirectory() — /tmp is always writable
    // by root and doesn't have sandbox restrictions that NSTemporaryDirectory()
    // might have for the app container.
    NSString *outFile = [NSString stringWithFormat:@"/tmp/dpkg_out_%d.txt", getpid()];
    NSString *errFile = [NSString stringWithFormat:@"/tmp/dpkg_err_%d.txt", getpid()];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:outFile error:nil];
    [fm removeItemAtPath:errFile error:nil];

    // Verify the .deb file exists and is readable before invoking dpkg.
    if (![fm fileExistsAtPath:packagePath]) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"Package file does not exist: %@", packagePath];
        return -100;
    }
    if (![fm fileExistsAtPath:dpkgPath]) {
        if (errorOut) *errorOut = [NSString stringWithFormat:@"dpkg binary does not exist at %@", dpkgPath];
        return -101;
    }

    // ROOT CAUSE of dpkg exit 2 with no output:
    //   We were running dpkg via system "/bin/sh -c ...", but the system
    //   /bin/sh doesn't have DYLD_LIBRARY_PATH set to <jbroot>/usr/lib/.
    //   dpkg is dynamically linked and needs libdpkg.so, libzstd.so, etc.
    //   from <jbroot>/usr/lib/. Without the library path, dyld can't find
    //   them → dpkg crashes with SIGKILL before producing any output.
    //
    // FIX:
    //   Run dpkg DIRECTLY (not through /bin/sh) using exec_cmd_trusted,
    //   which calls jbclient_trust_file_by_path first (to add dpkg's
    //   CDHash to the trust cache) then posix_spawn.
    //
    //   We set DYLD_LIBRARY_PATH to <jbroot>/usr/lib/ so dyld can find
    //   the shared libraries.  We also set PATH and HOME for dpkg's
    //   postinst scripts.
    //
    //   This matches how RootHide Bootstrap runs dpkg:
    //     spawn_bootstrap_binary({"/usr/bin/dpkg", "-i", ...})
    //   which uses spawn_common (persona override + DYLD_INSERT_LIBRARIES).

    // ROOT CAUSE of dpkg exit 2 with no output:
    //   dpkg is dynamically linked and needs libdpkg.so, libzstd.so, etc.
    //   from <jbroot>/usr/lib/.  Setting DYLD_LIBRARY_PATH doesn't work on
    //   iOS 16+ (AMFI strips it).  RootHide solves this with
    //   DYLD_INSERT_LIBRARIES=<jbroot>/basebin/bootstrap.dylib which hooks
    //   dyld to redirect lookups.
    //
    //   We don't have bootstrap.dylib, BUT we can run dpkg via the
    //   jbroot's /bin/sh which has the correct rpath/DYLD setup.
    //   prep_bootstrap.sh ran successfully this way, so dpkg should too.
    //
    //   We use exec_cmd_trusted to run jbroot's /bin/sh -c "dpkg -i ..."
    //   The jbroot /bin/sh resolves libraries via rpath correctly.
    NSString *jbrootLib = [NSString stringWithUTF8String:JBROOT_PATH("/usr/lib")];
    NSString *jbrootBin = [NSString stringWithUTF8String:JBROOT_PATH("/usr/bin")];
    NSString *jbrootSbin = [NSString stringWithUTF8String:JBROOT_PATH("/usr/sbin")];
    setenv("PATH", [NSString stringWithFormat:@"%@:%@:%@:/usr/bin:/bin:/usr/sbin:/sbin",
                     jbrootBin, jbrootSbin, jbrootLib].UTF8String, 1);
    setenv("HOME", "/var/root", 1);
    setenv("DPKG_ADMINDIR", [NSString stringWithUTF8String:JBROOT_PATH("/var/lib/dpkg")].UTF8String, 1);
    setenv("TMPDIR", "/tmp", 1);

    // Build dpkg command with output redirection
    NSString *cmd = [NSString stringWithFormat:
        @"\"%@\" -i --force-all \"%@\" >\"%@\" 2>\"%@\"",
        dpkgPath, packagePath, outFile, errFile];

    NSLog(@"[installPackage] running via jbroot sh: %@", cmd);
    [[DOUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"dpkg -i %@", packagePath.lastPathComponent] debug:YES];

    // Run dpkg via JBROOT's /bin/sh (not system /bin/sh).
    // The jbroot /bin/sh has correct rpath to find libraries.
    int r = exec_cmd_trusted(JBROOT_PATH("/bin/sh"),
                             "-c", cmd.UTF8String, NULL);

    NSLog(@"[installPackage] dpkg exit code: %d", r);

    if (errorOut) {
        NSError *readErr = nil;
        NSString *outContent = [NSString stringWithContentsOfFile:outFile encoding:NSUTF8StringEncoding error:&readErr];
        NSString *errContent = [NSString stringWithContentsOfFile:errFile encoding:NSUTF8StringEncoding error:&readErr];
        NSMutableArray *parts = [NSMutableArray new];
        if (outContent.length > 0) {
            [parts addObject:[NSString stringWithFormat:@"[stdout]\n%@", outContent]];
        }
        if (errContent.length > 0) {
            [parts addObject:[NSString stringWithFormat:@"[stderr]\n%@", errContent]];
        }
        if (parts.count > 0) {
            *errorOut = [parts componentsJoinedByString:@"\n\n"];
        } else {
            *errorOut = [NSString stringWithFormat:@"(no output captured, exit=%d)", r];
        }
    }
    [fm removeItemAtPath:outFile error:nil];
    [fm removeItemAtPath:errFile error:nil];
    return r;
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
        NSString *debPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:packageManagerDict[@"Package"]];
        NSString *name = packageManagerDict[@"Display Name"];
        NSString *bundleID = packageManagerDict[@"Key"];

        // FIX: check binary đã tồn tại chưa. Nếu rồi → skip để tránh reinstall
        // không cần thiết + tránh uicache chạy lại (lâu).
        NSString *appPath = [NSString stringWithFormat:@"/Applications/%@.app", name];
        NSString *realAppPath = JBROOT_PATH(appPath);
        NSString *infoPlistPath = [realAppPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
        NSString *executableName = infoPlist[@"CFBundleExecutable"] ?: name;
        NSString *executablePath = [realAppPath stringByAppendingPathComponent:executableName];

        BOOL binaryExists = [[NSFileManager defaultManager] fileExistsAtPath:executablePath];
        NSString *installedVersion = [self installedVersionForPackageWithIdentifier:bundleID];
        BOOL shouldInstall = !installedVersion || !binaryExists;

        NSLog(@"[RootHide] installPackageManagers: %@ (bundleID=%@ version=%@ binary=%d -> shouldInstall=%d)",
              name, bundleID, installedVersion, binaryExists, shouldInstall);

        if (!shouldInstall) {
            NSLog(@"[RootHide] %@ already installed — re-trust-cache binary only (defensive)", name);
            // Defensive: trust-cache lại (cdhash có thể bị mất sau reboot)
            [self trustCacheAppBinariesAfterInstall:name];
            // Refresh icon (uicache idempotent)
            exec_cmd_trusted(JBROOT_PATH("/usr/bin/uicache"), "-p", appPath.UTF8String, NULL);
            continue;
        }

        NSLog(@"[RootHide] Installing %@ from %@", name, debPath);

        // ============================================================
        // FIX CRASH (per video RPReplay_Final1787506627.mp4):
        // Trước đây dùng manuallyInstallDeb (parse .deb in-process, extract
        // data.tar.xz 3.9MB qua libarchive_unarchive) → app bị SIGKILL ngay
        // sau khi install xong, trước khi reach được rebootUserspace.
        //
        // Root cause analysis (5 Whys):
        // 1. Tại sao crash? → App SIGKILL sau log "kernel primitives still valid"
        // 2. Tại sao SIGKILL? → Jetsam hoặc AMFI kill do RAM spike từ NSData
        //    buffers của manuallyInstallDeb (debData 4MB + dataTarData 4MB +
        //    libarchive buffers 20MB+).
        // 3. Tại sao upstream opa334/Dopamine không bị? → Upstream dùng
        //    `dpkg -i` (exec_cmd_trusted spawn binary ngoài, RAM tốn trong
        //    child process, không tốn RAM của Dopamine app).
        // 4. Tại sao fork dùng manuallyInstallDeb? → Để handle case dpkg
        //    chưa được trust-cached khi finalizeBootstrap chạy. Nhưng
        //    prep_bootstrap.sh (Step 2) đã install dpkg + trust-cache nó,
        //    nên dpkg đã available ở Step 4.
        // 5. Tại sao vẫn giữ ensureJbrootSymlinksInApps + trustCache? → Vì
        //    dpkg postinst script của Sileo/RootHide không tự tạo .jbroot
        //    symlink cho .app dirs (roothide-specific). Phải làm thủ công.
        //
        // FIX: Dùng `dpkg -i` (exec_cmd_trusted spawn binary ngoài, match
        // upstream opa334). Sau khi dpkg install xong, gọi:
        //   1. trustCacheAppBinariesAfterInstall (roothide-specific, trust-cache
        //      binary + .dylib trong .app/Frameworks/)
        //   2. ensureJbrootSymlinksInApps (roothide-specific, tạo .jbroot
        //      symlink trong mỗi .app dir để dyld load libroothide.dylib)
        // ============================================================

        // Path 1 (preferred): dpkg -i (match upstream opa334)
        // exec_cmd_trusted sẽ:
        //   1. jbclient_trust_file_by_path(dpkg_path) — trust-cache dpkg binary
        //   2. posix_spawn dpkg với uid=0 (runAsRoot context đã có)
        //   3. waitpid đợi dpkg exit
        int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"),
                                  "-i", "--force-all",
                                  debPath.fileSystemRepresentation, NULL);
        NSLog(@"[RootHide] dpkg -i %@ exit code: %d", name, r);
        fflush(stderr);

        if (r != 0) {
            // Fallback: manuallyInstallDeb (cho case dpkg chưa available)
            NSLog(@"[RootHide] dpkg -i failed (%d), falling back to manuallyInstallDeb", r);
            fflush(stderr);
            NSError *installError = [self manuallyInstallDeb:debPath appName:name];
            if (installError) {
                NSLog(@"[RootHide] Failed to install %@ (continuing — non-fatal): %@", name, installError);
                continue;
            }
        } else {
            // dpkg -i thành công → vẫn cần trust-cache + symlinks (roothide-specific)
            [self trustCacheAppBinariesAfterInstall:name];
            [self ensureRootHidePatcherSupport];
        }

        // Run uicache to refresh the app icon
        NSLog(@"[RootHide] uicache -p %@", appPath);
        exec_cmd_trusted(JBROOT_PATH("/usr/bin/uicache"), "-p", appPath.UTF8String, NULL);
    }
    return nil;
}

// Manually install a .deb package without using the dpkg binary.
// Parses the .deb ar archive in pure ObjC, extracts data.tar,
// then uses libarchive to extract files to <jbroot>/.
//
// FIX LỖI 2 + 3: Helper trust-cache mọi binary + dylib + framework trong .app
// sau khi install. Hàm này:
// 1. Tìm .app directory vừa install (theo appName hoặc scan /Applications)
// 2. Đọc Info.plist để lấy CFBundleExecutable
// 3. Trust-cache binary chính + tất cả .dylib/.framework trong Frameworks/
//
// Đặt helper NÀY (không phải trong manuallyInstallDeb) để tránh duplicate code
// giữa manuallyInstallDeb và installPackageManagers.
- (void)trustCacheAppBinariesAfterInstall:(NSString *)appName
{
    NSFileManager *fm = [NSFileManager defaultManager];

    // Tìm .app directory: thử nhiều vị trí
    // 1. <jbroot>/Applications/<appName>.app
    // 2. <jbroot>/Applications/RootHide.app (đặc biệt cho RootHide Manager)
    NSArray *candidateNames = @[
        [NSString stringWithFormat:@"/Applications/%@.app", appName],
        @"/Applications/RootHide.app",  // hardcoded fallback cho RootHide Manager
    ];

    for (NSString *appBundlePath in candidateNames) {
        NSString *realAppBundlePath = JBROOT_PATH(appBundlePath);
        if (![fm fileExistsAtPath:realAppBundlePath]) continue;

        // Lấy executable name từ Info.plist
        NSString *infoPlistPath = [realAppBundlePath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
        NSString *executableName = infoPlist[@"CFBundleExecutable"] ?: appName;

        // Trust-cache binary chính
        NSString *executablePath = [realAppBundlePath stringByAppendingPathComponent:executableName];
        if ([fm fileExistsAtPath:executablePath]) {
            // ROOTHIDE PATCHER FIX: use the recurse path (same one systemhook uses
            // at spawn time) instead of the flat by_path trust. RootHidePatcher's
            // main executable links libroothide.dylib via
            // @loader_path/.jbroot/usr/lib/libroothide.dylib and shells out to
            // jbroot("/usr/bin/bash"); the flat trust only registered the main
            // cdhash and never normalized the developer-certificate slices, so on
            // iOS 17+ (SPTM/TXM) the app launched but its dylibs / spawned tools
            // were untrusted → AMFI killed them and the convert silently produced
            // no output. recurse collects the executable AND its dependent
            // libraries and runs ensure_randomized_cdhash_for_slice on each.
            int tcR = jbclient_trust_executable_recurse(executablePath.fileSystemRepresentation, NULL);
            if (tcR != 0) {
                tcR = jbclient_trust_file_by_path(executablePath.fileSystemRepresentation);
            }
            NSLog(@"[RootHide] trust-cache %@/%@ (binary, recurse): %d", appName, executableName, tcR);
        }

        // Trust-cache tất cả .dylib trong Frameworks/
        NSString *frameworksPath = [realAppBundlePath stringByAppendingPathComponent:@"Frameworks"];
        if ([fm fileExistsAtPath:frameworksPath]) {
            for (NSString *item in [fm contentsOfDirectoryAtPath:frameworksPath error:nil]) {
                if ([item hasSuffix:@".dylib"] || [item hasSuffix:@".framework"]) {
                    NSString *itemPath = [frameworksPath stringByAppendingPathComponent:item];
                    jbclient_trust_executable_recurse(itemPath.fileSystemRepresentation, NULL);
                }
            }
        }

        // Trust-cache tất cả .dylib ngoài cùng trong .app (một số app sign thẳng dylib trong .app)
        for (NSString *item in [fm contentsOfDirectoryAtPath:realAppBundlePath error:nil]) {
            if ([item hasSuffix:@".dylib"]) {
                NSString *itemPath = [realAppBundlePath stringByAppendingPathComponent:item];
                jbclient_trust_executable_recurse(itemPath.fileSystemRepresentation, NULL);
            }
        }

        // ROOTHIDE PATCHER FIX: RootHidePatcher ships Mach-O helper tools in a
        // top-level "cctools" directory (otool, strings, install_name_tool) and
        // prepends <bundle>/cctools to PATH when running patch.sh. Those are
        // executed as child processes, so each must be executable AND trusted or
        // AMFI kills them mid-conversion (the "convert does nothing" symptom).
        NSString *cctoolsPath = [realAppBundlePath stringByAppendingPathComponent:@"cctools"];
        if ([fm fileExistsAtPath:cctoolsPath]) {
            for (NSString *tool in [fm contentsOfDirectoryAtPath:cctoolsPath error:nil]) {
                NSString *toolPath = [cctoolsPath stringByAppendingPathComponent:tool];
                chmod(toolPath.fileSystemRepresentation, 0755);
                int tr = jbclient_trust_executable_recurse(toolPath.fileSystemRepresentation, NULL);
                if (tr != 0) {
                    jbclient_trust_file_by_path(toolPath.fileSystemRepresentation);
                }
                NSLog(@"[RootHide] trust-cache %@/cctools/%@: %d", appName, tool, tr);
            }
        }

        // ROOTHIDE PATCHER FIX: patch.sh is copied into the .app bundle and run
        // through bash. Ensure it is executable so the conversion can start.
        NSString *patchScript = [realAppBundlePath stringByAppendingPathComponent:@"patch.sh"];
        if ([fm fileExistsAtPath:patchScript]) {
            chmod(patchScript.fileSystemRepresentation, 0755);
        }

        break; // chỉ process .app đầu tiên tìm thấy
    }
}

// Manually install a .deb package without using the dpkg binary.
// Parses the .deb ar archive in pure ObjC, extracts data.tar,
// then uses libarchive to extract files to <jbroot>/.
- (NSError *)manuallyInstallDeb:(NSString *)debPath appName:(NSString *)appName
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:debPath]) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:-1
                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Deb file not found: %@", debPath]}];
    }

    // Read the entire .deb file into memory
    NSError *readError = nil;
    NSData *debData = [NSData dataWithContentsOfFile:debPath options:0 error:&readError];
    if (!debData) {
        return readError ?: [NSError errorWithDomain:bootstrapErrorDomain code:-1
                                          userInfo:@{NSLocalizedDescriptionKey: @"Failed to read deb file"}];
    }

    // Parse the ar archive format to find data.tar.* and control.tar.*
    // ar format: 8-byte magic "!<arch>\n", then 60-byte headers + file data
    const uint8_t *bytes = debData.bytes;
    NSUInteger length = debData.length;

    // Verify magic
    if (length < 8 || memcmp(bytes, "!<arch>\n", 8) != 0) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:-1
                               userInfo:@{NSLocalizedDescriptionKey: @"Not a valid ar archive (bad magic)"}];
    }

    NSData *dataTarData = nil;
    NSData *controlTarData = nil;
    NSString *dataTarName = nil;

    NSUInteger pos = 8; // skip magic
    while (pos + 60 <= length) {
        // Parse ar header (60 bytes)
        char name[17] = {0};
        memcpy(name, bytes + pos, 16);
        // Trim trailing spaces
        for (int i = 15; i >= 0 && name[i] == ' '; i--) name[i] = 0;

        // Parse size (10 bytes at offset 48)
        char sizeStr[11] = {0};
        memcpy(sizeStr, bytes + pos + 48, 10);
        unsigned long fileSize = strtoul(sizeStr, NULL, 10);

        // Skip header (60 bytes) to get to file data
        NSUInteger dataStart = pos + 60;
        if (dataStart + fileSize > length) break;

        NSString *entryName = [NSString stringWithUTF8String:name];
        // Remove trailing slash from BSD format names
        entryName = [entryName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        NSLog(@"[RootHide] ar entry: %@ (size=%lu)", entryName, fileSize);

        if ([entryName hasPrefix:@"data.tar"]) {
            dataTarData = [debData subdataWithRange:NSMakeRange(dataStart, fileSize)];
            dataTarName = entryName;
        } else if ([entryName hasPrefix:@"control.tar"]) {
            controlTarData = [debData subdataWithRange:NSMakeRange(dataStart, fileSize)];
        }

        // Move to next entry (file data padded to even boundary)
        pos = dataStart + fileSize;
        if (pos % 2 != 0) pos++; // padding byte
    }

    if (!dataTarData) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:-1
                               userInfo:@{NSLocalizedDescriptionKey: @"data.tar not found in .deb file"}];
    }

    NSLog(@"[RootHide] Found %@ (%lu bytes)", dataTarName, (unsigned long)dataTarData.length);

    // Write data.tar to a temp file
    // iOS 18.3 watchdog/crash .ips (4d16e66b…, bug 309, EXC_BREAKPOINT in
    // _NSDescriptionWithStringProxyFunc under +[NSString stringWithFormat:] at
    // manuallyInstallDeb+3060): the crashing frame was the tarCmd format below.
    // At that point the STRING arguments were valid, but the runtime trap fired
    // because the process was in a torn state after the 1c973e0 spawn-hook
    // regression poisoned the surrounding bootstrap (dpkg -i failed -> this
    // fallback ran -> one more poisoned spawn chain). Two defenses now:
    //   1. The spawn-hook regression itself is fixed (85e5426), so this
    //      fallback should rarely even run.
    //   2. Every format argument is re-derived into plain UTF-8 C strings and
    //      checked before formatting, so a nil/unparseable path can no longer
    //      reach %@ and trap the runtime.
    NSString *tarPathForCmd = JBROOT_PATH(@"/bin/tar") ?: @"";
    NSString *jbrootPath = [NSString stringWithUTF8String:JBROOT_PATH("/")];
    if (!jbrootPath || jbrootPath.length == 0) {
        NSLog(@"[RootHide] manuallyInstallDeb: jbroot unavailable — skipping tar fallback");
        return [NSError errorWithDomain:bootstrapErrorDomain code:-1
                               userInfo:@{NSLocalizedDescriptionKey: @"jbroot unavailable during deb fallback"}];
    }
    NSString *tmpDir = [NSString stringWithFormat:@"/tmp/deb_%d", getpid()];
    [fm createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *dataTarPath = [tmpDir stringByAppendingPathComponent:dataTarName];
    [dataTarData writeToFile:dataTarPath atomically:YES];

    // Extract data.tar to jbroot using libarchive
    // libarchive can handle xz, gzip, lzma compression automatically
    NSLog(@"[RootHide] Extracting data.tar to %@", jbrootPath);

    // Write data.tar and use libarchive_unarchive to extract
    int extractRet = libarchive_unarchive(dataTarPath.fileSystemRepresentation,
                                          jbrootPath.fileSystemRepresentation);
    if (extractRet != 0) {
        NSLog(@"[RootHide] libarchive extraction failed (%d), trying jbroot tar", extractRet);
        // Fallback: use jbroot's /bin/tar (via /bin/sh). Guard every argument —
        // this whole block runs on the recovery path, so it must never throw.
        if (tarPathForCmd.length > 0 && dataTarPath.length > 0) {
            NSString *tarCmd = [[NSString alloc] initWithFormat:@"\"%@\" -xf \"%@\" -C \"%@\"",
                                tarPathForCmd, dataTarPath, jbrootPath];
            if (tarCmd) {
                int tarRet = exec_cmd_trusted(JBROOT_PATH("/bin/sh"), "-c", tarCmd.UTF8String, NULL);
                if (tarRet != 0) {
                    NSLog(@"[RootHide] jbroot tar also failed (%d)", tarRet);
                }
            }
        }
    }

    // FIX LỖI 2 + 3 (CRITICAL): Trust-cache binary của app NGAY sau khi extract.
    //
    // Tại sao CẦN làm điều này TRONG manuallyInstallDeb (không chờ caller):
    // - Caller (installPackageManagers / finalizeBootstrap) có thể gọi uicache
    //   ngay sau khi manuallyInstallDeb return.
    // - uicache spawn app để lấy bundle info → nếu binary có CMS signature
    //   (dev-cert, như RootHide Manager app) và chưa được trust-cached →
    //   AMFI SIGKILL → uicache cũng crash → JB abort.
    // - Đặt trust-cache Ở ĐÂY đảm bảo dù caller làm gì sau đó, binary vẫn
    //   launch được.
    //
    // Tại sao KHÔNG return error nếu trust-cache fail:
    // - Trust-cache fail không phải lý do để fail toàn bộ install. Files đã
    //   được extract, dpkg status đã update. Caller có thể retry trust-cache
    //   sau (trustCacheBootstrapBinaries sẽ scan lại toàn bộ /Applications).
    // - Trả error sẽ làm JB abort → user không vào được springboard → khó debug.
    [self trustCacheAppBinariesAfterInstall:appName];

    // Parse control file if available
    if (controlTarData) {
        NSString *controlTarPath = [tmpDir stringByAppendingPathComponent:@"control.tar"];
        [controlTarData writeToFile:controlTarPath atomically:YES];

        // Extract control file from control.tar
        NSString *controlTmpDir = [tmpDir stringByAppendingPathComponent:@"control"];
        [fm createDirectoryAtPath:controlTmpDir withIntermediateDirectories:YES attributes:nil error:nil];
        libarchive_unarchive(controlTarPath.fileSystemRepresentation,
                             controlTmpDir.fileSystemRepresentation);

        NSString *controlContent = [NSString stringWithContentsOfFile:[controlTmpDir stringByAppendingPathComponent:@"control"]
                                                            encoding:NSUTF8StringEncoding error:nil];

        if (controlContent) {
            // Update dpkg status file
            NSString *statusFile = JBROOT_PATH(@"/var/lib/dpkg/status");
            [fm createDirectoryAtPath:JBROOT_PATH(@"/var/lib/dpkg") withIntermediateDirectories:YES attributes:nil error:nil];

            NSArray *controlLines = [controlContent componentsSeparatedByString:@"\n"];
            NSString *packageLine = controlLines.count > 0 ? controlLines[0] : @"Package: unknown";

            NSString *existing = [NSString stringWithContentsOfFile:statusFile encoding:NSUTF8StringEncoding error:nil];
            if (!existing || ![existing containsString:packageLine]) {
                NSString *statusEntry = [NSString stringWithFormat:
                    @"\n%@\nStatus: install ok installed\nPriority: optional\nSection: Packaging\n%@\n\n",
                    packageLine, controlContent];
                // Append to status file
                if (existing) {
                    [existing writeToFile:statusFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:statusFile];
                    // FIX BUG #6 (null-check): fh có thể nil nếu statusFile không tồn tại
                    // hoặc permission denied. Gọi [fh seekToEndOfFile] với nil sẽ crash.
                    if (fh) {
                        @try {
                            [fh seekToEndOfFile];
                            [fh writeData:[statusEntry dataUsingEncoding:NSUTF8StringEncoding]];
                            [fh closeFile];
                        } @catch (NSException *e) {
                            NSLog(@"[RootHide] WARNING: failed to write dpkg status for %@: %@", appName, e);
                            [fh closeFile];
                        }
                    } else {
                        // Fallback: ghi nguyên file (không append)
                        [statusEntry writeToFile:statusFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    }
                } else {
                    [statusEntry writeToFile:statusFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
            }
        }
    }

    // Cleanup
    [fm removeItemAtPath:tmpDir error:nil];

    NSLog(@"[RootHide] Successfully installed %@ (manual extraction)", appName);

    // ROOTHIDE: After installing the .deb, ensure every .app directory inside
    // <jbroot>/Applications/ has a `.jbroot` symlink pointing back to <jbroot>.
    //
    // WHY: Sileo, Zebra, RootHide Manager, and any other RootHide-aware app
    // have an LC_LOAD_DYLIB entry like:
    //   @loader_path/.jbroot/usr/lib/libroothide.dylib
    // When dyld loads the binary, @loader_path is the .app directory itself,
    // so dyld looks for:  <app_dir>/.jbroot/usr/lib/libroothide.dylib
    //
    // The RootHide Bootstrap tarball ships with a `.jbroot -> .` symlink at
    // the ROOT of the bootstrap (= <jbroot>/.jbroot), which only helps
    // binaries located directly in <jbroot>/ (e.g. <jbroot>/bin/dpkg).
    // It does NOT help binaries in subdirectories like
    // <jbroot>/Applications/Sileo.app/Sileo.
    //
    // For those, we MUST create a separate .jbroot symlink inside each .app
    // directory. The correct relative path from <jbroot>/Applications/Foo.app/
    // back to <jbroot>/ is "../.." (one .. to <jbroot>/Applications/, another
    // .. to <jbroot>/).
    //
    // Without this symlink, the moment Sileo/Zebra/RootHideManager is
    // launched, dyld fails to load libroothide.dylib and the app crashes
    // before main() even runs (the user perceives this as "app crashes on
    // open" right after jailbreak).
    //
    // We re-sweep ALL .app dirs (not just the one we just installed) so
    // that apps the user installed separately via dpkg -i also get the
    // symlink on the next jailbreak cycle.
    [self ensureRootHidePatcherSupport];

    return nil;
}

// ============================================================================
// ROOTHIDE PATCHER SUPPORT (runs on EVERY jailbreak, not just first extract)
// ============================================================================
// RootHidePatcher 2.1.4 flow and why each piece must exist BEFORE the user
// opens the app:
//
//   1. -[Derootifier_ShellScript folderCheck] (Patcher's ContentView.onAppear)
//      does fileExists(jbroot("/var/mobile/RootHidePatcher/.Inbox")) and on
//      miss does createDirectory(withIntermediateDirectories:YES) — as uid 501
//      INSIDE the app sandbox. Two independent failure modes produce the alert
//      "Error! There was a problem with making the folder for the deb.":
//        a) /var/mobile/RootHidePatcher does not exist yet. The checkin
//           sandbox extension covers <jbroot>/var/mobile, but the extension
//           was issued by name at check-in time; when the directory tree was
//           created by an earlier root-context run (dpkg postinst / patch.sh
//           running as root via the persona fix) the subdirectory is root-
//           owned and mkdir fails with EPERM for mobile.
//        b) The directory exists but is owned by root:mobile (created by
//           patch.sh, which runs as root) — mode 0755 leaves mobile unable
//           to create .Inbox inside it.
//      Both are fixed by pre-creating the tree 501:501 and force-chowning
//      any pre-existing root-owned copies on every jailbreak.
//
//   2. patch.sh hard-gates on dpkg-deb / file / awk / ldid and later calls
//      install_name_tool, plutil, sed, find, mktemp, realpath, sw_vers,
//      whoami. The RootHide bootstrap straps (1800 AND 1900, verified) ship
//      dpkg-deb/ldid/bash/sed/find/mktemp/realpath/sw_vers/whoami but NOT
//      file, awk (any variant) or plutil, and otool needs
//      @rpath/libxar.1.dylib (libxar1) which is also absent. Those four only
//      arrive via the Patcher deb's Depends when installed through Sileo —
//      a raw `dpkg -i` skips Depends entirely. We can't install them from
//      the JB app (they're not bundled), so surface a user-visible warning
//      listing exactly what to install instead of the UI swallowing the
//      failure as a bare "Error(1)".
//
//   3. The Patcher deb's postinst is a best-effort no-op (`chown ... || true`)
//      and the deb itself contains no /var/mobile paths, so nothing in the
//      package creates this tree — it must be bootstrapped from here.
//
// Idempotent and cheap: a handful of stat/createDirectory/chown calls.
- (void)ensureRootHidePatcherSupport
{
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];

        // --- 1. Pre-create + enforce mobile ownership of the Patcher work dirs
        NSArray<NSString *> *patcherDirs = @[
            @"/var/mobile/RootHidePatcher",
            @"/var/mobile/RootHidePatcher/.Inbox",
            @"/var/mobile/RootHidePatcher/output",
            @"/var/mobile/RootHidePatcher/tmp",
            @"/var/mobile/RootHidePatcher/.cache",
            @"/var/tmp/com.roothide.patcher-Inbox",
        ];
        for (NSString *relDir in patcherDirs) {
            NSString *dirAbs = JBROOT_PATH(relDir);
            BOOL isDirectory = NO;
            BOOL exists = [fm fileExistsAtPath:dirAbs isDirectory:&isDirectory];
            if (!exists) {
                NSDictionary<NSFileAttributeKey, id> *attrs = @{
                    NSFilePosixPermissions : @0755,
                    NSFileOwnerAccountID : @501,
                    NSFileGroupOwnerAccountID : @501,
                };
                NSError *mkErr = nil;
                if (![fm createDirectoryAtPath:dirAbs
                   withIntermediateDirectories:YES
                                    attributes:attrs
                                         error:&mkErr]) {
                    NSLog(@"[RootHide] PATCHER: pre-create %@ failed: %@", dirAbs, mkErr);
                }
            } else if (isDirectory) {
                // Force mobile ownership non-recursively; patch.sh (running as
                // root via persona fix) recreates these with root ownership.
                // The top-level dir must be mobile-writable or folderCheck()'s
                // createDirectory(.Inbox) throws inside the app sandbox.
                chown(dirAbs.fileSystemRepresentation, 501, 501);
            }
        }
        // The extracted-deb trees patch.sh leaves under .Inbox are root-owned
        // (patch.sh runs as root); chown them so the NEXT import can clean them.
        NSString *inboxAbs = JBROOT_PATH(@"/var/mobile/RootHidePatcher/.Inbox");
        NSDirectoryEnumerator *inboxEnum = [fm enumeratorAtURL:[NSURL fileURLWithPath:inboxAbs]
                                    includingPropertiesForKeys:nil options:0 errorHandler:nil];
        for (NSURL *itemURL in inboxEnum) {
            chown(itemURL.path.fileSystemRepresentation, 501, 501);
        }

        // --- 2. Ensure app-level + nested .jbroot symlinks (covers cctools)
        [self ensureJbrootSymlinksInApps];

        // --- 3. Verify patch.sh tool availability; warn loudly when missing
        NSArray<NSString *> *patcherToolPaths = @[
            @"/usr/bin/bash", @"/usr/bin/dpkg-deb", @"/usr/bin/file", @"/usr/bin/awk",
            @"/usr/bin/ldid", @"/usr/bin/otool", @"/usr/bin/install_name_tool",
            @"/usr/bin/plutil", @"/usr/bin/mktemp", @"/usr/bin/realpath",
            @"/usr/bin/sw_vers", @"/usr/bin/whoami", @"/usr/bin/find", @"/usr/bin/sed",
        ];
        NSMutableString *missing = [NSMutableString string];
        for (NSString *toolRelPath in patcherToolPaths) {
            NSString *toolAbsPath = JBROOT_PATH(toolRelPath);
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:toolAbsPath isDirectory:&isDir] || isDir) {
                [missing appendFormat:@" %@", toolRelPath];
            }
        }
        if (missing.length > 0) {
            NSString *warn = [NSString stringWithFormat:
                @"PATCHER: thiếu công cụ cho patch.sh:%@ — cài qua Sileo "
                @"(file, gawk, plutil, libxar1) hoặc convert sẽ báo Error", missing];
            NSLog(@"[RootHide] PATCHER WARNING:%@", warn);
            [[DOUIManager sharedInstance] sendLog:warn debug:NO];
        } else {
            NSLog(@"[RootHide] PATCHER: all patch.sh dependencies present");
        }

        // --- 4. PATCHER IMPORT DIAGNOSTICS: if the Patcher app was opened
        // since the last jailbreak, its systemhook probes appended results to
        // /var/mobile/.patcher_diag.log. Surface the latest launch's probes so
        // the silent DocumentPicker import failure becomes visible.
        NSString *diagPath = JBROOT_PATH(@"/var/mobile/RootHidePatcher/.patcher_diag.log");
        NSString *diagContents = [NSString stringWithContentsOfFile:diagPath
                                                           encoding:NSUTF8StringEncoding
                                                              error:nil];
        if (diagContents.length > 0) {
            NSArray *lines = [diagContents componentsSeparatedByCharactersInSet:
                [NSCharacterSet newlineCharacterSet]];
            NSMutableArray *recent = [NSMutableArray array];
            for (NSString *line in lines) {
                if (line.length == 0) continue;
                [recent addObject:line];
            }
            // Keep at most the last 6 entries (1 launch = up to 4 lines).
            NSUInteger start = recent.count > 6 ? recent.count - 6 : 0;
            for (NSUInteger i = start; i < recent.count; i++) {
                NSString *line = recent[i];
                NSLog(@"[RootHide][PatcherDiag] %@", line);
                [[DOUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"PATCHER-DIAG: %@", line] debug:NO];
            }
            // Truncate so the next report only contains fresh probes.
            [@"" writeToFile:diagPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch (NSException *e) {
        NSLog(@"[RootHide] PATCHER support EXCEPTION (non-fatal): %@: %@", e.name, e.reason);
    }
}

// Create `.jbroot -> ../..` symlink inside every .app directory under
// <jbroot>/Applications/. Idempotent — if the symlink already exists and
// points to the right place, leave it alone; otherwise delete and recreate.
- (void)ensureJbrootSymlinksInApps
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appsRoot = JBROOT_PATH(@"/Applications");
    NSArray *apps = [fm contentsOfDirectoryAtPath:appsRoot error:nil];
    if (!apps) {
        NSLog(@"[RootHide] ensureJbrootSymlinksInApps: /Applications not listable (yet) — skipping");
        return;
    }
    NSUInteger created = 0;
    NSUInteger verified = 0;
    for (NSString *appDir in apps) {
        if (![appDir hasSuffix:@".app"]) continue;
        NSString *appPath = [appsRoot stringByAppendingPathComponent:appDir];
        NSString *jbrootLink = [appPath stringByAppendingPathComponent:@".jbroot"];

        // Check existing symlink
        NSDictionary *attrs = [fm attributesOfItemAtPath:jbrootLink error:nil];
        if (attrs && attrs[NSFileType] == NSFileTypeSymbolicLink) {
            // Already a symlink — verify destination
            NSError *readErr = nil;
            NSString *dest = [fm destinationOfSymbolicLinkAtPath:jbrootLink error:&readErr];
            if (!readErr && ([dest isEqualToString:@"../.."] || [dest isEqualToString:@".."])) {
                verified++;
                continue;
            }
            // Wrong destination — remove and recreate
            [fm removeItemAtPath:jbrootLink error:nil];
        } else if (attrs) {
            // Something else exists at this path (file or dir) — remove it
            [fm removeItemAtPath:jbrootLink error:nil];
        }

        // Create the symlink: <app>/.jbroot -> ../..
        // (../.. resolves from <jbroot>/Applications/<App>.app/ back to <jbroot>/)
        NSError *createErr = nil;
        if ([fm createSymbolicLinkAtPath:jbrootLink withDestinationPath:@"../.." error:&createErr]) {
            created++;
            NSLog(@"[RootHide] ensureJbrootSymlinksInApps: created %@/.jbroot -> ../..", appPath);
        } else {
            NSLog(@"[RootHide] ensureJbrootSymlinksInApps: FAILED to create %@/.jbroot: %@", jbrootLink, createErr);
        }

        // ROOTHIDE PATCHER FIX: RootHidePatcher ships Mach-O helpers in a nested
        // "cctools" directory (otool / strings / install_name_tool) and patch.sh
        // rewrites library paths to "@loader_path/.jbroot/usr/lib/...". For a
        // binary at <app>/cctools/otool, @loader_path is the cctools directory,
        // so the single .jbroot symlink at the .app root is NOT visible to it and
        // dyld fails to resolve libroothide.dylib → the helper is killed and the
        // conversion aborts with no message. Drop a correctly-relative .jbroot
        // symlink into every nested directory that actually contains a Mach-O.
        created += [self ensureJbrootSymlinksInAppBundle:appPath jbroot:appsRoot];
    }
    NSLog(@"[RootHide] ensureJbrootSymlinksInApps: scanned %lu .app dirs, created %lu symlinks, verified %lu existing",
          (unsigned long)apps.count, (unsigned long)created, (unsigned long)verified);
}

// Ensure a `.jbroot` symlink exists in every sub-directory of an .app bundle that
// contains at least one Mach-O file, pointing back at the jailbreak root with a
// path relative to that directory. Returns the number of symlinks created.
- (NSUInteger)ensureJbrootSymlinksInAppBundle:(NSString *)appPath jbroot:(NSString *)appsRoot
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *jbrootRoot = [appsRoot stringByDeletingLastPathComponent]; // <jbroot>
    NSUInteger created = 0;

    NSArray<NSURL *> *allItems = [fm enumeratorAtURL:[NSURL fileURLWithPath:appPath]
                          includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                                             options:0
                                        errorHandler:nil].allObjects;

    NSMutableSet<NSString *> *dirsNeedingLink = [NSMutableSet set];
    for (NSURL *url in allItems) {
        NSNumber *isRegular = nil;
        [url getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
        if (![isRegular boolValue]) continue;

        // Cheap Mach-O sniff: first 4 bytes are a mach-o / fat magic.
        int fd = open(url.path.fileSystemRepresentation, O_RDONLY);
        if (fd < 0) continue;
        uint32_t magicBE = 0;
        ssize_t got = read(fd, &magicBE, sizeof(magicBE));
        close(fd);
        if (got != (ssize_t)sizeof(magicBE)) continue;

        // On-disk Mach-O magics are stored big-endian.
        uint32_t m = OSSwapBigToHostInt32(magicBE);
        BOOL isMachO = (m == 0xfeedfacf || m == 0xfeedface ||   // MH_MAGIC_64 / MH_MAGIC
                        m == 0xcafebabe || m == 0xcafebabf);    // FAT_MAGIC / FAT_MAGIC_64
        if (!isMachO) continue;

        NSString *dir = [url.path stringByDeletingLastPathComponent];
        if ([dir isEqualToString:appPath]) continue; // .app root already handled
        [dirsNeedingLink addObject:dir];
    }

    for (NSString *dir in dirsNeedingLink) {
        NSString *link = [dir stringByAppendingPathComponent:@".jbroot"];
        NSDictionary *attrs = [fm attributesOfItemAtPath:link error:nil];
        if (attrs && attrs[NSFileType] == NSFileTypeSymbolicLink) continue; // already present
        if (attrs) { [fm removeItemAtPath:link error:nil]; }

        // Relative path from <dir> back to <jbroot>.
        NSString *rel = [self relativePathFromDirectory:dir toDirectory:jbrootRoot];
        if (rel.length == 0) continue;
        NSError *err = nil;
        if ([fm createSymbolicLinkAtPath:link withDestinationPath:rel error:&err]) {
            created++;
            NSLog(@"[RootHide] PATCHER: created %@/.jbroot -> %@", dir, rel);
        } else {
            NSLog(@"[RootHide] PATCHER: FAILED to create %@/.jbroot: %@", link, err);
        }
    }
    return created;
}

// Compute a relative path ("../../..") that navigates from `fromDir` to `toDir`.
- (NSString *)relativePathFromDirectory:(NSString *)fromDir toDirectory:(NSString *)toDir
{
    NSArray<NSString *> *fromComps = [fromDir pathComponents];
    NSArray<NSString *> *toComps = [toDir pathComponents];

    NSUInteger common = 0;
    NSUInteger maxCommon = MIN(fromComps.count, toComps.count);
    while (common < maxCommon && [fromComps[common] isEqualToString:toComps[common]]) {
        common++;
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSUInteger i = common; i < fromComps.count; i++) {
        [parts addObject:@".."];
    }
    for (NSUInteger i = common; i < toComps.count; i++) {
        [parts addObject:toComps[i]];
    }
    if (parts.count == 0) return @".";
    return [parts componentsJoinedByString:@"/"];
}

- (BOOL)shouldInstallPackage:(NSString *)identifier
{
    NSString *bundledVersion = gBundledPackages[identifier];
    if (!bundledVersion) return NO;
    
    NSString *installedVersion = [self installedVersionForPackageWithIdentifier:identifier];
    if (!installedVersion) return YES;
    
    return [installedVersion numericalVersionRepresentation] < [bundledVersion numericalVersionRepresentation];
}

// Re-sign the patched RootHide dylibs with ldid.
//
// CHICKEN-AND-EGG PROBLEM:
//   ldid is itself a RootHide binary.  When it runs, dyld loads
//   libroothide.dylib (a dependency).  libroothide.dylib's constructor
//   calls __private_jbrootat_alloc, which has the assertion
//   `stat(JBROOT, &jbrootst) == 0`.
//
//   If we call ldid BEFORE patching libroothide.dylib → assertion fires
//   → SIGABRT (exit 6).
//   If we call ldid AFTER patching but BEFORE trust-caching → AMFI
//   rejects the unsigned dylib → ldid crashes with "No such file".
//
// SOLUTION:
//   1. Patch BOTH dylibs first (done in patchRootHideAssertions).
//   2. Add BOTH patched dylibs to the trust cache via
//      jbclient_trust_file_by_path().  This makes AMFI accept them
//      even though their code signatures are invalid.
//   3. NOW run ldid to re-sign.  ldid loads the trust-cached
//      libroothide.dylib → constructor runs → assertion is NOP'd → OK.
//      ldid writes a new adhoc signature to the dylib.
//
//   This function is called from finalizeBootstrap (step 12), AFTER
//   launchdhook is loaded (step 8).  jbclient_trust_file_by_path()
//   sends XPC to launchdhook, which adds the file's CDHash to the
//   kernel's trust cache.
- (NSError *)resignPatchedDylibs
{
    NSString *roothideInitPath  = JBROOT_PATH(@"/usr/lib/roothideinit.dylib");
    NSString *libroothidePath   = JBROOT_PATH(@"/usr/lib/libroothide.dylib");

    NSFileManager *fm = [NSFileManager defaultManager];

    // ─── Trust-cache BOTH patched dylibs ─────────────────────────────
    // This is the ONLY step needed.  jbclient_trust_file_by_path() sends
    // XPC to launchdhook, which adds the file's CDHash to the kernel trust
    // cache.  AMFI will then accept the patched dylib even though its code
    // signature is invalid (because the bytes were modified).
    //
    // We do NOT call ldid at all.  ldid fails on this device because:
    //   1. ldid is a RootHide binary that loads libroothide.dylib
    //   2. The jbroot path is very long (~160 chars), and ldid's internal
    //      path handling fails with ENOENT ("No such file or directory")
    //      even though the file exists and is readable.
    //   3. Trust-caching is sufficient — AMFI checks the trust cache
    //      before checking the embedded code signature.
    NSLog(@"[RootHide] trust-caching patched dylibs...");

    if ([fm fileExistsAtPath:roothideInitPath]) {
        chmod(roothideInitPath.fileSystemRepresentation, 0755);
        int tcR = jbclient_trust_file_by_path(roothideInitPath.fileSystemRepresentation);
        NSLog(@"[RootHide] trust-cache roothideinit.dylib: %d", tcR);
    } else {
        NSLog(@"[RootHide] WARNING: roothideinit.dylib missing — cannot trust-cache");
    }
    if ([fm fileExistsAtPath:libroothidePath]) {
        chmod(libroothidePath.fileSystemRepresentation, 0755);
        int tcR = jbclient_trust_file_by_path(libroothidePath.fileSystemRepresentation);
        NSLog(@"[RootHide] trust-cache libroothide.dylib: %d", tcR);
    } else {
        NSLog(@"[RootHide] WARNING: libroothide.dylib missing — cannot trust-cache");
    }

    return nil;
}

// Trust-cache ALL macho binaries in the bootstrap directory.
// This enumerates <jbroot>/usr/ recursively, finds all macho files,
// and adds their CDHashes to the kernel trust cache via
// jbclient_trust_file_by_path().  After this, AMFI will accept all
// bootstrap binaries (dpkg, apt, sh, etc.) without needing re-signing.
- (void)trustCacheBootstrapBinaries
{
    NSString *jbroot = [NSString stringWithUTF8String:JBROOT_PATH("/")];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger trusted = 0;
    NSUInteger skipped = 0;

    // Scan BOTH /usr/ and /Applications/ directories.
    // /usr/ contains bootstrap binaries (dpkg, apt, sh, etc.)
    // /Applications/ contains installed apps (Sileo, Zebra, RootHide)
    //   → their main executable MUST be trust-cached or AMFI kills
    //   them with SIGKILL when SpringBoard launches them → black screen crash
    NSArray *scanDirs = @[
        [jbroot stringByAppendingPathComponent:@"usr"],
        [jbroot stringByAppendingPathComponent:@"Applications"],
        [jbroot stringByAppendingPathComponent:@"Library"],
    ];

    for (NSString *scanDir in scanDirs) {
        if (![fm fileExistsAtPath:scanDir]) continue;

        NSDirectoryEnumerator<NSURL *> *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:scanDir]
                                                      includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                                                                         options:0
                                                                     errorHandler:nil];

        for (NSURL *url in enumerator) {
            NSNumber *isRegular = nil;
            [url getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
            if (![isRegular boolValue]) continue;

            // Skip symlinks
            NSDictionary *attrs = [fm attributesOfItemAtPath:url.path error:nil];
            if (attrs[NSFileType] == NSFileTypeSymbolicLink) continue;

            // ROOTHIDE FIX (iOS 17 dev-cert apps "Developer Mode Required"):
            // the flat jbclient_trust_file_by_path only registers the file's own
            // ad-hoc cdhash and does NOT run the roothide randomized-cdhash
            // normalization, so binaries signed with a developer certificate
            // (TeamID present) kept failing TXM validation at spawn time even
            // though their cdhash was in the trustcache. The recurse path (same
            // one systemhook uses for spawned executables) collects the
            // executable AND its dependent dylibs and normalizes each slice via
            // ensure_randomized_cdhash_for_slice. Fall back to the flat trust
            // when the recurse call fails (e.g. launchd not reachable yet).
            int r = jbclient_trust_executable_recurse(url.path.fileSystemRepresentation, NULL);
            if (r != 0) {
                r = jbclient_trust_file_by_path(url.path.fileSystemRepresentation);
            }
            if (r == 0) {
                trusted++;
            } else {
                skipped++;
                // ROOTHIDE FIX (iOS 17 "Killed: 9"): per-file trust failures were
                // previously swallowed silently, making AMFI SIGKILL loops
                // undiagnosable. Log every failure path + result code.
                NSLog(@"[RootHide] trust-cache FAILED (%d): %@", r, url.path);
            }
        }
    }

    NSLog(@"[RootHide] trust-cache: %lu binaries trusted, %lu skipped", (unsigned long)trusted, (unsigned long)skipped);
    if (trusted == 0) {
        // Loud failure: if nothing got trusted, every bootstrap child will be
        // SIGKILLed by AMFI ("Killed: 9" loop). Surface it in the app log.
        NSLog(@"[RootHide] trust-cache WARNING: ZERO binaries trusted — spawned bootstrap binaries will be killed by AMFI");
    }
}

// FIX LỖI 1 + 2: Tách install RootHide Manager thành method riêng để dễ retry
// và không phụ thuộc vào flow finalizeBootstrap chính.
//
// Method này ĐẢM BẢO:
// 1. RootHide Manager được install và binary extract vào <jbroot>/Applications/RootHide.app/
// 2. Binary được chown root:wheel + chmod 6755 (setuid root) — cần thiết cho
//    RootHide Manager để gọi jbctl/mount/trust-cache.
// 3. Binary được trust-cached NGAY (qua manuallyInstallDeb -> trustCacheAppBinariesAfterInstall).
// 4. uicache được gọi để refresh icon.
//
// Method này KHÔNG throw exception và KHÔNG return error — log mọi lỗi và
// return. Lý do: JB không nên fail chỉ vì RootHide Manager install fail.
- (void)installRootHideManagerApp
{
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];

        // Check xem có cần install không (binary missing hoặc dpkg chưa có entry)
        NSString *roothideAppBinaryPath = JBROOT_PATH(@"/Applications/RootHide.app/RootHide");
        BOOL roothideAppBinaryExists = [fm fileExistsAtPath:roothideAppBinaryPath];
        NSString *existingRootHideVersion = [self installedVersionForPackageWithIdentifier:@"com.roothide.manager"];
        BOOL shouldInstall = !existingRootHideVersion || !roothideAppBinaryExists;
        NSLog(@"[RootHide] RootHide Manager: dpkg_version=%@ binary_exists=%d -> shouldInstall=%d",
              existingRootHideVersion, roothideAppBinaryExists, shouldInstall);

        if (!shouldInstall) {
            NSLog(@"[RootHide] RootHide Manager đã cài rồi — chỉ trust-cache lại (defensive)");
            // Ngay cả khi đã cài, vẫn trust-cache lại để đảm bảo cdhash trong trustcache
            // (có thể trustcache đã bị clear sau reboot)
            [self trustCacheAppBinariesAfterInstall:@"RootHide"];
            // Vẫn apply chmod/chown (có thể bị reset)
            if (roothideAppBinaryExists) {
                // Syscalls directly — exec_cmd_root spawns /bin/chown + /bin/chmod
                // via persona override, which fails with EPERM on 16.7/17.5.
                if (chown(roothideAppBinaryPath.fileSystemRepresentation, 0, 0) != 0) {
                    NSLog(@"[RootHide] chown RootHide binary failed (errno %d)", errno);
                }
                if (chmod(roothideAppBinaryPath.fileSystemRepresentation, 06755) != 0) {
                    NSLog(@"[RootHide] chmod 6755 RootHide binary failed (errno %d)", errno);
                }
            }
            return;
        }

        // Tìm .deb file
        NSString *packagesDir = [[[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Packages"] copy];
        NSString *roothideAppDeb = [packagesDir stringByAppendingPathComponent:@"roothideapp_1.3.9_iphoneos-arm64e.deb"];
        if (![fm fileExistsAtPath:roothideAppDeb]) {
            NSLog(@"[RootHide] RootHide Manager deb NOT FOUND in bundle — skipping auto-install");
            [[DOUIManager sharedInstance] sendLog:@"RootHide Manager deb not bundled (skipped)" debug:YES];
            return;
        }

        NSLog(@"[RootHide] Installing RootHide Manager from %@", roothideAppDeb);
        [[DOUIManager sharedInstance] sendLog:@"Installing RootHide Manager" debug:NO];

        // ============================================================
        // FIX CRASH: Dùng dpkg -i thay vì manuallyInstallDeb (match upstream
        // opa334). manuallyInstallDeb giữ 4MB+ NSData buffers trong process
        // RAM → jetsam kill. dpkg -i spawn binary ngoài, RAM tốn trong
        // child process. Sau khi dpkg install xong, vẫn cần:
        //   1. trustCacheAppBinariesAfterInstall (roothide-specific)
        //   2. ensureJbrootSymlinksInApps (roothide-specific .jbroot symlink)
        // ============================================================
        int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"),
                                  "-i", "--force-all",
                                  roothideAppDeb.fileSystemRepresentation, NULL);
        NSLog(@"[RootHide] dpkg -i RootHide Manager exit code: %d", r);
        fflush(stderr);

        if (r != 0) {
            // Fallback: manuallyInstallDeb
            NSLog(@"[RootHide] dpkg -i failed (%d), falling back to manuallyInstallDeb", r);
            fflush(stderr);
            NSError *installErr = [self manuallyInstallDeb:roothideAppDeb appName:@"RootHide"];
            if (installErr) {
                NSLog(@"[RootHide] RootHide Manager install FAILED (continuing — non-fatal): %@", installErr);
                [[DOUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"RootHide Manager install failed: %@", installErr] debug:YES];
                // FIX: Retry một lần. Có thể fail lần đầu do thư mục chưa exist sau extract.
                // manuallyInstallDeb idempotent (nếu files đã exist, extract đè).
                NSLog(@"[RootHide] Retrying RootHide Manager install...");
                NSError *retryErr = [self manuallyInstallDeb:roothideAppDeb appName:@"RootHide"];
                if (retryErr) {
                    NSLog(@"[RootHide] RootHide Manager retry FAILED: %@", retryErr);
                    return;  // Cho up, không crash JB
                }
            }
        } else {
            // dpkg -i thành công → vẫn cần trust-cache + symlinks (roothide-specific)
            [self trustCacheAppBinariesAfterInstall:@"RootHide"];
            [self ensureRootHidePatcherSupport];
        }

        // Verify binary on disk
        BOOL binaryNowExists = [fm fileExistsAtPath:roothideAppBinaryPath];
        NSLog(@"[RootHide] RootHide Manager install OK, binary on disk: %d", binaryNowExists);
        if (!binaryNowExists) {
            NSLog(@"[RootHide] WARNING: install reported success but binary missing — dpkg status may be stale");
            return;
        }

        // Apply postinst-equivalent: chown 0:0 + chmod +s (setuid root)
        // RootHide Manager cần setuid root để gọi jbctl/mount/trust-cache.
        if (chown(roothideAppBinaryPath.fileSystemRepresentation, 0, 0) != 0) {
            NSLog(@"[RootHide] chown RootHide binary failed (errno %d)", errno);
        }
        if (chmod(roothideAppBinaryPath.fileSystemRepresentation, 06755) != 0) {
            NSLog(@"[RootHide] chmod 6755 RootHide binary failed (errno %d)", errno);
        }
        NSLog(@"[RootHide] Applied postinst-equivalent: chown root:wheel + chmod 6755 on RootHide binary");

        // Trust-cache lần cuối (defensive — có thể fail lần đầu do binary
        // mới extract và jbserver chưa pick up)
        [self trustCacheAppBinariesAfterInstall:@"RootHide"];

        // Refresh icon cache
        exec_cmd_trusted(JBROOT_PATH("/usr/bin/uicache"), "-p", "/Applications/RootHide.app", NULL);
        NSLog(@"[RootHide] RootHide Manager install complete");
    } @catch (NSException *e) {
        NSLog(@"[RootHide] EXCEPTION during RootHide Manager install: %@: %@", e.name, e.reason);
        // KHÔNG throw lên — JB tiếp tục
    }
}

- (NSError *)finalizeBootstrap
{
    // ROOTHIDE: Simplified finalizeBootstrap.
    //
    // FIX LỖI 1 (JB crash cuối, v2):
    // Mỗi step được wrap trong @try/@catch để NSException không crash app.
    // Trước đây một số step chỉ catch NSError (qua return value) nhưng KHÔNG catch
    // NSException → nếu có exception (vd: NSInvalidArgumentException do nil dict,
    // NSInternalInconsistencyException do dpkg status parse fail) → app crash
    // → DOJailbreaker không reach được rebootUserspace → "JB crash cuối".
    //
    // FIX LỖI 2 (RootHide app không được cài):
    // 1. Trust-cache bootstrap binaries ĐẦU TIÊN (đảm bảo dpkg, sh, tar chạy được)
    // 2. Run prep_bootstrap.sh (chỉ first jailbreak)
    // 3. Install RootHide Manager app FIRST (trước Sileo) — đảm bảo binary
    //    được trust-cached trước khi Sileo uicache chạy
    // 4. Install Sileo/Zebra
    // 5. Install bundled packages (libroot, libkrw, basebin-link, launchctl)
    // 6. Re-trust-cache toàn bộ /Applications (defensive)
    // 7. Ensure .jbroot symlinks
    // 8. Trust-cache Dopamine app itself
    NSLog(@"[RootHide] finalizeBootstrap: starting");

    // ROOTHIDE FIX LỖI 1 (CRITICAL, v5):
    // Revert về flow ĐƠN GIẢN theo fork gốc (github.com/roothide/Dopamine)
    //
    // EVIDENCE các patch trước FAIL:
    //   - v1: spawnJbctlAsRootWithArgs với --waitfor pipe → race condition, app crash
    //   - v2: direct reboot3 từ app → EPERM (thiếu entitlement)
    //   - v3: jbctl spawn ngay sau Step 1 → apps không cài
    //   - v4: jbctl spawn sau Step 5 (skip 6,7,8) → vẫn fail (user báo 'như cũ')
    //
    // ROOT CAUSE: User code tự chế phức tạp. Fork gốc CHÍNH THỨC:
    //   - finalizeBootstrap chỉ install apps, KHÔNG gọi reboot
    //   - rebootUserspace được gọi bởi caller (DOMainViewController → finalize)
    //   - rebootUserspace dùng exec_cmd_suspended + SIGCONT (KHÔNG --waitfor pipe)
    //
    // FIX v5: finalizeBootstrap chỉ install apps, return nil
    // Reboot sẽ do caller (DOJailbreaker.finalize → rebootUserspace) handle

    // Step 1: trust-cache bootstrap binaries (đảm bảo dpkg, sh, tar chạy được)
    NSLog(@"[RootHide] Step 1/5: trust-caching bootstrap binaries...");
    fflush(stderr);
    @try {
        [self trustCacheBootstrapBinaries];
    } @catch (NSException *e) {
        NSLog(@"[RootHide] Step 1 EXCEPTION (non-fatal): %@: %@", e.name, e.reason);
    }
    fflush(stderr);

    // Step 2: run prep_bootstrap.sh (chỉ first jailbreak)
    NSLog(@"[RootHide] Step 2/5: prep_bootstrap.sh check");
    fflush(stderr);
    @try {
        NSString *prepBootstrapPath = JBROOT_PATH(@"/prep_bootstrap.sh");
        if ([[NSFileManager defaultManager] fileExistsAtPath:prepBootstrapPath]) {
            [[DOUIManager sharedInstance] sendLog:@"Finalizing Bootstrap" debug:NO];
            int r = exec_cmd_trusted(JBROOT_PATH("/bin/sh"), prepBootstrapPath.fileSystemRepresentation, NULL);
            if (r != 0) {
                NSLog(@"[RootHide] prep_bootstrap.sh returned %d (continuing — non-fatal)", r);
            }
        } else {
            NSLog(@"[RootHide] prep_bootstrap.sh not found (re-jailbreak) — skipping");
        }
        fflush(stderr);
    } @catch (NSException *e) {
        NSLog(@"[RootHide] Step 2 EXCEPTION (non-fatal): %@: %@", e.name, e.reason);
        fflush(stderr);
    }

    // Step 3: install RootHide Manager app FIRST.
    NSLog(@"[RootHide] Step 3/5: installing RootHide Manager app...");
    fflush(stderr);
    @try {
        [self installRootHideManagerApp];
    } @catch (NSException *e) {
        NSLog(@"[RootHide] Step 3 EXCEPTION (non-fatal): %@: %@", e.name, e.reason);
        fflush(stderr);
    }

    // Step 4: install Sileo/Zebra
    NSLog(@"[RootHide] Step 4/5: installing package managers (Sileo/Zebra)...");
    fflush(stderr);
    @try {
        NSError *pmError = [self installPackageManagers];
        if (pmError) {
            NSLog(@"[RootHide] installPackageManagers FAILED (continuing — non-fatal): %@", pmError);
        }
        fflush(stderr);
    } @catch (NSException *e) {
        NSLog(@"[RootHide] Step 4 EXCEPTION (non-fatal): %@: %@", e.name, e.reason);
        fflush(stderr);
    }

    // Step 5: install bundled packages
    NSLog(@"[RootHide] Step 5/5: installing bundled packages (tweak infra, libroot, libkrw, basebin-link, launchctl)...");
    fflush(stderr);
    @try {
        // ============================================================
        // FIX TWEAK-INSTALL (iOS 17/18): bootstrap arm64e KHÔNG chứa bất kỳ
        // gói nào Provides: mobilesubstrate và không có libkrw0-plugin.
        // Sileo vì thế từ chối cài hầu hết tweak với các lỗi:
        //   "Depends mobilesubstrate" / "Depends preferenceloader" /
        //   "Depends com.opa334.altlist" / "Depends libkrw0-plugin".
        //
        // Root cause: các repo arm64 (ellekit.space, Procursus 1900 arm64)
        // không cài được vì dpkg trên strap arm64e không có foreign arch;
        // repo arm64e duy nhất đủ bộ (roothide.github.io) là REPO — user
        // phải tự bấm cài trong Sileo, nhưng chính những gói đó lại cần
        // mobilesubstrate nên Sileo cũng không resolve nổi (deadlock deps).
        // → Không bundle sẵn thì tweak không bao giờ cài được.
        //
        // Giải pháp: bundle 3 deb arm64e từ roothide.github.io (đã kiểm tra
        // payload bằng extract sạch):
        // - ElleKit 1.2-1 Provides mobilesubstrate (= 99) + libhooker;
        //   payload chỉ là /usr/lib/{TweakLoader,TweakInject,libellekit,
        //   libsubstrate,libhooker,libblackjack}.dylib + ellekit/ +
        //   Library/MobileSubstrate + CydiaSubstrate.framework — KHÔNG đụng
        //   libroothide.dylib/roothideinit.dylib của gói roothide trong strap;
        // - PreferenceLoader 2.2.8 Depends mobilesubstrate (được ElleKit
        //   Provide) → phải cài SAU ElleKit;
        // - AltList 1.0.11 Depends firmware(>=7.0) — strap không có gói
        //   firmware, nhưng dpkg chạy với --force-all (như mọi bundled deb)
        //   nên dep thiếu này bị bỏ qua một cách có chủ đích.
        // Cả 3 đều fat arm64+arm64e (minos 15.0) khớp hệ, và hệ thống fork
        // đã sẵn sàng chạy chúng: dyldhook hook expandAtLoaderPath dịch
        // @loader_path/.jbroot cho tweaks rootless, systemhook dlopen
        // TweakLoader khi should_enable_tweaks, trust-cache sweep quét
        // /usr sau install (cuối Step 5 này).
        // ============================================================
        static NSString * const kTweakInfraMarker = @"/usr/lib/TweakLoader.dylib";
        NSString *tweakLoaderInstalled = JBROOT_PATH(kTweakInfraMarker);
        BOOL shouldInstallTweakInfra = ![[NSFileManager defaultManager] fileExistsAtPath:tweakLoaderInstalled];
        if (shouldInstallTweakInfra) {
            NSString *packagesDir = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Packages"];
            NSString *elleKitDeb  = [packagesDir stringByAppendingPathComponent:@"ellekit_1.2-1_iphoneos-arm64e.deb"];
            NSString *plDeb       = [packagesDir stringByAppendingPathComponent:@"preferenceloader_2.2.8_iphoneos-arm64e.deb"];
            NSString *altListDeb  = [packagesDir stringByAppendingPathComponent:@"com.opa334.altlist_1.0.11_iphoneos-arm64e.deb"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:elleKitDeb]) {
                int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"), "-i", "--force-all", elleKitDeb.fileSystemRepresentation, NULL);
                NSLog(@"[RootHide] dpkg -i ellekit exit: %d", r);
                fflush(stderr);
            } else {
                NSLog(@"[RootHide] ellekit deb NOT bundled (skipping tweak infra install)");
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:plDeb]) {
                int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"), "-i", "--force-all", plDeb.fileSystemRepresentation, NULL);
                NSLog(@"[RootHide] dpkg -i preferenceloader exit: %d", r);
                fflush(stderr);
            }
            if ([[NSFileManager defaultManager] fileExistsAtPath:altListDeb]) {
                int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"), "-i", "--force-all", altListDeb.fileSystemRepresentation, NULL);
                NSLog(@"[RootHide] dpkg -i altlist exit: %d", r);
                fflush(stderr);
            }
        } else {
            NSLog(@"[RootHide] tweak infra already present (TweakLoader.dylib exists) — skipping");
        }

        BOOL shouldInstallLibroot = [self shouldInstallPackage:@"libroot-dopamine"];
        BOOL shouldInstallLibkrw = [self shouldInstallPackage:@"libkrw0-dopamine"];
        BOOL shouldInstallBasebinLink = [self shouldInstallPackage:@"dopamine-basebin-link"];
        BOOL shouldInstallLaunchctl = NO;
        if (__builtin_available(iOS 19.0, *)) {
            shouldInstallLaunchctl = [self shouldInstallPackage:@"launchctl"];
        }

        // ============================================================
        // FIX CRASH: Dùng dpkg -i (match upstream opa334) thay vì
        // manuallyInstallDeb cho bundled packages. Lý do giống Step 3/4:
        // manuallyInstallDeb giữ NSData buffers trong process RAM → jetsam.
        // dpkg -i spawn binary ngoài, RAM tốn trong child process.
        //
        // Bundled packages (libroot/libkrw/basebin-link/launchctl) KHÔNG
        // phải .app dirs, nên KHÔNG cần trustCacheAppBinariesAfterInstall
        // hay ensureJbrootSymlinksInApps (chỉ cần cho .app dirs).
        // ============================================================
        if (shouldInstallLaunchctl) {
            // FIX FILENAME MISMATCH: file thật trong Packages/additional là
            // launchctl_1_1.2.0_iphoneos-arm64.deb (arch arm64, KHÔNG phải
            // arm64e) nhưng code cũ tham chiếu "..._iphoneos-arm64e.deb" →
            // fileExists luôn NO → dpkg -i không bao giờ chạy, mỗi lần đều rơi
            // vào fallback manuallyInstallDeb (không qua dpkg db → gói không
            // được quản lý, lỗi "mã lỗi kiến trúc" về sau). Khớp tên file thật;
            // arch arm64 được chấp nhận nhờ foreign-arch registration (Step 6).
            NSString *launchctlPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"launchctl_1_1.2.0_iphoneos-arm64.deb"];
            int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"),
                                      "-i", "--force-all",
                                      launchctlPath.fileSystemRepresentation, NULL);
            NSLog(@"[RootHide] dpkg -i launchctl exit: %d", r);
            fflush(stderr);
            if (r != 0) {
                // Fallback manuallyInstallDeb
                NSError *installErr = [self manuallyInstallDeb:launchctlPath appName:@"launchctl"];
                if (installErr) NSLog(@"[RootHide] launchctl install (non-fatal): %@", installErr);
            }
        }
        if (shouldInstallLibroot) {
            NSString *librootPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"libroot.deb"];
            int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"),
                                      "-i", "--force-all",
                                      librootPath.fileSystemRepresentation, NULL);
            NSLog(@"[RootHide] dpkg -i libroot exit: %d", r);
            fflush(stderr);
            if (r != 0) {
                NSError *installErr = [self manuallyInstallDeb:librootPath appName:@"libroot"];
                if (installErr) NSLog(@"[RootHide] libroot install (non-fatal): %@", installErr);
            }
        }
        if (shouldInstallLibkrw) {
            NSString *libkrwPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"libkrw-dopamine.deb"];
            int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"),
                                      "-i", "--force-all",
                                      libkrwPath.fileSystemRepresentation, NULL);
            NSLog(@"[RootHide] dpkg -i libkrw exit: %d", r);
            fflush(stderr);
            if (r != 0) {
                NSError *installErr = [self manuallyInstallDeb:libkrwPath appName:@"libkrw"];
                if (installErr) NSLog(@"[RootHide] libkrw install (non-fatal): %@", installErr);
            }
        }
        if (shouldInstallBasebinLink) {
            if ([self fileOrSymlinkExistsAtPath:JBROOT_PATH(@"/usr/bin/opainject")]) {
                [[NSFileManager defaultManager] removeItemAtPath:JBROOT_PATH(@"/usr/bin/opainject") error:nil];
            }
            if ([self fileOrSymlinkExistsAtPath:JBROOT_PATH(@"/usr/bin/jbctl")]) {
                [[NSFileManager defaultManager] removeItemAtPath:JBROOT_PATH(@"/usr/bin/jbctl") error:nil];
            }
            if ([self fileOrSymlinkExistsAtPath:JBROOT_PATH(@"/usr/lib/libjailbreak.dylib")]) {
                [[NSFileManager defaultManager] removeItemAtPath:JBROOT_PATH(@"/usr/lib/libjailbreak.dylib") error:nil];
            }
            NSString *basebinLinkPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"basebin-link.deb"];
            int r = exec_cmd_trusted(JBROOT_PATH("/usr/bin/dpkg"),
                                      "-i", "--force-all",
                                      basebinLinkPath.fileSystemRepresentation, NULL);
            NSLog(@"[RootHide] dpkg -i basebin-link exit: %d", r);
            fflush(stderr);
            if (r != 0) {
                NSError *installErr = [self manuallyInstallDeb:basebinLinkPath appName:@"basebin-link"];
                if (installErr) NSLog(@"[RootHide] basebin-link install (non-fatal): %@", installErr);
            }
        }

        // FIX TWEAK-INSTALL: trust-cache ngay các dylib vừa cài (TweakLoader,
        // libellekit, PreferenceLoader, AltList...). sweep quét /usr +
        // /Applications + /Library và gọi recurse-trust từng file — nếu bỏ
        // qua, các dylib này chỉ được trust ở lần JB SAU (sau userspace
        // reboot đầu tiên), tức phiên hiện tại vẫn KIA khi tweak inject.
        if (shouldInstallTweakInfra || shouldInstallLibkrw || shouldInstallLibroot || shouldInstallBasebinLink) {
            NSLog(@"[RootHide] re-sweeping trust cache after bundled installs...");
            [self trustCacheBootstrapBinaries];
        }

        // ============================================================
        // FIX TWEAK ENVIRONMENT (Issue 1 — "mã nguồn setup môi trường
        // cho tweak deb không hoàn chỉnh"): ElleKit 1.2-1 cài các symlink
        // ABSOLUTE trong data.tar:
        //   /usr/lib/TweakLoader.dylib  -> /usr/lib/ellekit/libinjector.dylib
        //   /usr/lib/libsubstrate.dylib -> /usr/lib/libellekit.dylib
        //   /Library/MobileSubstrate/DynamicLibraries -> /usr/lib/TweakInject
        // Khi dpkg chạy với vroot (dpkg link @loader_path/.jbroot/usr/lib/
        // libvrootapi.dylib; vroot_symlink gọi jbrootat_alloc(fd, target)
        // rồi symlink() với target ĐÃ dịch thành relative ".jbroot/..."),
        // symlink được relative-hóa tự động. NHƯNG:
        //   1) IPA CŨ của fork từng cài ellekit/sileo/zebra/basebin-link
        //      qua fallback manuallyInstallDeb — extract in-process bằng
        //      libarchive trong app Dopamine (KHÔNG có vroot interpose)
        //      → symlink absolute ĐỨNG trơ trọi trên đĩa, dlopen ENOENT.
        //   2) Tweak do Sileo cài cũng vậy nếu Sileo từng fail giữa chừng
        //      và rơi vào trạng thái nửa vời.
        // Trên RootHide Bootstrap CHÍNH THỨC, ReRandomizeBootstrap
        // (bootstrap.m:354) chạy "/bin/sh /usr/libexec/updatelinks.sh" sau
        // MỖI lần randomize lại jbroot: find / -xdev -type l | updatelink
        // — binary updatelink rewrite từng symlink absolute thành
        // ".jbroot/usr/lib/..." (giải quyết qua self-symlink <jbroot>/
        // .jbroot -> "." do bootstrap tar cài sẵn). Fork này trước giờ
        // KHÔNG chạy bước đó lần nào.
        // Chạy mỗi finalizeBootstrap khi TweakLoader đã tồn tại —
        // idempotent (updatelink in "no change" cho symlink đã relative),
        // và find -xdev tự giới hạn trong volume jbroot.
        // ============================================================
        if ([self fileOrSymlinkExistsAtPath:JBROOT_PATH(@"/usr/lib/TweakLoader.dylib")]) {
            NSLog(@"[RootHide] running updatelinks.sh to fix absolute symlinks (TweakLoader, libsubstrate, DynamicLibraries)...");
            int r = exec_cmd_trusted(JBROOT_PATH("/bin/sh"),
                                     JBROOT_PATH("/usr/libexec/updatelinks.sh"), NULL);
            NSLog(@"[RootHide] updatelinks.sh exit: %d", r);
            if (r != 0) {
                // Fallback: updatelink đọc DANH SÁCH symlink path từ stdin
                // (find | updatelink), không nhận argv — pipe từng path
                // quan trọng nhất của tweak environment qua echo.
                const char *keyLinks[] = {
                    "/usr/lib/TweakLoader.dylib",
                    "/usr/lib/TweakInject.dylib",
                    "/usr/lib/libsubstrate.dylib",
                    "/usr/lib/libhooker.dylib",
                    "/usr/lib/libblackjack.dylib",
                    "/Library/MobileSubstrate/DynamicLibraries",
                };
                for (size_t i = 0; i < sizeof(keyLinks) / sizeof(keyLinks[0]); i++) {
                    // echo '<link>' | updatelink '<link>'
                    // (updatelink lấy path từ stdin, argv bị bỏ qua)
                    char cmdBuf[PATH_MAX + 64];
                    snprintf(cmdBuf, sizeof(cmdBuf), "echo '%s' | '%s'", keyLinks[i],
                             JBROOT_PATH("/usr/libexec/updatelink"));
                    exec_cmd_trusted(JBROOT_PATH("/bin/sh"), "-c", cmdBuf, NULL);
                }
            }
        }
        fflush(stderr);
    } @catch (NSException *e) {
        NSLog(@"[RootHide] EXCEPTION during bundled packages install: %@: %@", e.name, e.reason);
        fflush(stderr);
    }

    // ROOTHIDE PATCHER FIX: keep the Patcher working tree + .jbroot symlinks +
    // dependency warnings correct on EVERY jailbreak. Previously this ran only
    // inside the first-extract completion (bootstrapFinishedCompletion), which
    // re-jailbreaks skip via .thebootstrapped — so a root-owned patch.sh
    // directory or a missing tool set silently broke folderCheck()/convert
    // until the next full re-bootstrap.
    [self ensureRootHidePatcherSupport];

    // ============================================================
    // FIX SILEO "MÃ LỖI KIẾN TRÚC" (Issue 3, Step 6/6): dpkg db của
    // RootHide bootstrap coi hệ thống là iphoneos-arm64e duy nhất —
    // KHÔNG có foreign arch nào được đăng ký (không tồn tại file
    // <admindir>/arch, chưa bao giờ chạy dpkg --add-architecture).
    // Hệ quả:
    //   1) Mọi deb arch iphoneos-arm64 (rất phổ biến: repo Procursus
    //      chuẩn, launchctl deb đi kèm IPA, nhiều tweak/từ repo cộng
    //      đồng) bị dpkg từ chối: "package architecture (iphoneos-arm64)
    //      does not match system (iphoneos-arm64e)" → Sileo hiện mã lỗi.
    //   2) Gói arch all bị dpkg từ chối tương tự nếu db yêu cầu "all"
    //      phải nằm trong danh sách foreign arches của một số build.
    // RootHide Bootstrap CHÍNH THỨC tạo sẵn file arch với các dòng
    // iphoneos-arm64e / all / iphoneos-arm64; fork thiếu bước này.
    // Tạo trực tiếp file arch (an toàn hơn dpkg --add-architecture vì
    // không cần spawn dpkg, không đụng lock db đang giữ bởi step trên).
    // ============================================================
    @try {
        NSString *dpkgArchPath = JBROOT_PATH(@"/var/lib/dpkg/arch");
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray<NSString *> *archLines = [NSMutableArray array];
        if ([fm fileExistsAtPath:dpkgArchPath]) {
            NSString *existing = [NSString stringWithContentsOfFile:dpkgArchPath
                                                           encoding:NSUTF8StringEncoding
                                                              error:nil];
            if (existing) {
                for (NSString *line in [existing componentsSeparatedByCharactersInSet:
                                        [NSCharacterSet newlineCharacterSet]]) {
                    NSString *trimmed = [line stringByTrimmingCharactersInSet:
                                         [NSCharacterSet whitespaceCharacterSet]];
                    if (trimmed.length && ![archLines containsObject:trimmed]) {
                        [archLines addObject:trimmed];
                    }
                }
            }
        }
        for (NSString *arch in @[@"iphoneos-arm64e", @"all", @"iphoneos-arm64"]) {
            if (![archLines containsObject:arch]) [archLines addObject:arch];
        }
        NSString *archFileContent = [[archLines componentsJoinedByString:@"\n"]
                                     stringByAppendingString:@"\n"];
        NSError *writeErr = nil;
        BOOL wrote = [archFileContent writeToFile:dpkgArchPath
                                       atomically:YES
                                         encoding:NSUTF8StringEncoding
                                            error:&writeErr];
        if (!wrote) {
            NSLog(@"[RootHide] dpkg arch registration failed (non-fatal): %@", writeErr);
        } else {
            NSLog(@"[RootHide] dpkg arch file now:\n%@", archFileContent);
        }
    } @catch (NSException *e) {
        NSLog(@"[RootHide] arch registration EXCEPTION (non-fatal): %@: %@", e.name, e.reason);
    }

    // ROOTHIDE FIX LỖI 1 v5: KHÔNG gọi reboot trong finalizeBootstrap
    // Caller (DOMainViewController → fadeToBlack → jailbreaker.finalize → rebootUserspace)
    // sẽ handle reboot SAU khi finalizeBootstrap return thành công
    NSLog(@"[RootHide] finalizeBootstrap: DONE — caller will handle reboot");
    fflush(stderr);
    return nil;
}

// --- in-process recursive delete --------------------------------------------
// deleteBootstrap must NOT spawn /bin/rm. Two independent reasons, both proven
// on device:
//   1. exec_cmd_root() uses posix_spawnattr_set_persona_np(OVERRIDE, uid 0).
//      Apple neutered persona overrides for non-launchd callers (iOS 17.6+ per
//      the comment in systemhook/src/common/common.c:263), and in practice the
//      spawn fails with EPERM on 16.7.16 AND 17.5.1 in this fork — the user
//      logs show "locateJailbreakRoot: /bin/ls spawn failed: 1" followed by
//      "deleteBootstrap: rm jbroot failed (1)". Nothing was ever deleted.
//   2. Even when a spawn does succeed, the child inherits the patched dyld and
//      can be SIGKILLed by AMFI before it unlinks anything.
// The Dopamine app is already uid 0 and unsandboxed at this point (runAsRoot +
// runUnsandboxed in DOEnvironmentManager.deleteBootstrap, and the same block
// successfully lists /var/containers/Bundle/Application via NSFileManager), so
// plain unlinkat/rmdir syscalls are all we need.
//
// Returns 0 on success, or the first non-zero errno encountered. Missing paths
// are not an error (ENOENT => 0) so the sweep is idempotent.
static int rmrf_in_process(const char *path)
{
    struct stat sb;
    if (lstat(path, &sb) != 0) {
        return (errno == ENOENT) ? 0 : errno;
    }

    if (!S_ISDIR(sb.st_mode)) {
        // Regular file, symlink, socket, fifo, device node
        if (unlink(path) != 0 && errno != ENOENT) return errno;
        return 0;
    }

    int dirfd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dirfd < 0) {
        // Not openable — try removing it as a plain entry (covers races and
        // directories we cannot descend into).
        if (rmdir(path) == 0 || errno == ENOENT) return 0;
        return errno;
    }

    int firstErr = 0;
    DIR *d = fdopendir(dirfd);
    if (!d) {
        close(dirfd);
        return errno;
    }

    struct dirent *de;
    while ((de = readdir(d)) != NULL) {
        if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..")) continue;

        char childPath[PATH_MAX];
        snprintf(childPath, sizeof(childPath), "%s/%s", path, de->d_name);

        struct stat csb;
        if (lstat(childPath, &csb) != 0) {
            if (errno == ENOENT) continue;
            if (firstErr == 0) firstErr = errno;
            continue;
        }

        if (S_ISDIR(csb.st_mode)) {
            int rr = rmrf_in_process(childPath);
            if (rr != 0 && firstErr == 0) firstErr = rr;
        }
        else {
            if (unlink(childPath) != 0 && errno != ENOENT && firstErr == 0) {
                firstErr = errno;
            }
        }
    }
    closedir(d); // also closes dirfd

    if (rmdir(path) != 0 && errno != ENOENT && firstErr == 0) {
        firstErr = errno;
    }
    return firstErr;
}

static int rmrf_in_process_obj(NSString *path)
{
    return rmrf_in_process(path.fileSystemRepresentation);
}

// True when `path` itself is a symbolic link. NSFileManager's
// attributesOfItemAtPath: FOLLOWS symlinks, so it reports the target's type for
// a live link and fails outright for a dangling one — which means an
// "NSFileType == NSFileTypeSymbolicLink" test never matches anything. lstat is
// the only correct way to detect a link, and dangling links are exactly the
// traces this sweep exists to remove.
static BOOL is_symlink_path(NSString *path)
{
    struct stat sb;
    if (lstat(path.fileSystemRepresentation, &sb) != 0) return NO;
    return S_ISLNK(sb.st_mode);
}

static void remove_symlink_path(NSString *path)
{
    if (unlink(path.fileSystemRepresentation) == 0) {
        NSLog(@"[RootHide] deleteBootstrap: removed symlink %@", path);
    }
}

- (NSError *)deleteBootstrap
{
    // =========================================================================
    // Full remove-jailbreak cleanup (rewritten).
    //
    // The old implementation deleted only the two/three .jbroot-<JBRAND>
    // directories, never checked the rm exit status, and left every artifact
    // the jailbreak had published OUTSIDE those directories behind:
    //
    //   - /var/tmp/bootstrap.tar and /var/tmp/bootstrap_restore.tar
    //     (decompressed bootstrap leftovers, several dozen MB each)
    //   - /var/jb symlink (legacy rootless JB entry point; also recreated by
    //     other jailbreaks — remove when present)
    //   - xinaA15-style /var/<dir> leftover symlinks (same list prepareBootstrap
    //     already cleans when starting a FRESH bootstrap)
    //   - .jbroot symlinks INSIDE user app containers, created by
    //     ensureJbrootSymlinksInApps / ensure_jbroot_symlink for every jbroot
    //     app (Sileo, Zebra, RootHide Manager, RootHidePatcher...). When the
    //     jbroot disappears these become dangling symlinks pointing into a
    //     deleted directory — any app container carrying one is a visible
    //     jailbreak trace (and crashes the removed jbroot apps if they are
    //     still launched from caches).
    //   - the fake dyld names that were published into the kernel namecache
    //     (kernel state — dies with the next userspace reboot / full reboot,
    //     nothing to remove on disk here)
    //
    // Deletions are performed in-process with plain syscalls (see
    // rmrf_in_process above) — spawning /bin/rm fails with EPERM because the
    // persona override is rejected. Every failure is recorded and reported to
    // the caller instead of being silently swallowed (the old code returned nil
    // no matter what happened).
    // =========================================================================
    NSError *error = [self ensurePrivatePrebootIsWritable];
    if (error) return error;

    NSString *jbrootPath = [NSString stringWithUTF8String:gSystemInfo.jailbreakInfo.rootPath ?: ""];
    if (jbrootPath.length == 0) {
        // jbroot unknown — try to locate it before doing anything else
        [[DOEnvironmentManager sharedManager] locateJailbreakRoot];
        jbrootPath = [NSString stringWithUTF8String:gSystemInfo.jailbreakInfo.rootPath ?: ""];
        if (jbrootPath.length == 0) {
            NSLog(@"[RootHide] deleteBootstrap: no jbroot found — nothing to delete");
            return nil;
        }
    }

    NSMutableArray<NSString *> *errors = [NSMutableArray array];

    // 1. Remove /var/tmp leftovers (bootstrap tarballs)
    NSArray<NSString *> *varTmpLeftovers = @[
        @"/var/tmp/bootstrap.tar",
        @"/var/tmp/bootstrap_restore.tar",
    ];
    for (NSString *leftover in varTmpLeftovers) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:leftover]) {
            int r = rmrf_in_process_obj(leftover);
            if (r != 0) {
                NSLog(@"[RootHide] deleteBootstrap: rm %@ failed (errno %d)", leftover, r);
                [errors addObject:[NSString stringWithFormat:@"rm %@ (%d)", leftover, r]];
            } else {
                NSLog(@"[RootHide] deleteBootstrap: removed %@", leftover);
            }
        }
    }

    // 2. Remove legacy entry-point symlinks (other jailbreaks may have left them)
    rmrf_in_process_obj(@"/var/jb");

    // 3. Remove xinaA15-style leftover symlinks in /var (same list as
    //    prepareBootstrap uses for a fresh install; only removes them when
    //    they are symlinks so a real user directory named e.g. /var/bin
    //    is never touched).
    NSArray<NSString *> *varSymlinkLeftovers = @[
        @"/var/alternatives", @"/var/ap", @"/var/apt", @"/var/bin",
        @"/var/bzip2", @"/var/cache", @"/var/comm", @"/var/etc",
        @"/var/include", @"/var/info", @"/var/lib", @"/var/libexec",
        @"/var/limits", @"/var/local", @"/var/log", @"/var/logs",
        @"/var/man", @"/var/mds", @"/var/mds-coll", @"/var/mnt",
        @"/var/msg", @"/var/pref", @"/var/run", @"/var/sbin",
        @"/var/share", @"/var/spool", @"/var/src", @"/var/stash",
        @"/var/sy", @"/var/symbolic", @"/var/tar", @"/var/tmp",
        @"/var/ucb", @"/var/undone", @"/var/usr", @"/var/X11",
        @"/var/xbin", @"/var/zbin",
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *leftover in varSymlinkLeftovers) {
        if (is_symlink_path(leftover)) {
            // Only remove when the symlink target is gone or points into the
            // jbroot — never delete a link to a live system directory.
            char linkBuf[PATH_MAX] = { 0 };
            ssize_t linkLen = readlink(leftover.fileSystemRepresentation, linkBuf, sizeof(linkBuf) - 1);
            if (linkLen <= 0) continue;
            NSString *dest = [NSString stringWithUTF8String:linkBuf] ?: @"";
            char resolvedBuf[PATH_MAX] = { 0 };
            BOOL targetMissing = (realpath(leftover.fileSystemRepresentation, resolvedBuf) == NULL);
            BOOL targetInJbroot = [dest hasPrefix:@"/var/jb"] || [dest hasPrefix:jbrootPath] ||
                                  [dest containsString:@".jbroot-"];
            if (targetMissing || targetInJbroot) {
                remove_symlink_path(leftover);
            }
        }
    }

    // 4. Remove the jbroot directory itself (primary)
    NSLog(@"[RootHide] deleteBootstrap: removing %@", jbrootPath);
    int rmJbroot = rmrf_in_process_obj(jbrootPath);
    if (rmJbroot != 0) {
        NSLog(@"[RootHide] deleteBootstrap: rm jbroot failed (errno %d)", rmJbroot);
        [errors addObject:[NSString stringWithFormat:@"rm %@ (%d)", jbrootPath, rmJbroot]];
    } else {
        NSLog(@"[RootHide] deleteBootstrap: removed jbroot at %@", jbrootPath);
    }

    // 5. Remove secondary containers (AppGroup + old-style Data path)
    NSString *jbrootName = jbrootPath.lastPathComponent;
    NSArray<NSString *> *secondaryPaths = @[
        [NSString stringWithFormat:@"/var/mobile/Containers/Shared/AppGroup/%@", jbrootName],
        [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@", jbrootName],
    ];
    for (NSString *secondaryPath in secondaryPaths) {
        int r = rmrf_in_process_obj(secondaryPath);
        if (r != 0) {
            NSLog(@"[RootHide] deleteBootstrap: rm %@ failed (errno %d)", secondaryPath, r);
            [errors addObject:[NSString stringWithFormat:@"rm %@ (%d)", secondaryPath, r]];
        } else {
            NSLog(@"[RootHide] deleteBootstrap: removed secondary %@", secondaryPath);
        }
    }

    // 6. Remove dangling .jbroot symlinks from user app containers.
    //    ensureJbrootSymlinksInApps created <jbroot>/Applications/Foo.app/.jbroot
    //    (inside the jbroot — already gone with step 4), and libjailbreak's
    //    ensure_jbroot_symlink can additionally create one next to any real
    //    directory that resolved into the jbroot. Sweep BOTH app container
    //    roots for leftover .jbroot symlinks and delete them.
    NSArray<NSString *> *appContainerRoots = @[
        @"/var/containers/Bundle/Application",
        @"/var/mobile/Containers/Data/Application",
        @"/var/mobile/Containers/Shared/AppGroup",
    ];
    for (NSString *containerRoot in appContainerRoots) {
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:containerRoot error:nil];
        if (!entries) continue; // sandboxed / not listable — best effort only
        for (NSString *entry in entries) {
            NSString *entryPath = [containerRoot stringByAppendingPathComponent:entry];
            // (a) the container itself was a .jbroot-XXXX dir (secondary copy) — gone via step 5
            if ([entry hasPrefix:@".jbroot-"]) continue;
            // (b) a .jbroot symlink directly inside the container directory
            NSString *directSymlink = [entryPath stringByAppendingPathComponent:@".jbroot"];
            if (is_symlink_path(directSymlink)) {
                remove_symlink_path(directSymlink);
            }
            // (c) .app bundles inside a UUID container dir:
            //     <container>/<UUID>/Payload/Foo.app/.jbroot and
            //     <container>/<UUID>/Foo.app/.jbroot ( TrollStore layout)
            if ([entry hasSuffix:@".app"]) {
                NSString *bundleSymlink = [entryPath stringByAppendingPathComponent:@".jbroot"];
                if (is_symlink_path(bundleSymlink)) {
                    remove_symlink_path(bundleSymlink);
                }
            }
            else {
                // Enumerate one level into the UUID directory for .app bundles
                NSArray<NSString *> *innerEntries = [fm contentsOfDirectoryAtPath:entryPath error:nil];
                for (NSString *inner in innerEntries ?: @[]) {
                    NSString *innerPath = [entryPath stringByAppendingPathComponent:inner];
                    if ([inner hasSuffix:@".app"]) {
                        NSString *bundleSymlink = [innerPath stringByAppendingPathComponent:@".jbroot"];
                        if (is_symlink_path(bundleSymlink)) remove_symlink_path(bundleSymlink);
                        continue;
                    }
                    if (![inner isEqual:@"Payload"]) continue;
                    NSString *payloadSymlink = [innerPath stringByAppendingPathComponent:@".jbroot"];
                    if (is_symlink_path(payloadSymlink)) remove_symlink_path(payloadSymlink);
                    for (NSString *payloadApp in [fm contentsOfDirectoryAtPath:innerPath error:nil] ?: @[]) {
                        if (![payloadApp hasSuffix:@".app"]) continue;
                        NSString *appSymlink = [[innerPath stringByAppendingPathComponent:payloadApp] stringByAppendingPathComponent:@".jbroot"];
                        if (is_symlink_path(appSymlink)) remove_symlink_path(appSymlink);
                    }
                }
            }
        }
    }

    if (errors.count > 0) {
        return [NSError errorWithDomain:bootstrapErrorDomain code:-1
                               userInfo:@{NSLocalizedDescriptionKey :
                                          [NSString stringWithFormat:@"Remove jailbreak failed for %lu target(s): %@",
                                           (unsigned long)errors.count, [errors componentsJoinedByString:@", "]]}];
    }

    NSLog(@"[RootHide] deleteBootstrap: cleanup complete");
    return nil;
}

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
