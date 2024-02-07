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

- (BOOL) isUpdateAvailable {
    NSArray *releases = [self getLatestReleases];
    if (releases.count == 0)
        return NO;
    
    NSString *latestVersion = releases[0][@"tag_name"];
    NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return ![latestVersion isEqualToString:currentVersion];
}

- (NSArray *)getLatestReleases {
    static dispatch_once_t onceToken;
    static NSArray *releases;
    dispatch_once(&onceToken, ^{
        NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/opa334/Dopamine/releases"];
        NSData *data = [NSData dataWithContentsOfURL:url];
        releases = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
    });
    return releases;
}


-(NSArray*)availablePackageManagers {
    return @[kSileoPackageManager, kZebraPackageManager];
}

-(BOOL)isDebug {
    NSNumber *debug = [self.userDefaults valueForKey:@"debug"];
    return debug == nil ? NO : [debug boolValue];
}

-(BOOL)enableTweaks {
    NSNumber *tweaks = [self.userDefaults valueForKey:@"tweaks"];
    return tweaks == nil ? YES : [tweaks boolValue];
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
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int stdout_pipe[2];
        int stdout_orig[2];
        if (pipe(stdout_pipe) != 0 || pipe(stdout_orig) != 0) {
            return;
        }

        dup2(STDOUT_FILENO, stdout_orig[1]);
        close(stdout_orig[0]);
        
        dup2(stdout_pipe[1], STDOUT_FILENO);
        close(stdout_pipe[1]);
        
        char buffer[1024];
        char line[1024];
        int line_index = 0;
        ssize_t bytes_read;

        while ((bytes_read = read(stdout_pipe[0], buffer, sizeof(buffer) - 1)) > 0) {
            @autoreleasepool {
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
                write(stdout_orig[1], buffer, bytes_read);
            }
        }
        close(stdout_pipe[0]);
    });
}

@end
