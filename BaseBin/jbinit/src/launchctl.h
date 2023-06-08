#import <Foundation/Foundation.h>

#ifndef launchctl_h
#define launchctl_h

#if defined(__cplusplus)
extern "C" {
#endif

extern int64_t launchctl_load(const char* plistPath, bool unload);

#if defined(__cplusplus)
}
#endif

#endif /* launchctl_h */