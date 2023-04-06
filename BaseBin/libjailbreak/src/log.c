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

void JBLogDebug(const char *format, ...)
{
	if (!debugLogsEnabled) return;

	static char *debugLogFilePath = NULL;
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		const char *processName = JBLogGetProcessName();
		const char *logSuffix = "-DEBUG.log";

		debugLogFilePath = malloc(strlen(LOGGING_PATH) + strlen(logSuffix) + strlen(processName) + 1);
		strcpy(debugLogFilePath, LOGGING_PATH);
		strcat(debugLogFilePath, processName);
		strcat(debugLogFilePath, logSuffix);
	});
	

	FILE *debugLogFile = fopen(debugLogFilePath, "a");
	if (debugLogFile) {

		time_t ltime;
		struct tm result;
		char stime[32];
		ltime = time(NULL);
		localtime_r(&ltime, &result);
		asctime_r(&result, stime);
		stime[24] = 0;

		fprintf(debugLogFile, "[");
		fprintf(debugLogFile, "%s", stime);
		fprintf(debugLogFile, "] ");

		va_list va;
		va_start(va, format);
		vfprintf(debugLogFile, format, va);
		va_end(va);

		fprintf(debugLogFile, "\n");

		fflush(debugLogFile);
		fclose(debugLogFile);
	}
}

void JBLogError(const char *format, ...)
{
	if (!errorLogsEnabled) return;

	static char *errorLogFilePath = NULL;
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		const char *processName = JBLogGetProcessName();
		const char *logSuffix = "-ERROR.log";

		errorLogFilePath = malloc(strlen(LOGGING_PATH) + strlen(logSuffix) + strlen(processName) + 1);
		strcpy(errorLogFilePath, LOGGING_PATH);
		strcat(errorLogFilePath, processName);
		strcat(errorLogFilePath, logSuffix);
	});
	

	FILE *errorLogFile = fopen(errorLogFilePath, "a");
	if (errorLogFile) {

		time_t ltime;
		struct tm result;
		char stime[32];
		ltime = time(NULL);
		localtime_r(&ltime, &result);
		asctime_r(&result, stime);
		stime[24] = 0;

		fprintf(errorLogFile, "[");
		fprintf(errorLogFile, "%s", stime);
		fprintf(errorLogFile, "] ");

		va_list va;
		va_start(va, format);
		vfprintf(errorLogFile, format, va);
		va_end(va);

		fprintf(errorLogFile, "\n");

		fflush(errorLogFile);
		fclose(errorLogFile);
	}
}