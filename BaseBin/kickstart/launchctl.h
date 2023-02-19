#import <Foundation/Foundation.h>

#ifndef launchctl_h
#define launchctl_h

#if defined(__cplusplus)
extern "C" {
#endif

extern int64_t launchctlLoad(const char* plistPath);

#if defined(__cplusplus)
}
#endif

#endif /* launchctl_h */