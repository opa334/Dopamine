#import "boot_info.h"
#import "handoff.h"
#import "jailbreakd.h"
#import "pplrw.h"
#import "pte.h"
#import "kcall.h"
#import "util.h"

//#define DEBUG_LOGS 1

#ifdef DEBUG_LOGS
#define JBLogDebug(args ...) NSLog(args)
#else
#define JBLogDebug(args ...)
#endif
