#include "info.h"
#import <Foundation/Foundation.h>
#import "util.h"
#import <sys/stat.h>

bool is_dopamine_app(const char *pathC)
{
	if (!jbinfo(appIdentifier)) return false;

	// Make sure the prefix is sane
	const char wantedPrefixC[] = "/private/var/containers/Bundle/Application/";
	if (strncmp(pathC, wantedPrefixC, (sizeof(wantedPrefixC) - 1)) != 0) return false;

	// Make sure there are no path traversals
	if (strstr(pathC, "/../")) return false;

	// Stricly enforce the number of slashes (8)
	// /private/var/containers/Bundle/Application/*/*.app/*
	// ^       ^   ^          ^      ^           ^ ^     ^
	uint64_t slashNum = 0;
	uint64_t idx = 0;
	while (pathC[idx] != 0) {
		if (pathC[idx++] == '/') {
			slashNum++;
		}
	}
	if (slashNum != 8) return false;

	@autoreleasepool {
		NSString *path = [NSString stringWithUTF8String:pathC];
		NSString *infoPlistPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Info.plist"];
		if (![[NSFileManager defaultManager] fileExistsAtPath:infoPlistPath]) return false;

		NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
		NSString *bundleIdentifier = infoPlist[@"CFBundleIdentifier"];
		if (!bundleIdentifier) return false;

		return !strcmp(bundleIdentifier.UTF8String, jbinfo(appIdentifier));
	}
}

NSString *NSPrebootUUIDPath(NSString *relativePath)
{
	@autoreleasepool {
		return [NSString stringWithUTF8String:prebootUUIDPath(relativePath.UTF8String)];
	}
}

void _JBFixMobilePermissionsOfDirectory(NSString *directoryPath, BOOL recursive)
{
	struct stat s;
	NSURL *directoryURL = [NSURL fileURLWithPath:directoryPath];

	if (stat(directoryURL.fileSystemRepresentation, &s) == 0) {
		if (s.st_uid != 501 || s.st_gid != 501) {
			chown(directoryURL.fileSystemRepresentation, 501, 501);
		}
	}

	if (recursive) {
		NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:directoryURL includingPropertiesForKeys:nil options:0 errorHandler:nil];
		for (NSURL *fileURL in enumerator) {
			if (stat(fileURL.fileSystemRepresentation, &s) == 0) {
				if (s.st_uid != 501 || s.st_gid != 501) {
					chown(fileURL.fileSystemRepresentation, 501, 501);
				}
			}
		}
	}
}

void JBFixMobilePermissions(void)
{
	@autoreleasepool {
/*********************************** on roothide jbroot:/var is always a symlink ***************************************************
		NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:JBROOT_PATH(@"/var") error:nil];
		if ([attributes[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
			// /var/jb/var is a symlink, abort
			return;
		}
		attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:JBROOT_PATH(@"/var/mobile") error:nil];
		if ([attributes[NSFileType] isEqualToString:NSFileTypeSymbolicLink]) {
			// /var/jb/var/mobile is a symlink, abort
			return;
		}
***********************************************************************************************************************************/

		_JBFixMobilePermissionsOfDirectory(JBROOT_PATH(@"/var/mobile"), NO);
		_JBFixMobilePermissionsOfDirectory(JBROOT_PATH(@"/var/mobile/Library"), NO);
		_JBFixMobilePermissionsOfDirectory(JBROOT_PATH(@"/var/mobile/Library/SplashBoard"), YES);
		_JBFixMobilePermissionsOfDirectory(JBROOT_PATH(@"/var/mobile/Library/Application Support"), YES);
		_JBFixMobilePermissionsOfDirectory(JBROOT_PATH(@"/var/mobile/Library/Preferences"), YES);
	}
}