#include <mach/mach.h>

#include <xpc/xpc.h>
#include <xpc_private.h>
#include <libjailbreak/hookd.h>
#include <libproc.h>
#include <sys/proc_info.h>

mach_port_t extract_task_port(mach_port_t clientTaskPort, mach_port_t callerPort)
{
	if (callerPort == -1) {
		mach_port_mod_refs(mach_task_self(), clientTaskPort, MACH_PORT_RIGHT_SEND, 1);
		// printf("extract_task_port: Got callerPort=-1, taking clientTaskPort (%d)\n", clientTaskPort); fflush(stdout);
		return clientTaskPort;
	}

	mach_port_t extracted;
	mach_msg_type_name_t right;
	kern_return_t kr = mach_port_extract_right(clientTaskPort, callerPort, MACH_MSG_TYPE_COPY_SEND, &extracted, &right);
	if (kr != KERN_SUCCESS) {
		// printf("extract_task_port: Got clientTaskPort=%d, callerPort=%d, failed extracting: %d\n", clientTaskPort, callerPort, kr); fflush(stdout);
		return MACH_PORT_NULL;
	}

	// printf("extract_task_port: Got clientTaskPort=%d, callerPort=%d, extracted to %d\n", clientTaskPort, callerPort, extracted); fflush(stdout);
	return extracted;
}


int apply_hook(mach_port_t clientTaskPort, mach_port_t taskPortInClient, vm_address_t vmaddr, const void *data, vm_size_t size)
{
	if (!data || size == 0) return -1;

	mach_port_t taskPort = extract_task_port(clientTaskPort, taskPortInClient);
	if (!MACH_PORT_VALID(taskPort)) {
		// printf("apply_hook: Error, task port %d is invalid\n", taskPort); fflush(stdout);
		return -1;
	}

	// char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
	// pid_t taskPortPid = 0;
	// pid_for_task(taskPort, &taskPortPid);
	// if (proc_pidpath (taskPortPid, pathbuf, sizeof(pathbuf)) <= 0) {
	// 	strlcpy(pathbuf, "<unknown>", sizeof(pathbuf));
	// }
	// printf("Applying hook with size %zu at %#llx in [pid=%d,path=%s]\n", size, vmaddr, taskPortPid, pathbuf);

	kern_return_t kr = vm_protect(taskPort, vmaddr, size, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
	if (kr != KERN_SUCCESS) {
		// printf("Failed to make %lx->%#lx in task %d writable (%d)\n", vmaddr, vmaddr+size, taskPort, kr); fflush(stdout);
		mach_port_mod_refs(mach_task_self(), taskPort, MACH_PORT_RIGHT_SEND, -1);
		return kr;
	}

	kr = vm_write(taskPort, vmaddr, (vm_offset_t)data, (mach_msg_type_number_t)size);
	if (kr != KERN_SUCCESS) {
		// printf("Failed to write data at %#lx in task %d (%d)\n", (vm_offset_t)data, taskPort, kr); fflush(stdout);
	}

	kern_return_t restoreKr = vm_protect(taskPort, vmaddr, size, false, VM_PROT_READ | VM_PROT_EXECUTE);
	if (restoreKr != KERN_SUCCESS) {
		// printf("Failed to make %lx->%#lx in task %d executable (%d)\n", vmaddr, vmaddr+size, taskPort, restoreKr); fflush(stdout);
		mach_port_mod_refs(mach_task_self(), taskPort, MACH_PORT_RIGHT_SEND, -1);
		return restoreKr;
	}

	mach_port_mod_refs(mach_task_self(), taskPort, MACH_PORT_RIGHT_SEND, -1);
	return kr;
}

int apply_fixup(mach_port_t clientTaskPort, mach_port_t taskPortInClient, vm_address_t address, vm_size_t size, bool set_maximum, vm_prot_t prot)
{
	mach_port_t taskPort = extract_task_port(clientTaskPort, taskPortInClient);
	if (!MACH_PORT_VALID(taskPort)) {
		// printf("apply_fixup: Error, task port %d is invalid\n", taskPort); fflush(stdout);
		return -1;
	}

	kern_return_t kr = vm_protect(taskPort, address, size, set_maximum, prot);
	mach_port_mod_refs(mach_task_self(), taskPort, MACH_PORT_RIGHT_SEND, -1);
	return kr;
}

void server_loop(mach_port_t port)
{
	kern_return_t kr;
	mach_msg_size_t buffer_size = 4096 + MAX_TRAILER_SIZE;
	void *buffer = malloc(buffer_size);

	while (true) {
		struct hookd_mach_msg *msg = (struct hookd_mach_msg *)buffer;
		task_port_t clientTaskPort = MACH_PORT_NULL;

		kr = mach_msg(
			(mach_msg_header_t *)msg,
			MACH_RCV_MSG |
			MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) |
			MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT),
			0,
			buffer_size,
			port,
			MACH_MSG_TIMEOUT_NONE,
			MACH_PORT_NULL
		);

		if (kr != KERN_SUCCESS) {
			continue;
		}

		// printf("Hookd received msg: ");
		// __builtin_dump_struct(msg, printf);

		if (msg->hdr.msgh_size < sizeof(struct hookd_mach_msg)) goto deny;

		mach_msg_trailer_t *trailer = (mach_msg_trailer_t *)((uint8_t *)msg + msg->hdr.msgh_size);
		if (trailer->msgh_trailer_type != MACH_MSG_TRAILER_FORMAT_0 || 
			trailer->msgh_trailer_size < sizeof(mach_msg_audit_trailer_t)) goto deny;

		mach_msg_audit_trailer_t *auditTrailer = (mach_msg_audit_trailer_t *)trailer;
		pid_t callerPid = audit_token_to_pid(auditTrailer->msgh_audit);

#if !HOOKD_SKIP_CALLER_VERIFICATION
		if (callerPid != 1) goto deny;
#endif

		size_t dataSize = msg->hdr.msgh_size - offsetof(struct hookd_mach_msg, data);
		
		if (msg->hooksStartOff > dataSize) goto deny;
		if (msg->fixupsStartOff > dataSize) goto deny;
		if (msg->hooksStartOff > msg->fixupsStartOff) goto deny;

		kr = task_for_pid(mach_task_self(), msg->clientPid, &clientTaskPort);
		if (kr != KERN_SUCCESS || !MACH_PORT_VALID(clientTaskPort)) {
			// printf("task_for_pid(%d) failed (%d)\n", msg->clientPid, kr);
			goto deny;
		}

		size_t hooksSize = msg->fixupsStartOff - msg->hooksStartOff;
		size_t fixupsSize = dataSize - msg->fixupsStartOff;

		uint8_t *hooksStart  = &msg->data[msg->hooksStartOff];
		uint8_t *fixupsStart = &msg->data[msg->fixupsStartOff];

		// Apply hooks
		int64_t *hookResults = NULL;
		uint32_t hookCount = 0;
		if (hooksSize > 0) {
			for (uint32_t idx = 0; idx < hooksSize;) {
				struct hookd_encoded_hook *hook = (struct hookd_encoded_hook *)&hooksStart[idx];
				uint32_t remainingBytes = hooksSize - idx;
				uint32_t hookSize = sizeof(*hook) + hook->dataSize;
				if (hookSize > remainingBytes) break;

				hookCount++;
				hookResults = realloc(hookResults, sizeof(int64_t) * hookCount);
				hookResults[hookCount-1] = apply_hook(clientTaskPort, msg->taskPortInClient, hook->address, hook->data, hook->dataSize);
				// printf("Hook %d (address=%#llx, data=%p, dataSize=%zu) => %lld\n", hookCount-1, hook->address, hook->data, hook->dataSize, hookResults[hookCount-1]);
				idx += hookSize;
			}
		}

		// Apply fixups
		int64_t *fixupResults = NULL;
		uint32_t fixupCount = 0;
		if ((fixupsSize > 0) && ((fixupsSize % sizeof(struct hookd_encoded_fixup)) == 0)) {
			fixupCount = fixupsSize / sizeof(struct hookd_encoded_fixup);
			fixupResults = malloc(fixupCount * sizeof(int64_t));

			for (uint32_t idx = 0; idx < fixupCount; idx++) {
				struct hookd_encoded_fixup *fixup = (struct hookd_encoded_fixup *)&fixupsStart[idx * sizeof(struct hookd_encoded_fixup)];
				fixupResults[idx] = apply_fixup(clientTaskPort, msg->taskPortInClient, fixup->address, fixup->size, fixup->set_maximum, fixup->prot);
				// printf("Fixup %d => %lld\n", idx, fixupResults[idx]);
			}
		}

		size_t hookResultsSize  = hookCount * sizeof(int64_t);
		size_t fixupResultsSize = fixupCount * sizeof(int64_t);

		size_t replySize = sizeof(struct hookd_mach_msg_reply) + hookResultsSize + fixupResultsSize;
		struct hookd_mach_msg_reply *reply = malloc(replySize);
		reply->hdr.msgh_size = replySize;
		
		reply->hookResultsCount  = hookCount;
		reply->fixupResultsCount = fixupCount;

		if (hookResults)  { memcpy(&reply->data[0],               hookResults,  hookResultsSize);  free(hookResults); }
		if (fixupResults) { memcpy(&reply->data[hookResultsSize], fixupResults, fixupResultsSize); free(fixupResults); }

		int32_t bits = MACH_MSGH_BITS_REMOTE(msg->hdr.msgh_bits);
		if (bits == MACH_MSG_TYPE_COPY_SEND) {
			bits = MACH_MSG_TYPE_MOVE_SEND;
		}
		reply->hdr.msgh_bits = MACH_MSGH_BITS(bits, 0);
		reply->hdr.msgh_remote_port  = msg->hdr.msgh_remote_port;
		reply->hdr.msgh_local_port   = 0;
		reply->hdr.msgh_voucher_port = 0;
		reply->hdr.msgh_id           = msg->hdr.msgh_id + 100;

		// printf("Hookd sending reply: ");
		// __builtin_dump_struct(reply, printf);

		if (mach_msg_send(&reply->hdr) == KERN_SUCCESS) {
			msg->hdr.msgh_remote_port = 0;
			msg->hdr.msgh_bits = msg->hdr.msgh_bits & ~MACH_MSGH_BITS_REMOTE_MASK;
		}

deny:
		if (MACH_PORT_VALID(clientTaskPort)) {
			mach_port_mod_refs(mach_task_self(), clientTaskPort, MACH_PORT_RIGHT_SEND, -1);
		}
		mach_msg_destroy(&msg->hdr);
		fflush(stdout);
		continue;
	}
}

int main(int argc, char **argv)
{
	//freopen("/private/preboot/hookd.log", "a+", stdout); 

	// printf("hookd: we out here\n"); fflush(stdout);

	// Create server port
	mach_port_t serverPort = MACH_PORT_NULL;
	mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &serverPort);
	mach_port_insert_right(mach_task_self(), serverPort, serverPort, MACH_MSG_TYPE_MAKE_SEND);

	// Send server port to parent
	mach_port_t *registeredPorts;
	mach_msg_type_number_t registeredPortsCount = 0;
	kern_return_t kr = mach_ports_lookup(mach_task_self(), &registeredPorts, &registeredPortsCount);
	if (kr != KERN_SUCCESS) {
		// printf("hookd failed to lookup registered ports\n"); fflush(stdout);
		return -1;
	}

	mach_port_t checkinPort = registeredPorts[2];
	if (checkinPort == MACH_PORT_NULL) {
		// printf("checkinPort is NULL, not launched from launchd\n"); fflush(stdout);
		return -1;
	}

	mach_msg_header_t hdr = {};
	hdr.msgh_size         = sizeof(hdr);
	hdr.msgh_bits        |= MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND);
	hdr.msgh_remote_port  = checkinPort;
	hdr.msgh_local_port   = serverPort;
	hdr.msgh_voucher_port = 0;
	hdr.msgh_id           = 0x40000000;

	kr = mach_msg(&hdr, MACH_SEND_MSG, hdr.msgh_size, 0, 0, 0, 0);
	if (kr != KERN_SUCCESS) {
		// printf("hookd failed to send checkin to parent\n"); fflush(stdout);
		return kr;
	}

	vm_deallocate(mach_task_self(), (vm_address_t)registeredPorts, sizeof(mach_port_t) * registeredPortsCount);

	// Start server
	// printf("hookd: Starting server...\n"); fflush(stdout);
	server_loop(serverPort);

	return 0;
}
