// #define ENABLE_LOGS

#ifdef ENABLE_LOGS
#include <unistd.h>
#include <stdbool.h>
#include <sys/syslimits.h>

#define JBLOG_FULL_SYNC 0
#define JBLOG_FORCE_LOG 1

bool JBLogEnabled();
void JBLogDebugFunction(const char *format, ...);
void JBLogErrorFunction(const char *format, ...);

char* JBLogGetLogFilePath(const char* logname, const char* suffix, char buffer[PATH_MAX]);
void JBLogFunction(const char* path, pid_t pid, uint64_t tid, const char* prefix, const char *format, ...);

#define JBLogDebug(...) do { if(JBLOG_FORCE_LOG || JBLogEnabled()) JBLogDebugFunction(__VA_ARGS__); } while(0)
#define JBLogError(...) do { if(JBLOG_FORCE_LOG || JBLogEnabled()) JBLogErrorFunction(__VA_ARGS__); } while(0)

#else
#define JBLogDebug(...)
#define JBLogError(...)
#endif
