#include <mach-o/dyld.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <dispatch/dispatch.h>

bool debugLogsEnabled = false;
bool errorLogsEnabled = false;
#define LOGGING_PATH "/var/log/"

const char *JBLogGetProcessName(void)
{
	static char *processName = NULL;
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		uint32_t length = 0;
		_NSGetExecutablePath(NULL, &length);
		char *buf = malloc(length);
		_NSGetExecutablePath(buf, &length);

		char delim[] = "/";
		char *last = NULL;
		char *ptr = strtok(buf, delim);
		while(ptr != NULL)
		{
			last = ptr;
			ptr = strtok(NULL, delim);
		}
		processName = strdup(last);
		free(buf);
	});
	return processName;
}


void JBDLogV(const char* prefix, const char *format, va_list va)
{
	static char *logFilePath = NULL;
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		const char *processName = JBLogGetProcessName();

		time_t t = time(NULL);
		struct tm *tm = localtime(&t);
		char timestamp[20];
		strftime(timestamp, sizeof(timestamp), "%Y-%m-%d_%H-%M-%S", tm);

		logFilePath = malloc(strlen(LOGGING_PATH) + strlen(processName) + strlen(timestamp) + 6);
		strcpy(logFilePath, LOGGING_PATH);
		strcat(logFilePath, processName);
		strcat(logFilePath, "-");
		strcat(logFilePath, timestamp);
		strcat(logFilePath, ".log");
	});

	FILE *logFile = fopen(logFilePath, "a");
	if (logFile) {
		time_t ltime;
		struct tm result;
		char stime[32];
		ltime = time(NULL);
		localtime_r(&ltime, &result);
		asctime_r(&result, stime);
		stime[24] = 0;

		fprintf(logFile, "[%s] [%s] ", stime, prefix);
		vfprintf(logFile, format, va);
		fprintf(logFile, "\n");

		fflush(logFile);
		fclose(logFile);
	}
}

void JBLogDebug(const char *format, ...)
{
	if (!debugLogsEnabled) return;
	va_list va;
	va_start(va, format);
	JBDLogV("DEBUG", format, va);
	va_end(va);	
}

void JBLogError(const char *format, ...)
{
	if (!errorLogsEnabled) return;
	va_list va;
	va_start(va, format);
	JBDLogV("ERROR", format, va);
	va_end(va);	
}