//
//  DOUIManager.m
//  Dopamine
//
//  Created by tomt000 on 24/01/2024.
//

#import "DOUIManager.h"
#import <pthread.h>

@implementation DOUIManager

+ (id)sharedInstance
{
    static DOUIManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DOUIManager alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    if (self = [super init]){
        _preferenceManager = [DOPreferenceManager sharedManager];
        _logRecord = [NSMutableArray new];
    }
    return self;
}

- (BOOL)isUpdateAvailable
{
    NSArray *releases = [self getLatestReleases];
    if (releases.count == 0)
        return NO;
    
    NSString *latestVersion = releases[0][@"tag_name"];
    NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return ![latestVersion isEqualToString:currentVersion];
}

- (NSArray *)getLatestReleases
{
    static dispatch_once_t onceToken;
    static NSArray *releases;
    dispatch_once(&onceToken, ^{
        NSURL *url = [NSURL URLWithString:@"https://api.github.com/repos/opa334/Dopamine/releases"];
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (data) {
            NSError *error;
            releases = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
            if (error)
            {
                onceToken = 0;
                releases = @[];
            }
        }
    });
    return releases;
}


- (NSArray*)availablePackageManagers
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"PkgManagers" ofType:@"plist"];
    return [NSArray arrayWithContentsOfFile:path];
}

- (NSArray*)enabledPackageManagerKeys
{
    return [_preferenceManager preferenceValueForKey:@"enabledPkgManagers"] ?: @[];
}

- (NSArray*)enabledPackageManagers
{
    NSMutableArray *enabledPkgManagers = [NSMutableArray new];
    NSArray *enabledKeys = [self enabledPackageManagerKeys];

    [[self availablePackageManagers] enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *key = obj[@"Key"];
        if ([enabledKeys containsObject:key]) {
            [enabledPkgManagers addObject:obj];
        }
    }];

    return enabledPkgManagers;
}

- (void)resetPackageManagers
{
    [_preferenceManager removePreferenceValueForKey:@"enabledPkgManagers"];
}

- (void)resetSettings
{
    [_preferenceManager removePreferenceValueForKey:@"verboseLogsEnabled"];
    [_preferenceManager removePreferenceValueForKey:@"tweakInjectionEnabled"];
    [self resetPackageManagers];
}

- (void)setPackageManager:(NSString*)key enabled:(BOOL)enabled
{
    NSMutableArray *pkgManagers = [self enabledPackageManagerKeys].mutableCopy;
    
    if (enabled && ![pkgManagers containsObject:key]) {
        [pkgManagers addObject:key];
    }
    else if (!enabled && [pkgManagers containsObject:key]) {
        [pkgManagers removeObject:key];
    }

    [_preferenceManager setPreferenceValue:pkgManagers forKey:@"enabledPkgManagers"];
}

- (BOOL)isDebug
{
    NSNumber *debug = [_preferenceManager preferenceValueForKey:@"verboseLogsEnabled"];
    return debug == nil ? NO : [debug boolValue];
}

- (BOOL)enableTweaks
{
    NSNumber *tweaks = [_preferenceManager preferenceValueForKey:@"tweakInjectionEnabled"];
    return tweaks == nil ? YES : [tweaks boolValue];
}

- (void)sendLog:(NSString*)log debug:(BOOL)debug update:(BOOL)update
{
    if (!self.logView)
        return;
    
    BOOL isDebug = self.logView.class == DODebugLogView.class;
    if (debug && !isDebug)
        return;
    
    if (update) {
        if ([self.logView respondsToSelector:@selector(updateLog:)]) {
            [self.logView updateLog:log];
        }
    }
    else {
        [self.logView showLog:log];
    }
}

- (void)sendLog:(NSString*)log debug:(BOOL)debug
{
    [self sendLog:log debug:debug update:NO];
}

- (void)shareLogRecord
{
    if (self.logRecord.count == 0)
        return;

    NSString *log = [self.logRecord componentsJoinedByString:@"\n"];
    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[log] applicationActivities:nil];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:activityViewController animated:YES completion:nil];
}

- (void)completeJailbreak
{
    if (!self.logView)
        return;

    [self.logView didComplete];
}

- (void)startLogCapture
{
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
                        NSString *str = [NSString stringWithUTF8String:line];
                        [[DOUIManager sharedInstance] sendLog:str debug:YES];
                        [self.logRecord addObject:str];
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
