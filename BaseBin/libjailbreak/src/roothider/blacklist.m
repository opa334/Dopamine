#import <Foundation/Foundation.h>

#include "../libjailbreak.h"
#include "common.h"


#define APP_PATH_PREFIX "/private/var/containers/Bundle/Application/"
#define NULL_UUID "00000000-0000-0000-0000-000000000000"

NSString *getAppBundlePathFromSpawnPath(const char *path) {
    if (!path) return nil;

    char abspath[PATH_MAX];
    if (!realpath(path, abspath)) return nil;

    if (strncmp(abspath, APP_PATH_PREFIX, sizeof(APP_PATH_PREFIX) - 1) != 0)
        return nil;

    char *p1 = abspath + sizeof(APP_PATH_PREFIX) - 1;
    char *p2 = strchr(p1, '/');
    if (!p2) return nil;

    //is normal app or jailbroken app/daemon?
    if ((p2 - p1) != (sizeof(NULL_UUID) - 1))
        return nil;

    char *p = strstr(p2, ".app/");
    if (!p) return nil;

    p[sizeof(".app/") - 1] = '\0';

    return [NSString stringWithUTF8String:abspath];
}

// get main bundle identifier of app for (PlugIns's) executable path
NSString *getAppIdentifierFromPath(const char *path) {
    if (!path) return nil;

    NSString *bundlePath = getAppBundlePathFromSpawnPath(path);
    if (!bundlePath) return nil;

    NSDictionary *appInfo = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
    if (!appInfo) return nil;

    NSString *identifier = appInfo[@"CFBundleIdentifier"];
    if (!identifier) return nil;

    return identifier;
}

NSArray* builtinApps = @[
    @"com.opa334.Dopamine-roothide",
];

bool isBlacklistedApp(const char* identifier)
{
    if(!identifier) return false;

    if([builtinApps containsObject:@(identifier)]) return false;

    NSString* configFilePath = JBROOT_PATH(@"/var/mobile/Library/RootHide/RootHideConfig.plist");
    NSDictionary* roothideConfig = [NSDictionary dictionaryWithContentsOfFile:configFilePath];
    if(!roothideConfig) return false;

    NSDictionary* appconfig = roothideConfig[@"appconfig"];
    if(!appconfig) return false;

    NSNumber* blacklisted = appconfig[@(identifier)];
    if(!blacklisted) return false;

    return blacklisted.boolValue;
}

bool isBlacklistedPath(const char* path)
{
    if(!path) return false;
    NSString* identifier = getAppIdentifierFromPath(path);
    if(!identifier) return false;
    return isBlacklistedApp(identifier.UTF8String);
}
