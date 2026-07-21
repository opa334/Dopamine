#ifndef __LDH_ASL_H
#define __LDH_ASL_H

#include <os/once_private.h>

struct asl_context {
	bool asl_enabled;
	const char *progname;
	int asl_fd;
#if TARGET_OS_SIMULATOR && !TARGET_OS_MACCATALYST
	const char *sim_log_path;
	os_unfair_lock sim_connect_lock;
#else
	os_once_t connect_once;
#endif
};

#endif