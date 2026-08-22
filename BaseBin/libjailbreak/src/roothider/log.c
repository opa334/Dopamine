#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <sys/time.h>
#include <mach-o/dyld.h>
#include <sys/syslimits.h>
#include <dispatch/dispatch.h>
#include "log.h"

#ifdef ENABLE_LOGS

bool debugLogsEnabled = true;
bool errorLogsEnabled = true;

#define LOGGING_DIR "/var/log"

const char *JBLogGetProcessName(void) {
    static char *processName = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uint32_t length = 0;
        _NSGetExecutablePath(NULL, &length);
        char *buf = malloc(length);
        _NSGetExecutablePath(buf, &length);

        char delim[] = "/";
        char *last = NULL;
        char *ptr = strtok(buf, delim);
        while (ptr != NULL) {
            last = ptr;
            ptr = strtok(NULL, delim);
        }
        processName = strdup(last);
        free(buf);
    });
    return processName;
}

char* JBLogGetLogFilePath(const char* logname, const char* suffix, char buffer[PATH_MAX])
{
    static char __thread logFilePath[PATH_MAX] = {0};
    if(!buffer) buffer = logFilePath;

    //struct tm *tm = localtime(&t); //xpc dead loop

    struct timeval t={0};
    gettimeofday(&t, NULL);

    snprintf(buffer, PATH_MAX, "%s/%s-%lu.%d-%d%s.log", LOGGING_DIR, logname, t.tv_sec, t.tv_usec, getpid(), suffix ? suffix : "");

    return buffer;
}

const char* JBLogGetDefaultLogFilePath()
{
    static char logFilePath[PATH_MAX] = {0};

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        JBLogGetLogFilePath(JBLogGetProcessName(), NULL, logFilePath);
    });
    return logFilePath;
}

void JBDLogV(const char* path, pid_t pid, uint64_t tid, const char *prefix, const char *format, va_list va) {

    FILE *logFile = fopen(path, "a");
    if (logFile) {
        fprintf(logFile, "[%lu] [%u] [%lld] [%s] ", time(NULL), pid, tid, prefix);
        vfprintf(logFile, format, va);
        fprintf(logFile, "\n");

        fflush(logFile);
        fsync(fileno(logFile));
#if JBLOG_FULL_SYNC==1
        fcntl(fileno(logFile), F_FULLFSYNC); //slow
#endif
        fclose(logFile);

        //sync(); //super slow
    }
}

bool JBLogEnabled(void) {
    static bool enabled = false;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        enabled = access("/var/.JBLogEnabled", F_OK) == 0;
    });
    return enabled;
}

void JBLogFunction(const char* path, pid_t pid, uint64_t tid, const char* prefix, const char *format, ...)
{
    va_list va;
    va_start(va, format);
    JBDLogV(path, pid, tid, prefix, format, va);
    va_end(va);
}

void JBLogDebugFunction(const char *format, ...) {
    if (!debugLogsEnabled) return;
    va_list va;
    va_start(va, format);

    __uint64_t tid = 0;
    pthread_threadid_np(pthread_self(), &tid);

    JBDLogV(JBLogGetDefaultLogFilePath(), getpid(), tid, "DEBUG", format, va);

    va_end(va);
}

void JBLogErrorFunction(const char *format, ...) {
    if (!errorLogsEnabled) return;
    va_list va;
    va_start(va, format);

    __uint64_t tid = 0;
    pthread_threadid_np(pthread_self(), &tid);

    JBDLogV(JBLogGetDefaultLogFilePath(), getpid(), tid, "ERROR", format, va);
	
    static char errorLogFilePath[PATH_MAX] = {0};

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        JBLogGetLogFilePath(JBLogGetProcessName(), "-error", errorLogFilePath);
    });
	
    JBDLogV(errorLogFilePath, getpid(), tid, "ERROR", format, va);
    
    va_end(va);
}

#endif // ENABLE_LOGS