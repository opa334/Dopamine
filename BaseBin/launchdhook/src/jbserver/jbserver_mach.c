#include <libjailbreak/jbserver.h>
#include <mach/mach.h>
#include <bsm/audit.h>
#include <libproc.h>
#include <sys/proc_info.h>
extern int fileport_makefd (mach_port_t port);

int systemwide_process_checkin(audit_token_t *processToken, char **rootPathOut, char **bootUUIDOut, char **sandboxExtensionsOut, bool *fullyDebuggedOut);
int systemwide_fork_fix(audit_token_t *parentToken, uint64_t childPid);
int systemwide_trust_file(audit_token_t *processToken, int rfd, struct siginfo *siginfo, size_t siginfoSize);

bool systemwide_domain_allowed(audit_token_t clientToken);

int jbserver_send_mach_reply(mach_msg_header_t *hdr, void *replyData)
{
	kern_return_t kr = -1;

	if (replyData && MACH_PORT_VALID(hdr->msgh_remote_port) && MACH_MSGH_BITS_REMOTE(hdr->msgh_bits) != 0) {
		struct jbserver_mach_msg_reply *reply = (struct jbserver_mach_msg_reply *)replyData;

		// Send reply
		uint32_t bits = MACH_MSGH_BITS_REMOTE(hdr->msgh_bits);
		if (bits == MACH_MSG_TYPE_COPY_SEND)
			bits = MACH_MSG_TYPE_MOVE_SEND;
		
		reply->msg.hdr.msgh_bits = MACH_MSGH_BITS(bits, 0);
		// size already set
		reply->msg.hdr.msgh_remote_port  = hdr->msgh_remote_port;
		reply->msg.hdr.msgh_local_port   = 0;
		reply->msg.hdr.msgh_voucher_port = 0;
		reply->msg.hdr.msgh_id           = hdr->msgh_id + 100;
		
		kr = mach_msg_send(&reply->msg.hdr);
		if (kr == KERN_SUCCESS /*|| kr == MACH_SEND_INVALID_MEMORY || kr == MACH_SEND_INVALID_RIGHT || kr == MACH_SEND_INVALID_TYPE || kr == MACH_SEND_MSG_TOO_SMALL*/) {
			// All of these imply the message was either sent or destroyed
			// -> Kill the reply port in the original message as we certainly got rid of the associated right
			hdr->msgh_remote_port = 0;
			hdr->msgh_bits = hdr->msgh_bits & ~MACH_MSGH_BITS_REMOTE_MASK;
		}
	}

	return kr;
}

int jbserver_received_mach_message(audit_token_t *auditToken, struct jbserver_mach_msg *jbsMachMsg)
{
	int r = -1;

	// Anything implemented by the mach server is provided systemwide
	// So we also need to honor the allowed handler of the systemwide domain
	if (!systemwide_domain_allowed(*auditToken)) return -1;

	uint64_t msgSize = jbsMachMsg->hdr.msgh_size;
	void *replyData = NULL;

	if (jbsMachMsg->action == JBSERVER_MACH_CHECKIN) {
		if (msgSize < sizeof(struct jbserver_mach_msg_checkin)) return -1;
		struct jbserver_mach_msg_checkin *checkinMsg = (struct jbserver_mach_msg_checkin *)jbsMachMsg;

		size_t replySize = sizeof(struct jbserver_mach_msg_checkin_reply);
		replyData = malloc(replySize);
		struct jbserver_mach_msg_checkin_reply *reply = (struct jbserver_mach_msg_checkin_reply *)replyData;
		memset(reply, 0, replySize);
		
		char *jbRootPath = NULL, *bootUUID = NULL, *sandboxExtensions = NULL;
		bool fullyDebugged = false;
		int result = systemwide_process_checkin(auditToken, &jbRootPath, &bootUUID, &sandboxExtensions, &reply->fullyDebugged);

		reply->base.msg.magic         = jbsMachMsg->magic;
		reply->base.msg.action        = jbsMachMsg->action;
		reply->base.msg.hdr.msgh_size = replySize;

		if (jbRootPath) {
			strlcpy(reply->jbRootPath, jbRootPath, sizeof(reply->jbRootPath));
			free(jbRootPath);
		}
		if (bootUUID) {
			strlcpy(reply->bootUUID, bootUUID, sizeof(reply->bootUUID));
			free(bootUUID);
		}
		if (sandboxExtensions) {
			strlcpy(reply->sandboxExtensions, sandboxExtensions, sizeof(reply->sandboxExtensions));
			free(sandboxExtensions);
		}

		reply->base.status = result;
		r = 0;
	}
	else if (jbsMachMsg->action == JBSERVER_MACH_FORK_FIX) {
		if (msgSize < sizeof(struct jbserver_mach_msg_forkfix)) return -1;
		struct jbserver_mach_msg_forkfix *forkfixMsg = (struct jbserver_mach_msg_forkfix *)jbsMachMsg;

		size_t replySize = sizeof(struct jbserver_mach_msg_forkfix_reply);
		replyData = malloc(replySize);
		struct jbserver_mach_msg_forkfix_reply *reply = (struct jbserver_mach_msg_forkfix_reply *)replyData;
		memset(reply, 0, replySize);
		
		int result = systemwide_fork_fix(auditToken, forkfixMsg->childPid);

		reply->base.msg.magic         = jbsMachMsg->magic;
		reply->base.msg.action        = jbsMachMsg->action;
		reply->base.msg.hdr.msgh_size = replySize;

		reply->base.status = result;
		r = 0;
	}
	else if (jbsMachMsg->action == JBSERVER_MACH_TRUST_FILE) {
		if (msgSize < sizeof(struct jbserver_mach_msg_trust_fd)) return -1;
		struct jbserver_mach_msg_trust_fd *trustMsg = (struct jbserver_mach_msg_trust_fd *)jbsMachMsg;

		size_t replySize = sizeof(struct jbserver_mach_msg_trust_fd_reply);
		replyData = malloc(replySize);
		struct jbserver_mach_msg_trust_fd_reply *reply = (struct jbserver_mach_msg_trust_fd_reply *)replyData;
		memset(reply, 0, replySize);

		int result = systemwide_trust_file(auditToken, trustMsg->fd, trustMsg->siginfoPopulated ? &trustMsg->siginfo : NULL, sizeof(struct siginfo));

		reply->base.msg.magic         = jbsMachMsg->magic;
		reply->base.msg.action        = jbsMachMsg->action;
		reply->base.msg.hdr.msgh_size = replySize;

		reply->base.status = result;
		r = 0;
	}

	jbserver_send_mach_reply(&jbsMachMsg->hdr, replyData);

	if (replyData) free(replyData);

	return r;
}

/*int jbserver_received_complex_mach_message(audit_token_t *auditToken, uint64_t action, struct jbserver_mach_complex_msg *jbsComplexMachMsg)
{
	int r = -1;

	// Anything implemented by the mach server is provided systemwide
	// So we also need to honor the allowed handler of the systemwide domain
	if (!systemwide_domain_allowed(*auditToken)) return -1;

	uint64_t msgSize = jbsComplexMachMsg->hdr.msgh_size;
	void *replyData = NULL;

	if (action == JBSERVER_MACH_TRUST_FILE) {
		if (msgSize < sizeof(struct jbserver_mach_msg_trust_fd)) return -1;
		struct jbserver_mach_msg_trust_fd *trustFdMsg = (struct jbserver_mach_msg_trust_fd *)jbsComplexMachMsg;
		if (trustFdMsg->base.body.msgh_descriptor_count != 1) return -1;

		int fd = fileport_makefd(trustFdMsg->fdPort.name);
		if (fd < 0) return -1;

		size_t replySize = sizeof(struct jbserver_mach_msg_trust_fd_reply);
		replyData = malloc(replySize);
		struct jbserver_mach_msg_trust_fd_reply *reply = (struct jbserver_mach_msg_trust_fd_reply *)replyData;
		memset(reply, 0, replySize);

		int result = systemwide_trust_file(fd);
		close(fd);

		reply->base.msg.magic         = JBSERVER_MACH_MAGIC;
		reply->base.msg.action        = action;
		reply->base.msg.hdr.msgh_size = replySize;

		reply->base.status = result;
		r = 0;
	}

	jbserver_send_mach_reply(&jbsComplexMachMsg->hdr, replyData);

	if (replyData) free(replyData);

	return r;
}*/