#import <Foundation/Foundation.h>
#import <CoreServices/LSApplicationProxy.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/boot_info.h>
#import "trustcache.h"
#import "spawn_wrapper.h"
#include <libarchive/archive.h>
#include <libarchive/archive_entry.h>

static int
copy_data(struct archive *ar, struct archive *aw)
{
  int r;
  const void *buff;
  size_t size;
  la_int64_t offset;

  for (;;) {
    r = archive_read_data_block(ar, &buff, &size, &offset);
    if (r == ARCHIVE_EOF)
      return (ARCHIVE_OK);
    if (r < ARCHIVE_OK)
      return (r);
    r = archive_write_data_block(aw, buff, size, offset);
    if (r < ARCHIVE_OK) {
      fprintf(stderr, "%s\n", archive_error_string(aw));
      return (r);
    }
  }
}

int extract(NSString* fileToExtract, NSString* extractionPath)
{
    struct archive *a;
    struct archive *ext;
    struct archive_entry *entry;
    int flags;
    int r;

    /* Select which attributes we want to restore. */
    flags = ARCHIVE_EXTRACT_TIME;
    flags |= ARCHIVE_EXTRACT_PERM;
    flags |= ARCHIVE_EXTRACT_ACL;
    flags |= ARCHIVE_EXTRACT_FFLAGS;

    a = archive_read_new();
    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    ext = archive_write_disk_new();
    archive_write_disk_set_options(ext, flags);
    archive_write_disk_set_standard_lookup(ext);
    if ((r = archive_read_open_filename(a, fileToExtract.fileSystemRepresentation, 10240)))
        return 1;
    for (;;)
    {
        r = archive_read_next_header(a, &entry);
        if (r == ARCHIVE_EOF)
            break;
        if (r < ARCHIVE_OK)
            fprintf(stderr, "%s\n", archive_error_string(a));
        if (r < ARCHIVE_WARN)
            return 1;
        
        NSString* currentFile = [NSString stringWithUTF8String:archive_entry_pathname(entry)];
        NSString* fullOutputPath = [extractionPath stringByAppendingPathComponent:currentFile];
        //printf("extracting %@ to %@\n", currentFile, fullOutputPath);
        archive_entry_set_pathname(entry, fullOutputPath.fileSystemRepresentation);
        
        r = archive_write_header(ext, entry);
        if (r < ARCHIVE_OK)
            fprintf(stderr, "%s\n", archive_error_string(ext));
        else if (archive_entry_size(entry) > 0) {
            r = copy_data(a, ext);
            if (r < ARCHIVE_OK)
                fprintf(stderr, "%s\n", archive_error_string(ext));
            if (r < ARCHIVE_WARN)
                return 1;
        }
        r = archive_write_finish_entry(ext);
        if (r < ARCHIVE_OK)
            fprintf(stderr, "%s\n", archive_error_string(ext));
        if (r < ARCHIVE_WARN)
            return 1;
    }
    archive_read_close(a);
    archive_read_free(a);
    archive_write_close(ext);
    archive_write_free(ext);
    
    return 0;
}

NSString *trollStoreRootHelperPath(void)
{
	LSApplicationProxy *appProxy = [LSApplicationProxy applicationProxyForIdentifier:@"com.opa334.TrollStore"];
	return [appProxy.bundleURL.path stringByAppendingPathComponent:@"trollstorehelper"];
}

int basebinUpdateFromTar(NSString *basebinPath)
{
	uint64_t existingTCKaddr = bootInfo_getUInt64(@"basebin_trustcache_kaddr");
	uint64_t existingTCLength = kread32(existingTCKaddr + offsetof(trustcache_page, file.length));
	uint64_t existingTCSize = sizeof(trustcache_page) + (sizeof(trustcache_entry) * existingTCLength);

	NSString *tmpExtractionPath = [NSTemporaryDirectory() stringByAppendingString:[NSUUID UUID].UUIDString];
	int extractRet = extract(basebinPath, tmpExtractionPath);
	if (extractRet != 0) {
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
	int bbRet = basebinUpdateFromTar([appProxy.bundleURL.path stringByAppendingPathComponent:@"basebin.tar"]);
	if (bbRet != 0) return 2 + bbRet;
	return 0;
}