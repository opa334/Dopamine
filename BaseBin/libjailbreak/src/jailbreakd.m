#import "jailbreakd.h"

#import <mach/mach.h>
#import <unistd.h>
#import "pplrw.h"

kern_return_t bootstrap_look_up(mach_port_t port, const char *service, mach_port_t *server_port);

static pid_t mach_port_get_pid(mach_port_t port) {
	mach_port_t owner;
	mach_port_status_t status;
	mach_msg_type_number_t count = MACH_PORT_RECEIVE_STATUS_COUNT;
	kern_return_t kr = mach_port_get_attributes(mach_task_self(), port, MACH_PORT_RECEIVE_STATUS, (mach_port_info_t)&status, &count);
	if (kr != KERN_SUCCESS) {
		NSLog(@"Error: mach_port_get_attributes() failed with error %d (%s)\n", kr, mach_error_string(kr));
		return -1;
	}
	return status.mps_pset;
}

uint64_t jbdParseNumUInt64(NSNumber *num)
{
	if ([num isKindOfClass:NSNumber.class]) {
		return num.unsignedLongLongValue;
	}
	return 0;
}

uint64_t jbdParseNumInt64(NSNumber *num)
{
	if ([num isKindOfClass:NSNumber.class]) {
		return num.longLongValue;
	}
	return 0;
}

bool jbdParseBool(NSNumber *num)
{
	if ([num isKindOfClass:NSNumber.class]) {
		return num.boolValue;
	}
	return 0;
}

mach_port_t jbdMachPort(void)
{
	mach_port_t outPort = -1;

	if (getpid() == 1) {
		host_get_special_port(mach_host_self(), HOST_LOCAL_NODE, 15, &outPort);
	}
	else {
		bootstrap_look_up(bootstrap_port, "com.opa334.jailbreakd", &outPort);
	}

	return outPort;
}

int jbdEncodeMessage(mach_msg_header_t *msgPtr, NSDictionary *dictionary, size_t maxSize)
{
	NSError *error;
	NSData *msgData = [NSPropertyListSerialization dataWithPropertyList:dictionary format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
	if (!msgData) {
		NSLog(@"ERROR: Failed to encode message, %@", error);
		return 1;
	}
	
	uint8_t *dataStartPtr = (uint8_t *)(msgPtr + 1);

	size_t maxDataSize = maxSize - sizeof(mach_msg_header_t) - sizeof(uint64_t);

	if(msgData.length > maxDataSize) {
		NSLog(@"ERROR: Failed to encode message, dict is too big");
		return 1;
	}
	
	msgPtr->msgh_size = (sizeof(mach_msg_header_t) + msgData.length + sizeof(uint64_t) + 3) & ~3;

	*(uint64_t *)dataStartPtr = msgData.length;
	uint8_t *dictDataStartPtr = dataStartPtr + sizeof(uint64_t);

	[msgData getBytes:dictDataStartPtr length:msgData.length];
	return 0;
}

NSDictionary *jbdDecodeMessage(mach_msg_header_t *msgPtr)
{
	uint8_t *dataStartPtr = (void *)(msgPtr + 1);
	uint64_t dictSize = *(uint64_t *)dataStartPtr;
	uint8_t *dictDataStartPtr = dataStartPtr + sizeof(uint64_t);

	size_t maxDictSize = msgPtr->msgh_size - sizeof(mach_msg_header_t) - sizeof(uint64_t);
	if (dictSize > maxDictSize) {
		NSLog(@"ERROR: Malformed incoming message size, discarding...");
		return nil;
	}

	NSError *error;
	NSData *msgDictData = [NSData dataWithBytes:dictDataStartPtr length:dictSize];
	NSDictionary *dictionary = [NSPropertyListSerialization propertyListWithData:msgDictData options:0 format:nil error:&error];
	if (!dictionary)
	{
		NSLog(@"ERROR: Failed to decode dictionary from mach msg: %@", error);
	}

	return dictionary;
}


NSDictionary *sendJBDMessage(JBD_MESSAGE_ID messageId, NSDictionary *messageDict)
{
	mach_port_t daemon_port = jbdMachPort();
	mach_port_t reply_port;
	mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &reply_port);
	mach_port_insert_right(mach_task_self(), reply_port, reply_port, MACH_MSG_TYPE_MAKE_SEND);
	
	mach_msg_header_t *msg = malloc(0x1000);
	memset(msg, 0, 0x1000);
	jbdEncodeMessage(msg, messageDict, 0x1000);
	msg->msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
	msg->msgh_remote_port = daemon_port;
	msg->msgh_local_port = reply_port;
	msg->msgh_id = messageId;

	kern_return_t kr = mach_msg(msg, MACH_SEND_MSG | MACH_RCV_MSG, msg->msgh_size, 0x1000, reply_port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
	if (kr != KERN_SUCCESS) {
		NSLog(@"ERROR: mach_msg failed %d (%s)", kr, mach_error_string(kr));
		return nil;
	}

	return jbdDecodeMessage(msg);
}

void jbdGetStatus(uint64_t *PPLRWStatus, uint64_t *kcallStatus, pid_t *pid)
{
	NSDictionary *response = sendJBDMessage(JBD_MSG_GET_STATUS, @{});
	if (!response) return;

	if (PPLRWStatus) *PPLRWStatus = jbdParseNumUInt64(response[@"PPLRWStatus"]);
	if (kcallStatus) *kcallStatus = jbdParseNumUInt64(response[@"kcallStatus"]);
	if (pid) *pid = jbdParseNumInt64(response[@"pid"]);
}

void jbdTransferPPLRW(uint64_t magicPage)
{
	sendJBDMessage(JBD_MSG_PPL_INIT, @{ @"magicPage" : @(magicPage) });
}

uint64_t jbdTransferKcall(uint64_t kernelAllocation)
{
	NSDictionary *response = sendJBDMessage(JBD_MSG_PAC_INIT, @{ @"kernelAllocation" : @(kernelAllocation) });
	return jbdParseNumUInt64(response[@"arcContext"]);
}

void jbdFinalizeKcall(void)
{
	sendJBDMessage(JBD_MSG_PAC_FINALIZE, @{});
}

int jbdInitPPLRW(void)
{
	NSDictionary *response = sendJBDMessage(JBD_MSG_HANDOFF_PPL, @{});
	int64_t errorCode = jbdParseNumInt64(response[@"errorCode"]);
	uint64_t magicPage = jbdParseNumUInt64(response[@"magicPage"]);

	if (errorCode) return errorCode;
	initPPLPrimitives(magicPage);
	return 0;
}

uint64_t jbdKcall(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8)
{
	NSDictionary *response = sendJBDMessage(JBD_MSG_KCALL, @{
		@"func" : @(func),
		@"a1" : @(a1),
		@"a2" : @(a2),
		@"a3" : @(a3),
		@"a4" : @(a4),
		@"a5" : @(a5),
		@"a6" : @(a6),
		@"a7" : @(a7),
		@"a8" : @(a8),
	});
	return jbdParseNumUInt64(response[@"ret"]);
}

bool jbdUnrestrictProc(pid_t pid)
{
	NSDictionary *response = sendJBDMessage(JBD_MSG_UNRESTRICT_PROC, @{
		@"pid" : @(pid)
	});
	return jbdParseBool(response[@"success"]);
}

void jbdRebuildTrustCache(void)
{
	sendJBDMessage(JBD_MSG_REBUILD_TRUSTCACHE, @{});
}

int jbdInitKcall(void)
{
	return 0;
}
