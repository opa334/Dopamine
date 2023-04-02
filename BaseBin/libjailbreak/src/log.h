//#define DEBUG_LOGS 1
//#define ERROR_LOGS 1

#ifdef DEBUG_LOGS
#define JBLogDebug(args ...) NSLog(args)
#define JBLogError(args ...) NSLog(args)
#else
#define JBLogDebug(args ...)
#define JBLogError(args ...)
#endif
