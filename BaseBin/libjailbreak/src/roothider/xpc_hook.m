#import <Foundation/Foundation.h>

#include <errno.h>
#include <libgen.h>
#include <sandbox.h>
#include <libproc.h>
#include <xpc/xpc.h>
#include <sys/proc.h>
#include <sys/proc_info.h>

#include "../libjailbreak.h"
#include "../codesign.h"
#include "common.h"
#include "log.h"

xpc_object_t (*orig_xpc_dictionary_create_reply)(xpc_object_t original);
xpc_object_t new_xpc_dictionary_create_reply(xpc_object_t original)
{
	xpc_object_t reply = orig_xpc_dictionary_create_reply(original);
	if (reply) // only return success if original is a XPC_TYPE_DICTIONARY
	{
		audit_token_t clientToken = {0};
		xpc_dictionary_get_audit_token(original, &clientToken);

		if (isBlacklistedToken(&clientToken))
		{
			xpc_dictionary_set_value(reply, "roothide-blacklisted-process-request", original);
		}
	}

	return reply;
}

int (*orig_xpc_pipe_routine_reply)(xpc_object_t reply);
int new_xpc_pipe_routine_reply(xpc_object_t reply)
{
	if (xpc_get_type(reply) == XPC_TYPE_DICTIONARY)
	{
		xpc_object_t original = xpc_dictionary_get_value(reply, "roothide-blacklisted-process-request");
		if (original)
		{
			xpc_dictionary_set_value(reply, "roothide-blacklisted-process-request", NULL);

			audit_token_t clientToken = {0};
			xpc_dictionary_get_audit_token(original, &clientToken);

			uint64_t routine = xpc_dictionary_get_uint64(original, "routine");
			uint64_t subsystem = xpc_dictionary_get_uint64(original, "subsystem");

			/*
			if(subsystem==2 && routine==708)
			{
				volatile const char* name = xpc_dictionary_get_string(original, "name");

				volatile int error = xpc_dictionary_get_int64(reply, "error");

				if(error == 1)
				{
					xpc_dictionary_set_int64(reply, "error", 113);
				}
			}
			else if(subsystem==6 && routine==301)
			{
				volatile int pid = xpc_dictionary_get_int64(original, "pid");
				volatile uint64_t outgsk = xpc_dictionary_get_uint64(original, "outgsk");

				volatile int error = xpc_dictionary_get_int64(reply, "error");
				volatile xpc_object_t out = xpc_dictionary_get_value(reply, "out");

				//fake WebContent Instance

				switch(outgsk)
				{
					case 11:
					{
						if(error==0 && out && xpc_get_type(out)==XPC_TYPE_DICTIONARY)
						{
							xpc_dictionary_set_value(out,
						}
					}
					break;

					default:
					break;
				}
			}
			else //*/
			if (subsystem == 3 && routine == 829)
			{
				volatile int error = xpc_dictionary_get_int64(reply, "error");
				volatile const char *name = xpc_dictionary_get_string(reply, "name");
				volatile const char *bundle_identifier = xpc_dictionary_get_string(reply, "bundle_identifier");

				volatile const char *bundle = bundle_identifier ? bundle_identifier : (name ? name : "");

				volatile char client_identifier[255] = {0};
				proc_get_identifier(audit_token_to_pid(clientToken), client_identifier);

				volatile bool isSafeBundleIdentifier = is_safe_bundle_identifier(bundle);
				volatile bool isSelfBundleIdentifier = client_identifier[0] && string_has_prefix(bundle, client_identifier);

				if (error==0 && !isSelfBundleIdentifier && !isSafeBundleIdentifier)
				{
					JBLogDebug("hide coalition (%s) (%s) from blacklisted process(%d) %s", name, bundle_identifier, audit_token_to_pid(clientToken), proc_get_path(audit_token_to_pid(clientToken), NULL));

					xpc_dictionary_set_value(reply, "cid", NULL);
					xpc_dictionary_set_value(reply, "name", NULL);
					xpc_dictionary_set_value(reply, "bundle_identifier", NULL);
					xpc_dictionary_set_value(reply, "resource-usage-blob", NULL);

					xpc_dictionary_set_int64(reply, "error", 3);
				}
			}
		}
	}

	return orig_xpc_pipe_routine_reply(reply);
}

#define RB2_USERREBOOT (0x2000000000000000llu)
void check_usreboot_msg(xpc_object_t xmsg)
{
	if (xpc_dictionary_get_uint64(xmsg, "flags") != RB2_USERREBOOT)
	{
		return;
	}
	if (xpc_dictionary_get_uint64(xmsg, "type") != 1)
	{
		return;
	}
	if (!xpc_dictionary_get_value(xmsg, "handle") || xpc_dictionary_get_uint64(xmsg, "handle") != 0)
	{
		return;
	}

	if (getpid() != 1)
	{
		JBLogError("usereboot message not from launchd?");
		return;
	}

	audit_token_t clientToken = {0};
	xpc_dictionary_get_audit_token(xmsg, &clientToken);

	uint32_t csflags = 0;
	csops(audit_token_to_pid(clientToken), CS_OPS_STATUS, &csflags, sizeof(csflags));

	if ((csflags & CS_PLATFORM_BINARY) == 0)
	{
		JBLogError("usereboot message not from platform process?");
		return;
	}

	struct statfs fsb = {0};
	if (statfs("/Developer", &fsb) != 0)
	{
		JBLogError("unable to statfs /Developer, already broken?");
		return;
	}

	if (strcmp(fsb.f_mntonname, "/Developer") != 0)
	{
		JBLogDebug("/Developer not mounted. skip");
		return;
	}

	// fix Xcode debugging being broken after the userspace reboot
	// for iOS15 it is too late by the time launchd re-execs itself

	int retval = unmount("/Developer", MNT_FORCE);

	if (retval != 0)
	{
		JBLogError("unmount /Developer : %d %d,%s", retval, errno, strerror(errno));
	}
}

void roothide_handle_xpc_msg(xpc_object_t xmsg)
{
	check_usreboot_msg(xmsg);

	audit_token_t clientToken = {0};
	xpc_dictionary_get_audit_token(xmsg, &clientToken);

#ifdef ENABLE_LOGS
	if (xpc_dictionary_get_value(xmsg, "jb-domain") && xpc_dictionary_get_value(xmsg, "action"))
	{
		const char *desc = NULL;
		JBLogDebug("jbserver received xpc message from (%d) %s :\n%s",
				   audit_token_to_pid(clientToken),
				   proc_get_path(audit_token_to_pid(clientToken), NULL),
				   (desc = xpc_copy_description(xmsg)));
		if (desc) free((void *)desc);
	}
#endif

	if (isBlacklistedToken(&clientToken))
	{
		uint64_t routine = xpc_dictionary_get_uint64(xmsg, "routine");
		uint64_t subsystem = xpc_dictionary_get_uint64(xmsg, "subsystem");
		if (subsystem == 2 && routine == 708)
		{
			volatile char *bundle = NULL;
			volatile const char *name = xpc_dictionary_get_string(xmsg, "name");
			if (name) {
				if (string_has_prefix(name, "UIKitApplication:")) {
					bundle = name + sizeof("UIKitApplication:") - 1;
					char *end = strchr(bundle, '[');
					if (end) {
						asprintf(&bundle, "%.*s", (int)(end - bundle), bundle);
					} else {
						bundle = strdup(bundle);
					}
				} else {
					bundle = strdup(name);
				}
			} else {
				bundle = strdup("");
			}

			volatile int clientPid = audit_token_to_pid(clientToken);

			volatile char client_identifier[255] = {0};
			proc_get_identifier(clientPid, client_identifier);

			volatile bool isSafeBundleIdentifier = is_safe_bundle_identifier(bundle);
			volatile bool isSelfBundleIdentifier = client_identifier[0] && string_has_prefix(bundle, client_identifier);

			if (name && !isSelfBundleIdentifier && !isSafeBundleIdentifier)
			{
				JBLogDebug("hide job (%s) (%s) from blacklisted process(%d) %s", name, bundle, clientPid, proc_get_path(clientPid, NULL));
				xpc_dictionary_set_string(xmsg, "name", "");
			}

			free((void *)bundle);
		}
		else if (subsystem == 6 && routine == 301)
		{
			volatile int pid = xpc_dictionary_get_int64(xmsg, "pid");
			volatile int clientPid = audit_token_to_pid(clientToken);

			volatile char path[PATH_MAX] = {0};
			proc_get_path(pid, path);

			volatile char proc_identifier[255] = {0};
			proc_get_identifier(pid, proc_identifier);

			volatile char client_identifier[255] = {0};
			proc_get_identifier(clientPid, client_identifier);

			volatile bool isJailbrokenPath = !path[0] || hasTrollstoreMarker(path) || isSubPathOf(path, JBROOT_PATH("/"));
			volatile bool isSafeBundleIdentifier = proc_identifier[0] && is_safe_bundle_identifier(proc_identifier);
			volatile bool isSelfBundleIdentifier = proc_identifier[0] && client_identifier[0] && string_has_prefix(proc_identifier, client_identifier);

			if (pid > 0 && pid != clientPid && (isJailbrokenPath || (!isSafeBundleIdentifier && !isSelfBundleIdentifier)))
			{
				JBLogDebug("hide pid %d (%s) from blacklisted process(%d) %s", pid, path, clientPid, proc_get_path(clientPid, NULL));
				xpc_dictionary_set_int64(xmsg, "pid", INT_MAX);
			}
		}
	}
}
