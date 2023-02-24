#import "libjailbreak.h"
#import <xpc/xpc.h>
//#import "ppl.h"

xpc_connection_t getJBDConnection(void)
{
	xpc_connection_t xpcConnection = xpc_connection_create_mach_service("com.opa334.jailbreakd", NULL, XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
	xpc_connection_set_event_handler(xpcConnection, ^(xpc_object_t object){});
	xpc_connection_resume(xpcConnection);

	return xpcConnection;
}

void jbdUnrestrictCodeSigning(pid_t pid)
{
	xpc_connection_t jdbConnection = getJBDConnection();

	xpc_object_t message = xpc_dictionary_create(NULL,NULL,0);
	xpc_dictionary_set_string(message, "action", "unrestrict-cs");
	xpc_dictionary_set_uint64(message, "pid", pid);

	xpc_connection_send_message_with_reply_sync(jdbConnection, message);
}

uint64_t jbdInitPPLRemote(pid_t pid)
{
	xpc_connection_t jdbConnection = getJBDConnection();

	xpc_object_t message = xpc_dictionary_create(NULL,NULL,0);
	xpc_dictionary_set_string(message, "action", "handoff-ppl-pid");
	xpc_dictionary_set_uint64(message, "pid", pid);

	xpc_object_t reply = xpc_connection_send_message_with_reply_sync(jdbConnection, message);
	int64_t errorCode = xpc_dictionary_get_int64(reply, "error-code");
	uint64_t magicPage = xpc_dictionary_get_uint64(reply, "magic-page");
	return magicPage;
}

/*uint64_t jbdInitPPL(void)
{
	xpc_connection_t jdbConnection = getJBDConnection();

	xpc_object_t message = xpc_dictionary_create(NULL,NULL,0);
	xpc_dictionary_set_string(message, "action", "handoff-ppl");

	xpc_object_t reply = xpc_connection_send_message_with_reply_sync(jdbConnection, message);
	int64_t errorCode = xpc_dictionary_get_int64(reply, "error-code");
	uint64_t magicPage = xpc_dictionary_get_uint64(reply, "magic-page");

	if (errorCode != 0) {
		NSLog(@"Error %lld occured while trying to obtain PPL R/W", errorCode);
		return 0;
	}
	else
	{
		return magicPage;
	}
}

uint64_t jbdKcall(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8)
{
	xpc_connection_t jdbConnection = getJBDConnection();

	xpc_object_t message = xpc_dictionary_create(NULL,NULL,0);
	xpc_dictionary_set_string(message, "action", "kcall");
	xpc_dictionary_set_uint64(message, "func", func);
	xpc_dictionary_set_uint64(message, "a1", a1);
	xpc_dictionary_set_uint64(message, "a2", a2);
	xpc_dictionary_set_uint64(message, "a3", a3);
	xpc_dictionary_set_uint64(message, "a4", a4);
	xpc_dictionary_set_uint64(message, "a5", a5);
	xpc_dictionary_set_uint64(message, "a6", a6);
	xpc_dictionary_set_uint64(message, "a7", a7);
	xpc_dictionary_set_uint64(message, "a8", a8);

	xpc_object_t reply = xpc_connection_send_message_with_reply_sync(jdbConnection, message);
	return xpc_dictionary_get_uint64(reply, "ret");
}*/

