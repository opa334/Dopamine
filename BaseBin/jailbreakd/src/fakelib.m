#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/signatures.h>
#import <sandbox.h>
#import "dyld_patch.h"
#import "trustcache.h"

void generateSystemWideSandboxExtensions(NSString *targetPath)
{
	NSMutableArray *extensions = [NSMutableArray new];

	char *extension = NULL;

	// Make /var/jb readable
	extension = sandbox_extension_issue_file("com.apple.app-sandbox.read", "/var/jb", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];

	// Make binaries in /var/jb executable
	extension = sandbox_extension_issue_file("com.apple.sandbox.executable", "/var/jb", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];

	// Ensure the whole system has access to com.opa334.jailbreakd.systemwide
	extension = sandbox_extension_issue_mach("com.apple.app-sandbox.mach", "com.opa334.jailbreakd.systemwide", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];
	extension = sandbox_extension_issue_mach("com.apple.security.exception.mach-lookup.global-name", "com.opa334.jailbreakd.systemwide", 0);
	if (extension) [extensions addObject:[NSString stringWithUTF8String:extension]];

	NSDictionary *dictToSave = @{ @"extensions" : extensions };
	[dictToSave writeToFile:targetPath atomically:NO];
}

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
	BOOL isDirectory = NO;
	BOOL exists = fileExistsOrSymlink(sourcePath, &isDirectory);
	if (!exists) return 1;

	if (isDirectory) {
		int r = carbonCopySingle(sourcePath, targetPath);
		if (r != 0) return r;
		NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:sourcePath];
		for (NSString *relativePath in enumerator) {
			NSString *subSourcePath = [sourcePath stringByAppendingPathComponent:relativePath];
			NSString *subTargetPath = [targetPath stringByAppendingPathComponent:relativePath];
			r = carbonCopySingle(subSourcePath, subTargetPath);
			if (r != 0) return r;
		}
		return 0;
	}
	else {
		return carbonCopySingle(sourcePath, targetPath);
	}
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
		NSString *sandboxFakeLibPath = prebootPath(@"basebin/.fakelib/sandbox.plist");

		if (visible) {
			if (![[NSFileManager defaultManager] copyItemAtPath:systemhookPath toPath:systemhookFakeLibPath error:nil]) return 10;
			if (carbonCopy(patchedDyldPath, dyldFakeLibPath) != 0) return 11;
			generateSystemWideSandboxExtensions(sandboxFakeLibPath);
			JBLogDebug("Made fakelib visible");
		}
		else {
			if (![[NSFileManager defaultManager] removeItemAtPath:systemhookFakeLibPath error:nil]) return 12;
			if (carbonCopy(stockDyldPath, dyldFakeLibPath) != 0) return 13;
			if (![[NSFileManager defaultManager] removeItemAtPath:sandboxFakeLibPath error:nil]) return 14;
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
	if(dyldTCSize == 0 || dyldTCKaddr == 0) return 4;
	bootInfo_setObject(@"dyld_trustcache_kaddr", @(dyldTCKaddr));
	bootInfo_setObject(@"dyld_trustcache_size", @(dyldTCSize));
	JBLogDebug("dyld trust cache inserted, allocated at %llX (size: %zX)", dyldTCKaddr, dyldTCSize);

	return setFakeLibVisible(true);
}
