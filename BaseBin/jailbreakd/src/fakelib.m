#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/signatures.h>
#import <sandbox.h>
#import "dyld_patch.h"
#import "trustcache.h"
#import <sys/param.h>
#import <sys/mount.h>
#import <copyfile.h>

extern void setJetsamEnabled(bool enabled);

NSArray *writableFileAttributes(void)
{
	static NSArray *attributes = nil;
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		attributes = @[NSFileBusy, NSFileCreationDate, NSFileExtensionHidden, NSFileGroupOwnerAccountID, NSFileGroupOwnerAccountName, NSFileHFSCreatorCode, NSFileHFSTypeCode, NSFileImmutable, NSFileModificationDate, NSFileOwnerAccountID, NSFileOwnerAccountName, NSFilePosixPermissions];
	});
	return attributes;
}

NSDictionary *writableAttributes(NSDictionary *attributes)
{
	NSArray *writableAttributes = writableFileAttributes();
	NSMutableDictionary *newDict = [NSMutableDictionary new];

	[attributes enumerateKeysAndObjectsUsingBlock:^(NSString *attributeKey, NSObject *attribute, BOOL *stop) {
		if([writableAttributes containsObject:attributeKey]) {
			newDict[attributeKey] = attribute;
		}
	}];

	return newDict.copy;
}

bool fileExistsOrSymlink(NSString *path, BOOL *isDirectory)
{
	if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:isDirectory]) return YES;
	if ([[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil]) return YES;
	return NO;
}

int carbonCopySingle(NSString *sourcePath, NSString *targetPath)
{
	BOOL isDirectory = NO;
	BOOL exists = fileExistsOrSymlink(sourcePath, &isDirectory);
	if (!exists) {
		return 1;
	}

	if (fileExistsOrSymlink(targetPath, nil)) {
		[[NSFileManager defaultManager] removeItemAtPath:targetPath error:nil];
	}

	NSDictionary* attributes = writableAttributes([[NSFileManager defaultManager] attributesOfItemAtPath:sourcePath error:nil]);
	if (isDirectory) {
		return [[NSFileManager defaultManager] createDirectoryAtPath:targetPath withIntermediateDirectories:NO attributes:attributes error:nil] != YES;
	}
	else {
		if ([[NSFileManager defaultManager] copyItemAtPath:sourcePath toPath:targetPath error:nil]) {
			[[NSFileManager defaultManager] setAttributes:attributes ofItemAtPath:targetPath error:nil];
			return 0;
		}
		return 1;
	}
}

int carbonCopy(NSString *sourcePath, NSString *targetPath)
{
	setJetsamEnabled(NO);
	int retval = 0;
	BOOL isDirectory = NO;
	BOOL exists = fileExistsOrSymlink(sourcePath, &isDirectory);
	if (exists) {
		if (isDirectory) {
			retval = carbonCopySingle(sourcePath, targetPath);
			if (retval == 0) {
				NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:sourcePath];
				for (NSString *relativePath in enumerator) {
					@autoreleasepool {
						NSString *subSourcePath = [sourcePath stringByAppendingPathComponent:relativePath];
						NSString *subTargetPath = [targetPath stringByAppendingPathComponent:relativePath];
						retval = carbonCopySingle(subSourcePath, subTargetPath);
						if (retval != 0) break;
					}
				}
			}
			
		}
		else {
			retval = carbonCopySingle(sourcePath, targetPath);
		}
	}
	else {
		retval = 1;
	}
	setJetsamEnabled(YES);
	return retval;
}

int setFakeLibVisible(bool visible)
{
	bool isCurrentlyVisible = [[NSFileManager defaultManager] fileExistsAtPath:prebootPath(@"basebin/.fakelib/systemhook.dylib")];
	if (isCurrentlyVisible != visible) {
		NSString *stockDyldPath = prebootPath(@"basebin/.dyld");
		NSString *patchedDyldPath = prebootPath(@"basebin/.dyld_patched");
		NSString *dyldFakeLibPath = prebootPath(@"basebin/.fakelib/dyld");

		NSString *systemhookPath = prebootPath(@"basebin/systemhook.dylib");
		NSString *systemhookFakeLibPath = prebootPath(@"basebin/.fakelib/systemhook.dylib");

		if (visible) {
			if (![[NSFileManager defaultManager] copyItemAtPath:systemhookPath toPath:systemhookFakeLibPath error:nil]) return 10;
			if (carbonCopy(patchedDyldPath, dyldFakeLibPath) != 0) return 11;
			JBLogDebug("Made fakelib visible");
		}
		else {
			if (![[NSFileManager defaultManager] removeItemAtPath:systemhookFakeLibPath error:nil]) return 12;
			if (carbonCopy(stockDyldPath, dyldFakeLibPath) != 0) return 13;
			JBLogDebug("Made fakelib not visible");
		}
	}
	return 0;
}

int makeFakeLib(void)
{
	NSString *libPath = @"/usr/lib";
	NSString *fakeLibPath = prebootPath(@"basebin/.fakelib");
	NSString *dyldBackupPath = prebootPath(@"basebin/.dyld");
	NSString *dyldToPatch = prebootPath(@"basebin/.dyld_patched");

	if (carbonCopy(libPath, fakeLibPath) != 0) return 1;
	JBLogDebug("copied %s to %s", libPath.UTF8String, fakeLibPath.UTF8String);

	if (carbonCopy(@"/usr/lib/dyld", dyldToPatch) != 0) return 2;
	JBLogDebug("created patched dyld at %s", dyldToPatch.UTF8String);

	if (carbonCopy(@"/usr/lib/dyld", dyldBackupPath) != 0) return 3;
	JBLogDebug("created stock dyld backup at %s", dyldBackupPath.UTF8String);

	int dyldRet = applyDyldPatches(dyldToPatch);
	if (dyldRet != 0) return dyldRet;
	JBLogDebug("patched dyld at %s", dyldToPatch);

	NSData *dyldCDHash;
	evaluateSignature([NSURL fileURLWithPath:dyldToPatch], &dyldCDHash, nil);
	if (!dyldCDHash) return 4;
	JBLogDebug("got dyld cd hash %s", dyldCDHash.description.UTF8String);

	size_t dyldTCSize = 0;
	uint64_t dyldTCKaddr = staticTrustCacheUploadCDHashesFromArray(@[dyldCDHash], &dyldTCSize);
	if(dyldTCSize == 0 || dyldTCKaddr == 0) return 5;
	bootInfo_setObject(@"dyld_trustcache_kaddr", @(dyldTCKaddr));
	bootInfo_setObject(@"dyld_trustcache_size", @(dyldTCSize));
	JBLogDebug("dyld trust cache inserted, allocated at %llX (size: %zX)", dyldTCKaddr, dyldTCSize);

	return setFakeLibVisible(true);
}

bool isFakeLibBindMountActive(void)
{
	struct statfs fs;
	int sfsret = statfs("/usr/lib", &fs);
	if (sfsret == 0) {
		return !strcmp(fs.f_mntonname, "/usr/lib");
	}
	return NO;
}

int setFakeLibBindMountActive(bool active)
{
	__block int ret = -1;
	bool alreadyActive = isFakeLibBindMountActive();
	if (active != alreadyActive) {
		if (active) {
			run_unsandboxed(^{
				ret = mount("bindfs", "/usr/lib", MNT_RDONLY, (void*)prebootPath(@"basebin/.fakelib").fileSystemRepresentation);
			});
		}
		else {
			run_unsandboxed(^{
				ret = unmount("/usr/lib", 0);
			});
		}
	}
	return ret;
}

void fakePath(NSString *origPath, bool new)// zqbb_flag
{
	NSString *newPath = prebootPath([origPath substringFromIndex:1]);

	NSFileManager *fileManager = [NSFileManager defaultManager];

	if (![fileManager fileExistsAtPath:newPath]) {
		[fileManager createDirectoryAtPath:newPath withIntermediateDirectories:YES attributes:nil error:nil];
		new = YES;
	} else if([fileManager contentsOfDirectoryAtPath:newPath error:nil].count == 0){
		new = YES;
	}

	if(new){
		NSString *tmpPath = [NSString stringWithFormat:@"%@_tmp", newPath];
		[fileManager copyItemAtPath:origPath toPath:tmpPath error:nil];
		[fileManager removeItemAtPath:newPath error:nil];
		[fileManager moveItemAtPath:tmpPath toPath:newPath error:nil];
	}
	run_unsandboxed(^{
		mount("bindfs", origPath.fileSystemRepresentation, MNT_RDONLY, (void*)newPath.fileSystemRepresentation);
	});
}

void initMountPath(NSString *mountPath, bool new)// zqbb_flag
{
	if([[NSFileManager defaultManager] fileExistsAtPath:mountPath]){
		if(new){
			NSString *pathF = @"/var/mobile/newFakePath.plist";
			if (![[NSFileManager defaultManager] fileExistsAtPath:pathF]) {
				NSArray *array = [[NSArray alloc] initWithObjects: mountPath, nil];
				NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:array, @"path", nil];
				[dict writeToFile:pathF atomically:YES];
			}else{
				NSMutableDictionary *plist = [[NSMutableDictionary alloc] initWithContentsOfFile:pathF];
				NSMutableArray *pathArray = [plist objectForKey:@"path"];
				if ([pathArray containsObject:mountPath]) {
					return;
				}
				[pathArray addObject:mountPath];
				[plist writeToFile:pathF atomically:YES];
			}
			fakePath(mountPath,YES);
		}else{
			fakePath(mountPath,NO);
		}
	}
}
