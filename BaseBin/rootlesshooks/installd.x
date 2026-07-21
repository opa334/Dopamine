#import <Foundation/Foundation.h>

// BOOTLOOP RISK, DO NOT TOUCH
/*%hook MIGlobalConfiguration

- (NSMutableDictionary *)_bundleIDMapForBundlesInDirectory:(NSURL *)directoryURL
											 withExtension:(NSString *)extension
									 loadingAdditionalKeys:(NSSet *)additionalKeys
{
	NSLog(@"_bundleIDMapForBundlesInDirectory(%@, %@, %@)", directoryURL, extension, additionalKeys);

	if ([directoryURL.path isEqualToString:@"/Applications"] && [extension isEqualToString:@"app"]) {
		NSMutableDictionary *origMap = %orig;

		NSURL *rootlessAppDir = [NSURL fileURLWithPath:@"/var/jb/Applications" isDirectory:YES];
		NSMutableDictionary *rootlessAppsMap = %orig(rootlessAppDir, extension, additionalKeys);
		[origMap addEntriesFromDictionary:rootlessAppsMap];
		return origMap;
	}

	return %orig;
}

%end*/

void installdInit(void)
{
	%init();
}
