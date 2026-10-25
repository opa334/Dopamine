#import <Foundation/Foundation.h>
#include <roothide.h>
#include <libgen.h>
#include "common.h"

/* Fixed the "RUNNINGBOARD 3735883980" issue, which was caused by roothide uicache
 redirecting jailbroken app environment variables to `jbroot` (within the roothide filesystem r^x architecture) */

@interface RBProcess : NSObject
-(int)rbs_pid;
@end

NSSet<NSString*>* fixAllowedPaths(pid_t pid, NSSet<NSString*>* paths)
{
    char* procpath = proc_get_path(pid, NULL);
    if(!procpath) return paths;

    char procname[PATH_MAX]={0};
    NSLog(@"[%d, %s] Allowed locked file paths: %@", pid, basename_r(procpath, procname), paths);

    if(strncmp(rootfs(procpath), "/rootfs/", sizeof("/rootfs/")-1) == 0)
        return paths; // not a jailbroken app

    NSMutableSet* result = [NSMutableSet new];

    for (NSString* path in paths)
    {
        NSString* newPath = path;
        
        if([rootfs(path) hasPrefix:@"/rootfs/"]) {
            //redirect to jbroot
            newPath = jbroot(path);
        }

        // r^x filesystem path fix
        char real_path[PATH_MAX]={0};
        if(realpath(newPath.fileSystemRepresentation, real_path))
            [result addObject:@(real_path).stringByStandardizingPath];
    }

    NSLog(@"[%d, %s] Modified allowed locked file paths: %@", pid, basename_r(procpath, procname), result);

    return result;
}

%group ios15
%hookf(NSSet<NSString*>*, __RBProcess__lock_allowedLockedFilePaths_, RBProcess* process)
{
    NSSet* result = %orig;
    
    if(!result) return result;

    pid_t pid = [process rbs_pid];
    if(pid <= 0) return result;

    return fixAllowedPaths(pid, result);
}
%end // group ios15

%group ios16up
%hookf(NSSet<NSString*>*, __RBProcess__allowedLockedFilePaths_, RBProcess* process)
{
    NSSet* result = %orig;
    
    if(!result) return result;

    pid_t pid = [process rbs_pid];
    if(pid <= 0) return result;

    return fixAllowedPaths(pid, result);
}
%end //group ios16up

void rbdInit()
{
	NSLog(@"rbdInit...");
    MSImageRef RunningBoardImage = MSGetImageByName("/System/Library/PrivateFrameworks/RunningBoard.framework/RunningBoard");
    if(@available(iOS 16.0, *)) {
        %init(ios16up, __RBProcess__allowedLockedFilePaths_ = MSFindSymbol(RunningBoardImage, "-[RBProcess _allowedLockedFilePaths]"));
    } else {
        %init(ios15, __RBProcess__lock_allowedLockedFilePaths_ = MSFindSymbol(RunningBoardImage, "-[RBProcess _lock_allowedLockedFilePaths]"));
    }
}
