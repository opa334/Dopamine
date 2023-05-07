#import <xpc/xpc.h>
xpc_object_t launchd_xpc_send_message(xpc_object_t xdict);

typedef enum {
	LAUNCHD_JB_MSG_ID_GET_PPLRW,
	LAUNCHD_JB_MSG_ID_SIGN_STATE
} LAUNCHD_JB_MSG;

void patchBaseBinLaunchDaemonPlist(NSString *plistPath);
void patchBaseBinLaunchDaemonPlists(void);