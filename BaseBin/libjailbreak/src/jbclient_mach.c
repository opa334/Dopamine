#include "jbclient_mach.h"
#include <dispatch/dispatch.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <pthread.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
extern int fileport_makeport (int fd, mach_port_t * port);

mach_port_t jbclient_mach_get_launchd_port(void)
{
	mach_port_t launchdPort = MACH_PORT_NULL;
	task_get_bootstrap_port(mach_task_self(), &launchdPort);
	if (launchdPort == MACH_PORT_NULL) {
		mach_port_t *registeredPorts;
		mach_msg_type_number_t registeredPortsCount = 0;
		if (mach_ports_lookup(mach_task_self(), &registeredPorts, &registeredPortsCount) == KERN_SUCCESS) {
			launchdPort = registeredPorts[0];
			for (mach_msg_type_number_t i = 1; i < registeredPortsCount; i++) {
				mach_port_deallocate(mach_task_self(), registeredPorts[i]);
			}
			vm_deallocate(mach_task_self(), (vm_address_t)registeredPorts, registeredPortsCount * sizeof(mach_port_t));
		}
	}

	return launchdPort;
}

kern_return_t jbclient_mach_send_msg(mach_msg_header_t *hdr, struct jbserver_mach_msg_reply *reply)
{
	mach_port_t replyPort = mig_get_reply_port();
	if (!MACH_PORT_VALID(replyPort))
		return KERN_FAILURE;
	
	mach_port_t launchdPort = jbclient_mach_get_launchd_port();
	if (!MACH_PORT_VALID(launchdPort))
		return KERN_FAILURE;
	
	hdr->msgh_bits |= MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);

	// size already set
	hdr->msgh_remote_port  = launchdPort;
	hdr->msgh_local_port   = replyPort;
	hdr->msgh_voucher_port = 0;
	hdr->msgh_id           = 0x40000000 | 206;
	// 206: magic value to make WebContent work (seriously, this is the only ID that the WebContent sandbox allows)
	
	kern_return_t kr = mach_msg(hdr, MACH_SEND_MSG, hdr->msgh_size, 0, 0, 0, 0);
	if (kr != KERN_SUCCESS) {
		mach_port_deallocate(mach_task_self(), launchdPort);
		return kr;
	}
	
	reply->status = -1;
	kr = mach_msg(&reply->msg.hdr, MACH_RCV_MSG, 0, reply->msg.hdr.msgh_size, replyPort, 0, 0);
	if (kr != KERN_SUCCESS) {
		mach_port_deallocate(mach_task_self(), launchdPort);
		return kr;
	}
	
	// Get rid of any rights we might have received
	mach_msg_destroy(&reply->msg.hdr);
	mach_port_deallocate(mach_task_self(), launchdPort);
	return KERN_SUCCESS;
}

int jbclient_mach_process_checkin(char *jbRootPathOut, char *bootUUIDOut, char *sandboxExtensionsOut, bool *fullyDebuggedOut, bool *forceCSAdhocOut)
{
	struct jbserver_mach_msg_checkin msg;
	msg.base.hdr.msgh_size = sizeof(msg);
	msg.base.hdr.msgh_bits = 0;
	msg.base.action = JBSERVER_MACH_CHECKIN;
	msg.base.magic = JBSERVER_MACH_MAGIC;

	size_t replySize = sizeof(struct jbserver_mach_msg_checkin_reply) + MAX_TRAILER_SIZE;
	uint8_t replyU[replySize];
	bzero(replyU, replySize);
	struct jbserver_mach_msg_checkin_reply *reply = (struct jbserver_mach_msg_checkin_reply *)&replyU;
	reply->base.msg.hdr.msgh_size = replySize;

	kern_return_t kr = jbclient_mach_send_msg(&msg.base.hdr, (struct jbserver_mach_msg_reply *)reply);
	if (kr != KERN_SUCCESS) return kr;

	if (jbRootPathOut)        strlcpy(jbRootPathOut,        reply->jbRootPath,        sizeof(reply->jbRootPath));
	if (bootUUIDOut)          strlcpy(bootUUIDOut,          reply->bootUUID,          sizeof(reply->bootUUID));
	if (sandboxExtensionsOut) strlcpy(sandboxExtensionsOut, reply->sandboxExtensions, sizeof(reply->sandboxExtensions));

	if (fullyDebuggedOut) *fullyDebuggedOut = reply->fullyDebugged;
	if (forceCSAdhocOut) *forceCSAdhocOut = reply->forceCSAdhoc;

	return (int)reply->base.status;
}

int jbclient_mach_fork_fix(pid_t childPid)
{
	struct jbserver_mach_msg_forkfix msg;
	msg.base.hdr.msgh_size = sizeof(msg);
	msg.base.hdr.msgh_bits = 0;
	msg.base.action = JBSERVER_MACH_FORK_FIX;
	msg.base.magic = JBSERVER_MACH_MAGIC;

	msg.childPid = childPid;

	size_t replySize = sizeof(struct jbserver_mach_msg_forkfix_reply) + MAX_TRAILER_SIZE;
	uint8_t replyU[replySize];
	bzero(replyU, replySize);
	struct jbserver_mach_msg_forkfix_reply *reply = (struct jbserver_mach_msg_forkfix_reply *)&replyU;
	reply->base.msg.hdr.msgh_size = replySize;

	kern_return_t kr = jbclient_mach_send_msg(&msg.base.hdr, (struct jbserver_mach_msg_reply *)reply);
	if (kr != KERN_SUCCESS) return kr;

	return (int)reply->base.status;
}

int jbclient_mach_trust_file(int fd, struct siginfo *siginfo, bool attach)
{
	struct jbserver_mach_msg_trust_fd msg;
	msg.base.hdr.msgh_size = sizeof(msg);
	msg.base.hdr.msgh_bits = 0;
	msg.base.action = JBSERVER_MACH_TRUST_FILE;
	msg.base.magic = JBSERVER_MACH_MAGIC;

	msg.fd = fd;
	msg.siginfoPopulated = siginfo ? true : false;
	if (siginfo) {
		memcpy(&msg.siginfo, siginfo, sizeof(struct siginfo));
	}
	msg.attach = attach;

	size_t replySize = sizeof(struct jbserver_mach_msg_trust_fd_reply) + MAX_TRAILER_SIZE;
	uint8_t replyU[replySize];
	bzero(replyU, replySize);
	struct jbserver_mach_msg_trust_fd_reply *reply = (struct jbserver_mach_msg_trust_fd_reply *)&replyU;
	reply->base.msg.hdr.msgh_size = replySize;

	kern_return_t kr = jbclient_mach_send_msg(&msg.base.hdr, (struct jbserver_mach_msg_reply *)reply);
	if (kr != KERN_SUCCESS) return kr;

	return (int)reply->base.status;
}

int jbclient_mach_hookd_send_msg(struct hookd_mach_msg *hookdMsg, struct hookd_mach_msg_reply *hookdReply)
{
	if (!hookdMsg || !hookdReply) return -1;
	if (hookdMsg->hdr.msgh_size > HOOKD_MSG_MAX_SIZE) return -1;

	size_t msgSize = sizeof(struct jbserver_mach_msg_hookd_send_msg) + HOOKD_MSG_MAX_SIZE;
	uint8_t msgBuf[msgSize];
	bzero(msgBuf, msgSize);
	struct jbserver_mach_msg_hookd_send_msg *msg = (struct jbserver_mach_msg_hookd_send_msg *)&msgBuf;
	msg->base.hdr.msgh_size = sizeof(struct jbserver_mach_msg_hookd_send_msg) + hookdMsg->hdr.msgh_size;
	msg->base.hdr.msgh_bits = 0;
	msg->base.action = JBSERVER_MACH_HOOKD_SEND_MSG;
	msg->base.magic = JBSERVER_MACH_MAGIC;

	// Copy message
	memcpy(&msg->hookdMsg[0], hookdMsg, hookdMsg->hdr.msgh_size);

	size_t replySize = sizeof(struct jbserver_mach_msg_hookd_send_msg_reply) + HOOKD_MSG_MAX_SIZE + MAX_TRAILER_SIZE;
	uint8_t replyBuf[replySize];
	bzero(replyBuf, replySize);
	struct jbserver_mach_msg_hookd_send_msg_reply *fullReply = (struct jbserver_mach_msg_hookd_send_msg_reply *)&replyBuf;
	fullReply->base.msg.hdr.msgh_size = replySize;

	kern_return_t kr = jbclient_mach_send_msg(&msg->base.hdr, (struct jbserver_mach_msg_reply *)fullReply);
	if (kr != KERN_SUCCESS) return kr;

	memcpy(hookdReply, fullReply->hookdReply, HOOKD_MSG_MAX_SIZE);

	return (int)fullReply->base.status;
}