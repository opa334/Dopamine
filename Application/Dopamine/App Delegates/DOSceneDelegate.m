//
//  SceneDelegate.m
//  Dopamine
//
//  Created by Lars Fröder on 23.09.23.
//

#import "DOSceneDelegate.h"
#import "DONavigationController.h"
#import "DOEnvironmentManager.h"
#import <dlfcn.h>

@interface DOSceneDelegate ()
@property (nonatomic, strong) NSSet<UIOpenURLContext *> *pendingURLContexts;
@end

@implementation DOSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    window.rootViewController = [[DONavigationController alloc] init];
    [window makeKeyAndVisible];
    self.window = window;

    // Do not handle a cold-launch URL here: the process is still starting up and touching the
    // jailbreak environment this early can panic the device. Defer it until the scene is active.
    if (connectionOptions.URLContexts.count > 0) {
        self.pendingURLContexts = connectionOptions.URLContexts;
    }
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    [self handleURLContexts:URLContexts];
}

- (void)handleURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    for (UIOpenURLContext *context in URLContexts) {
        [self handleURL:context.URL];
    }
}

static dispatch_queue_t DOJailbreakHideQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.opa334.Dopamine.hide", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

// exposes "hide Jailbreak" / "unhide Jailbreak" for shortcuts app so it can be automated
- (void)handleURL:(NSURL *)url {
    if (![url.scheme isEqualToString:@"dopamine"]) return;

    NSString *action = url.host.lowercaseString;
    BOOL wantsHide;
    if ([action isEqualToString:@"hide"]) {
        wantsHide = YES;
    }
    else if ([action isEqualToString:@"unhide"]) {
        wantsHide = NO;
    }
    else if ([action isEqualToString:@"toggle"]) {
        wantsHide = ![[DOEnvironmentManager sharedManager] isJailbreakHidden];
    }
    else {
        return;
    }

    // optional ?then=<bundle id or app name> after hiding, cold launch that app
    NSString *thenBundleID = nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"then"]) {
            thenBundleID = item.value;
            break;
        }
    }

    UIApplication *app = [UIApplication sharedApplication];

    __block UIBackgroundTaskIdentifier bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
        [app endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];

    dispatch_async(DOJailbreakHideQueue(), ^{
        DOEnvironmentManager *envManager = [DOEnvironmentManager sharedManager];
        if (envManager.isJailbreakHidden != wantsHide) {
            [envManager setJailbreakHidden:wantsHide];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (wantsHide) {
                if (thenBundleID.length > 0) {
                    [self launchAppForIdentifierOrName:thenBundleID];
                }
            }
            else {
                // restoring jailbreak unhide function
                SEL suspendSel = NSSelectorFromString(@"suspend");
                if ([app respondsToSelector:suspendSel]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [app performSelector:suspendSel];
                    #pragma clang diagnostic pop
                }
            }
            if (bgTask != UIBackgroundTaskInvalid) {
                [app endBackgroundTask:bgTask];
                bgTask = UIBackgroundTaskInvalid;
            }
        });
    });
}

// launch an app by bundle id or app name
- (void)launchAppForIdentifierOrName:(NSString *)identifierOrName
{
    NSString *bundleID = [self resolvedBundleIDForIdentifierOrName:identifierOrName];

    void *sbServices = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY);
    int (*launchWithID)(CFStringRef, Boolean) = sbServices ? dlsym(sbServices, "SBSLaunchApplicationWithIdentifier") : NULL;
    int (*launchWithOptions)(CFStringRef, CFDictionaryRef, Boolean) = sbServices ? dlsym(sbServices, "SBSLaunchApplicationWithIdentifierAndLaunchOptions") : NULL;

    if (launchWithID && launchWithID((__bridge CFStringRef)bundleID, false) == 0) return;
    if (launchWithOptions && launchWithOptions((__bridge CFStringRef)bundleID, NULL, false) == 0) return;

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
    SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id workspace = [workspaceClass respondsToSelector:defaultSel] ? [workspaceClass performSelector:defaultSel] : nil;
    if ([workspace respondsToSelector:openSel]) {
        [workspace performSelector:openSel withObject:bundleID];
    }
    #pragma clang diagnostic pop
}

// accept either an exact bundle id or app name in ?then= arg.
// underscores are treated as spaces so app names can be typed without spaces (e.g. Clash_of_Clans).
- (NSString *)resolvedBundleIDForIdentifierOrName:(NSString *)identifierOrName
{
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
    SEL allSel = NSSelectorFromString(@"allInstalledApplications");
    if (![workspaceClass respondsToSelector:defaultSel]) return identifierOrName;

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id workspace = [workspaceClass performSelector:defaultSel];
    NSArray *apps = [workspace respondsToSelector:allSel] ? [workspace performSelector:allSel] : nil;
    #pragma clang diagnostic pop

    NSString *nameQuery = [identifierOrName stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    NSString *nameMatch = nil;
    for (id proxy in apps) {
        NSString *bundleID = [proxy valueForKey:@"applicationIdentifier"];
        if ([bundleID isEqualToString:identifierOrName]) {
            return bundleID;
        }
        if (!nameMatch) {
            NSString *localizedName = [proxy valueForKey:@"localizedName"];
            if ([localizedName caseInsensitiveCompare:identifierOrName] == NSOrderedSame ||
                [localizedName caseInsensitiveCompare:nameQuery] == NSOrderedSame) {
                nameMatch = bundleID;
            }
        }
    }
    return nameMatch ?: identifierOrName;
}

+ (void)relaunch
{
    UIWindowScene *windowScene = (UIWindowScene *)[[[UIApplication sharedApplication] connectedScenes] anyObject];
    DOSceneDelegate *instance = (DOSceneDelegate *)windowScene.delegate;

    [UIView animateWithDuration:0.3 animations:^{
        instance.window.alpha = 0;
    } completion:^(BOOL finished) {
        UIWindow *window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)instance.window.windowScene];
        window.rootViewController = [[DONavigationController alloc] init];
        [window makeKeyAndVisible];
        instance.window = window;
        instance.window.alpha = 0;
        [UIView animateWithDuration:0.3 animations:^{
            instance.window.alpha = 1;
        }];
    }];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    // Called as the scene is being released by the system.
    // This occurs shortly after the scene enters the background, or when its session is discarded.
    // Release any resources associated with this scene that can be re-created the next time the scene connects.
    // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
}


- (void)sceneDidBecomeActive:(UIScene *)scene {
    // Handle a URL that cold-launched the app now that startup has finished. A short extra delay
    // gives the jailbreak environment a moment to settle before we touch it.
    NSSet<UIOpenURLContext *> *pending = self.pendingURLContexts;
    if (pending.count > 0) {
        self.pendingURLContexts = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self handleURLContexts:pending];
        });
    }
}


- (void)sceneWillResignActive:(UIScene *)scene {
    // Called when the scene will move from an active state to an inactive state.
    // This may occur due to temporary interruptions (ex. an incoming phone call).
}


- (void)sceneWillEnterForeground:(UIScene *)scene {
    // Called as the scene transitions from the background to the foreground.
    // Use this method to undo the changes made on entering the background.
}


- (void)sceneDidEnterBackground:(UIScene *)scene {
    // Called as the scene transitions from the foreground to the background.
    // Use this method to save data, release shared resources, and store enough scene-specific state information
    // to restore the scene back to its current state.
}


@end
