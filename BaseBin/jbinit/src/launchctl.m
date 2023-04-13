#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
#import <libjailbreak/launchd.h>

#define ROUTINE_LOAD 800

int64_t launchctlLoad(const char* plistPath)
{
	xpc_object_t pathArray = xpc_array_create_empty();
	xpc_array_set_string(pathArray, XPC_ARRAY_APPEND, plistPath);
	
	xpc_object_t msgDictionary = xpc_dictionary_create_empty();
	xpc_dictionary_set_uint64(msgDictionary, "subsystem", 3);
	xpc_dictionary_set_uint64(msgDictionary, "handle", 0);
	xpc_dictionary_set_uint64(msgDictionary, "type", 1);
	xpc_dictionary_set_bool(msgDictionary, "legacy-load", true);
	xpc_dictionary_set_bool(msgDictionary, "enable", false);
	xpc_dictionary_set_uint64(msgDictionary, "routine", ROUTINE_LOAD);
	xpc_dictionary_set_value(msgDictionary, "paths", pathArray);
	
	xpc_object_t msgReply = launchd_xpc_send_message(msgDictionary);

	char *msgReplyDescription = xpc_copy_description(msgReply);
	printf("msgReply = %s\n", msgReplyDescription);
	free(msgReplyDescription);
	
	int64_t bootstrapError = xpc_dictionary_get_int64(msgReply, "bootstrap-error");
	if(bootstrapError != 0)
	{
		printf("bootstrap-error = %s\n", xpc_strerror((int32_t)bootstrapError));
		return bootstrapError;
	}
	
	int64_t error = xpc_dictionary_get_int64(msgReply, "error");
	if(error != 0)
	{
		printf("error = %s\n", xpc_strerror((int32_t)error));
		return error;
	}
	
	// launchctl seems to do extra things here
	// like getting the audit token via xpc_dictionary_get_audit_token
	// or sometimes also getting msgReply["req_pid"] and msgReply["rec_execcnt"]
	// but we don't really care about that here

	return 0;
}
