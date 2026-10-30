#import <Foundation/Foundation.h>
#import <substrate.h>
#import <objc/objc.h>
#import <libroot.h>

@interface XBSnapshotContainerIdentity : NSObject
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@end

@interface XBApplicationSnapshot : NSObject
- (XBSnapshotContainerIdentity *)containerIdentity;
- (NSString *)_configureDefaultPathWithinGroupForFormat:(long long)format;
@end

@interface XBApplicationSnapshotManifestImpl : NSObject
+ (long long)_outputFormatForSnapshot:(id)snapshot;
@end

%hook XBSnapshotContainerIdentity

- (NSString *)snapshotContainerPath
{
    NSString *path = %orig;
    if([path hasPrefix:@"/var/mobile/Library/SplashBoard/Snapshots/"] && ![self.bundleIdentifier hasPrefix:@"com.apple."]) {
        return JBROOT_PATH_NSSTRING(path);
    }
    return path;
}

%end

%hook XBApplicationSnapshotManifestImpl

- (BOOL)_imageAccessQueue_saveData:(NSData *)data forSnapshot:(XBApplicationSnapshot *)snapshot
{
    if (!data.length || !snapshot) {
        return %orig;
    }
    
    if ([snapshot.containerIdentity.bundleIdentifier hasPrefix:@"com.apple."]) {
        return %orig;
    }
    
    NSString *path = [snapshot _configureDefaultPathWithinGroupForFormat: [[self class] _outputFormatForSnapshot:snapshot]];
    if (!path)  {
        return NO;
    }
    
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:nil];
    return [data writeToFile:path options:0 error:nil];
}

%end

void springboardInit(void)
{
    %init();
}
