#import <Foundation/Foundation.h>
#import <CoreServices/LSApplicationProxy.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/boot_info.h>
#import "trustcache.h"
#import "spawn_wrapper.h"

NSString *trollStoreRootHelperPath(void)
{
	LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:@"com.opa334.TrollStore"];
	return [appProxy.bundleURL.path stringByAppendingString:@"trollstorehelper"];
}

int basebinUpdateFromTar(NSString *basebinPath)
{
	uint64_t existingTCKaddr = bootInfo_getUInt64(@"basebin_trustcache_kaddr");
	uint64_t existingTCLength = kread64(existingTCKaddr + offsetof(trustcache_page, file.length));
	uint64_t existingTCSize = sizeof(trustcache_page) + (sizeof(trustcache_entry) * existingTCLength);

	NSString *tmpExtractionPath = [NSTemporaryDirectory() stringByAppendingString:[NSUUID UUID].UUIDString];
	int tarRet = spawn(@"/var/jb/basebin/tar", @[@"-xf", @"-C", tmpExtractionPath]);
	if (tarRet != 0) {
		[[NSFileManager defaultManager] removeItemAtPath:tmpExtractionPath error:nil];
		return 1;
	}

	NSString *tmpBasebinPath = [tmpExtractionPath stringByAppendingPathComponent:@"basebin"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:tmpBasebinPath]) {
		[[NSFileManager defaultManager] removeItemAtPath:tmpExtractionPath error:nil];
		return 2;
	}

	NSString *newTrustcachePath = [tmpBasebinPath stringByAppendingPathComponent:@"basebin.tc"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:newTrustcachePath]) {
		[[NSFileManager defaultManager] removeItemAtPath:tmpExtractionPath error:nil];
		return 3;
	}

	uint64_t newTCKaddr = staticTrustCacheUploadFileAtPath(newTrustcachePath, NULL);
	if (!newTCKaddr) {
		[[NSFileManager defaultManager] removeItemAtPath:tmpExtractionPath error:nil];
		return 4;
	}

	// Copy new basebin over old basebin
	NSArray *basebinItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmpBasebinPath error:nil];
	for (NSString *basebinItem in basebinItems) {
		NSString *oldBasebinPath = [@"/var/jb/basebin" stringByAppendingPathComponent:basebinItem];
		NSString *newBasebinPath = [tmpBasebinPath stringByAppendingPathComponent:basebinItem];
		if ([[NSFileManager defaultManager] fileExistsAtPath:oldBasebinPath]) {
			[[NSFileManager defaultManager] removeItemAtPath:oldBasebinPath error:nil];
		}
		[[NSFileManager defaultManager] copyItemAtPath:newBasebinPath toPath:oldBasebinPath error:nil];
	}

	bootInfo_setObject(@"basebin_trustcache_kaddr", @(newTCKaddr));
	trustCacheListRemove(existingTCKaddr);

	// there is a non zero chance that the kernel is in the process of reading the
	// trustcache page even after we removed it, so we wait a second before freeing it
	sleep(1);

	kfree(existingTCKaddr, existingTCSize);
	return 0;
}

int jbUpdateFromTIPA(NSString *tipaPath)
{
	NSString *tsRootHelperPath = trollStoreRootHelperPath();
	if (!tsRootHelperPath) return 1;
	int installRet = spawn(tsRootHelperPath, @[@"install", tipaPath]);
	if (installRet != 0) return 2;

	// XXX: change to real bundle identifier
	LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:@"de.pinauten.Fugu15"];
	int bbRet = basebinUpdateFromTar([appProxy.bundleURL.path stringByAppendingString:@"basebin.tar"]);
	if (bbRet != 0) return 2 + bbRet;
	return 0;
}