//
//  DOUIManager.m
//  Dopamine
//
//  Created by tomt000 on 24/01/2024.
//

#import "DOUIManager.h"
#import <pthread.h>

@implementation DOUIManager

+(id)sharedInstance {
    static DOUIManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DOUIManager alloc] init];
    });
    return sharedInstance;
}

-(id)init {
    if (self = [super init]){
        self.userDefaults = [NSUserDefaults standardUserDefaults];
    }
    return self;
}

-(NSArray*)availablePackageManagers {
    return @[kSileoPackageManager, kZebraPackageManager];
}

-(BOOL)isDebug {
    BOOL debug = [self.userDefaults boolForKey:@"debug"];
    return debug == nil ? NO : debug;
}

-(BOOL)enableTweaks {
    BOOL tweaks = [self.userDefaults boolForKey:@"tweaks"];
    return tweaks == nil ? YES : tweaks;
}

-(void)sendLog:(NSString*)log debug:(BOOL)debug {
    if (!self.logView)
        return;
    
    BOOL isDebug = self.logView.class == DODebugLogView.class;
    if (debug && !isDebug)
        return;

    [self.logView showLog:log];
}

-(void)completeJailbreak {
    if (!self.logView)
        return;

    [self.logView didComplete];
}

-(void)startLogCapture {
    int stdout_pipe[2];
    if (pipe(stdout_pipe) != 0) {
        return;
    }

    dup2(stdout_pipe[1], STDOUT_FILENO);
    close(stdout_pipe[1]);
    int fd = stdout_pipe[0];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char buffer[1024];
        char line[1024];
        int line_index = 0;
        ssize_t bytes_read;

        while ((bytes_read = read(fd, buffer, sizeof(buffer) - 1)) > 0) {
            buffer[bytes_read] = '\0'; // Null terminate to handle as string
            for (int i = 0; i < bytes_read; ++i) {
                if (buffer[i] == '\n') {
                    line[line_index] = '\0';
                    [[DOUIManager sharedInstance] sendLog:[NSString stringWithUTF8String:line] debug:YES];
                    line_index = 0;
                } else {
                    if (line_index < sizeof(line) - 1) {
                        line[line_index++] = buffer[i];
                    }
                }
            }
            // Tee: Write back to the original standard output
            write(STDOUT_FILENO, buffer, bytes_read);
        }
        close(fd);
    });
}

@end
