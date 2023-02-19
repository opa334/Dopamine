#import "JBDFileTree.h"

@implementation JBDFileTree

- (BOOL)shouldIncludeItemAtPath:(NSString *)path
{
	NSString* sharePath = [_observePath stringByAppendingPathComponent:@"usr/share"];
	NSString* basebinPath = [_observePath stringByAppendingPathComponent:@"basebin"];

	if ([path hasPrefix:sharePath] || [path hasPrefix:basebinPath]) {
		return NO;
	}

	NSArray *ignoredExtensions = @[
		@"dpkg-tmp",
		@"dpkg-new",
		@"zst",
		@"deb",
		@"tar",
	];

	if ([ignoredExtensions containsObject:path.pathExtension]) return NO;

	return YES;
}

- (void)mustRescan
{
	extern void rebuildTrustCache(void);
	rebuildTrustCache();
}

@end