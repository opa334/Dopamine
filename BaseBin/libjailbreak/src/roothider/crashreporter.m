
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <libgen.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <mach/mach.h>
#include <mach/exception_types.h>
#include <mach-o/dyld.h>
#include <pthread/stack_np.h>
#include <pthread/pthread.h>
#include <dispatch/dispatch.h>

#include "crashreporter.h"
#include "common.h"
#include "log.h"

#ifndef __MigPackStructs
#define __MigPackStructs
#endif
#include "mach_exc.h" //mig -arch arm64 -arch arm64e mach_exc.defs

#define RB_QUICK	0x400
#define RB_PANIC	0x800
int reboot_np(int howto, const char *message); //only works in launchd

#undef ABORT
#define ABORT(...) do { \
		char *message=NULL; \
		asprintf(&message, __VA_ARGS__); \
		reboot_np(RB_PANIC|RB_QUICK, message); \
		free(message); \
		JBLogError(__VA_ARGS__); \
		_exit(0); \
	} while(0)

static const char* gReportName = NULL;
static NSUncaughtExceptionHandler* defaultNSExceptionHandler = NULL;

extern CFStringRef CFCopySystemVersionString(void);

#define	INSTACK(a)	((a) >= stackbot && (a) <= stacktop)
#if defined(__x86_64__)
#define	ISALIGNED(a)	((((uintptr_t)(a)) & 0xf) == 0)
#elif defined(__i386__)
#define	ISALIGNED(a)	((((uintptr_t)(a)) & 0xf) == 8)
#elif defined(__arm__) || defined(__arm64__)
#define	ISALIGNED(a)	((((uintptr_t)(a)) & 0x1) == 0)
#endif

#define EXC_MASK_CRASH_RELATED (EXC_MASK_BAD_ACCESS | \
		EXC_MASK_BAD_INSTRUCTION |			  \
		EXC_MASK_ARITHMETIC |				  \
		EXC_MASK_EMULATION |				  \
		EXC_MASK_SOFTWARE |					  \
		EXC_MASK_BREAKPOINT)

__attribute__((noinline))
static void pthread_backtrace(pthread_t pthread, vm_address_t *buffer, unsigned max, unsigned *nb,
		unsigned skip, void *startfp)
{
	void *frame, *next;
	void *stacktop = pthread_get_stackaddr_np(pthread);
	void *stackbot = stacktop - pthread_get_stacksize_np(pthread);

	*nb = 0;

	// Rely on the fact that our caller has an empty stackframe (no local vars)
	// to determine the minimum size of a stackframe (frame ptr & return addr)
	frame = startfp;
	next = (void*)pthread_stack_frame_decode_np((uintptr_t)frame, NULL);

	/* make sure return address is never out of bounds */
	stacktop -= (next - frame);

	if(!INSTACK(frame) || !ISALIGNED(frame))
		return;
	while (startfp || skip--) {
		if (startfp && startfp < next) break;
		if(!INSTACK(next) || !ISALIGNED(next) || next <= frame)
			return;
		frame = next;
		next = (void*)pthread_stack_frame_decode_np((uintptr_t)frame, NULL);
	}
	while (max--) {
		uintptr_t retaddr;
		next = (void*)pthread_stack_frame_decode_np((uintptr_t)frame, &retaddr);
		buffer[*nb] = retaddr;
		(*nb)++;
		if(!INSTACK(next) || !ISALIGNED(next) || next <= frame)
			return;
		frame = next;
	}
}

static crash_reporter_state gCrashReporterState = kCrashReporterStateNotActive;
mach_port_t gExceptionPort = MACH_PORT_NULL;
dispatch_queue_t gExceptionQueue = NULL;
pthread_t gExceptionThread = 0;

const char *crashreporter_string_for_code(int code)
{
	switch (code)
	{
		case EXC_BAD_ACCESS:
		return "EXC_BAD_ACCESS";

		case EXC_BAD_INSTRUCTION:
		return "EXC_BAD_INSTRUCTION";

		case EXC_ARITHMETIC:
		return "EXC_ARITHMETIC";

		case EXC_EMULATION:
		return "EXC_EMULATION";

		case EXC_SOFTWARE:
		return "EXC_SOFTWARE";
	
		case EXC_BREAKPOINT:
		return "EXC_BREAKPOINT";

		case EXC_SYSCALL:
		return "EXC_SYSCALL";

		case EXC_MACH_SYSCALL:
		return "EXC_MACH_SYSCALL";

		case EXC_RPC_ALERT:
		return "EXC_RPC_ALERT";

		case EXC_CRASH:
		return "EXC_CRASH";

		case EXC_RESOURCE:
		return "EXC_RESOURCE";

		case EXC_GUARD:
		return "EXC_GUARD";

		case EXC_CORPSE_NOTIFY:
		return "EXC_CORPSE_NOTIFY";
	}
	return NULL;
}

void crashreporter_dump_backtrace_line(FILE *f, vm_address_t addr)
{
	Dl_info info;
	if (dladdr((void *)addr, &info) != 0) {
		const char *sname = info.dli_sname;
		const char *fname = info.dli_fname;
		if (!sname) {
			sname = "<unexported>";
		}

		fprintf(f, "0x%lX: %s (0x%lX + 0x%lX) (%s(0x%lX) + 0x%lX)\n", addr, sname, (vm_address_t)info.dli_saddr, addr - (vm_address_t)info.dli_saddr, fname, (vm_address_t)info.dli_fbase, addr - (vm_address_t)info.dli_fbase);
	}
	else {
		fprintf(f, "0x%lX (no association)\n", addr);
	}
}

FILE *crashreporter_open_outfile(const char *source, char **nameOut)
{
	struct timeval t={0};
	gettimeofday(&t, NULL);

	char *name = NULL;
	asprintf(&name, "%s-%lu.%d-%d.ips", source, t.tv_sec, t.tv_usec, getpid());

	char dumpPath[PATH_MAX];
	strlcpy(dumpPath, "/var/mobile/Library/Logs/CrashReporter/", PATH_MAX);
	strlcat(dumpPath, name, PATH_MAX);

	if (nameOut) {
		*nameOut = name;
	}
	else {
		free(name);
	}

	FILE *f = fopen(dumpPath, "w");
	if (f) {
		struct utsname systemInfo;
		uname(&systemInfo);

		fprintf(f, "Device Model:   %s\n", systemInfo.machine);

		CFStringRef deviceVersion = CFCopySystemVersionString();
		if (deviceVersion) {
			fprintf(f, "Device Version: %s\n", CFStringGetCStringPtr(deviceVersion, kCFStringEncodingUTF8));
			CFRelease(deviceVersion);
		}

	#ifdef __arm64e__
		fprintf(f, "Architecture:   arm64e\n");
	#else
		fprintf(f, "Architecture:   arm64\n");
	#endif
		fprintf(f, "\n");
	}

	return f;
}

void crashreporter_save_outfile(FILE *f)
{
	fflush(f);
	fchown(fileno(f), 0, 250);
	fchmod(fileno(f), 00660);
	if (fcntl(fileno(f), F_FULLFSYNC) != 0) {
		fsync(fileno(f));
	}
	fclose(f);

	int dir = open("/var/mobile/Library/Logs/CrashReporter", O_RDONLY | O_DIRECTORY);
	if (dir >= 0) {
		if (fcntl(dir, F_FULLFSYNC) != 0) {
			fsync(dir);
		}
		close(dir);
	}
}

void crashreporter_dump_mach(FILE *f, int exception, int ncode, int64_t* code, arm_thread_state64_t threadState, arm_exception_state64_t exceptionState, pthread_t pthread)
{
	fprintf(f, "Exception:            %s\n", crashreporter_string_for_code(exception));
for(int i=0; i < ncode; i++)
	fprintf(f, "Exception Code[%d]:    0x%016llX (%lld)\n", i, code[i], code[i]);
	fprintf(f, "\n");

	fprintf(f, "Register State:\n");

	arm_thread_state64_t strippedState = threadState;
	__darwin_arm_thread_state64_ptrauth_strip(strippedState);

#ifdef __arm64e__
	uint32_t flags = threadState.__opaque_flags;
	threadState.__opaque_flags |= __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH;
	threadState.__opaque_flags &= ~(__DARWIN_ARM_THREAD_STATE64_FLAGS_IB_SIGNED_LR|__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_PC|__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_LR);
#else
	uint32_t flags = threadState.__pad;
#endif

	for(int i = 0; i <= 28; i++) {
		if (i < 10) {
			fprintf(f, " ");
		}
		fprintf(f, "x%d = 0x%016llX", i, threadState.__x[i]);
		if ((i+1) % (6+1) == 0) {
			fprintf(f, "\n");
		}
		else {
			fprintf(f, ", ");
		}
	}

	fprintf(f, " lr = 0x%016llX,  pc = 0x%016llX,  sp = 0x%016llX,  fp = 0x%016llX, cpsr= 0x%08X,       flags = 0x%08X\nesr = 0x%08X,         far = 0x%016llX\n\n",
		 (uint64_t)__darwin_arm_thread_state64_get_lr(threadState),
		 (uint64_t)__darwin_arm_thread_state64_get_pc(threadState),
		 (uint64_t)__darwin_arm_thread_state64_get_sp(threadState),
		 (uint64_t)__darwin_arm_thread_state64_get_fp(threadState),
		 threadState.__cpsr, flags, exceptionState.__esr, exceptionState.__far);

	fprintf(f, "Stripped State:\n");
	fprintf(f, " pc = 0x%016llX,  lr = 0x%016llX,  sp = 0x%016llX,  fp = 0x%016llX\n\n",
		(uint64_t)__darwin_arm_thread_state64_get_pc(strippedState),
		(uint64_t)__darwin_arm_thread_state64_get_lr(strippedState),
		(uint64_t)__darwin_arm_thread_state64_get_sp(strippedState),
		(uint64_t)__darwin_arm_thread_state64_get_fp(strippedState));

	fprintf(f, "Backtrace:\n");
	crashreporter_dump_backtrace_line(f, (vm_address_t)__darwin_arm_thread_state64_get_pc(strippedState));
	crashreporter_dump_backtrace_line(f, (vm_address_t)__darwin_arm_thread_state64_get_lr(strippedState));

	vm_address_t *bt = malloc(100 * sizeof(vm_address_t));
	memset(bt, 0, 100 * sizeof(vm_address_t));
	unsigned c = 100;
	pthread_backtrace(pthread, bt, c, &c, 0, (void *)__darwin_arm_thread_state64_get_fp(strippedState));

	int btIdx = 0;
	vm_address_t btAddr = bt[btIdx++];
	while (btAddr != 0) {
		crashreporter_dump_backtrace_line(f, btAddr);
		btAddr = bt[btIdx++];
	}
	fprintf(f, "\n");
}

void crashreporter_dump_image_list(FILE *f)
{
	fprintf(f, "Images:\n");
	for (uint32_t i = 0; i < _dyld_image_count(); i++) {
		fprintf(f, "0x%016llX\t%s\n", (uint64_t)_dyld_get_image_header(i), _dyld_get_image_name(i));
	}
}

void crashreporter_catch_mach(__Request__mach_exception_raise_t *request, __Reply__mach_exception_raise_t *reply)
{
	pthread_t pthread = pthread_from_mach_thread_np(request->thread.name);

	arm_thread_state64_t threadState = {0};
	mach_msg_type_number_t threadStateCount = ARM_THREAD_STATE64_COUNT;
	thread_get_state(request->thread.name, ARM_THREAD_STATE64, (thread_state_t)&threadState, &threadStateCount);

	arm_exception_state64_t exceptionState = {0};
	mach_msg_type_number_t exceptionStateCount = ARM_EXCEPTION_STATE64_COUNT;
	thread_get_state(request->thread.name, ARM_EXCEPTION_STATE64, (thread_state_t)&exceptionState, &exceptionStateCount);

	reply->NDR = request->NDR;
	reply->RetCode = KERN_FAILURE;

	__uint64_t tid = 0;
	pthread_threadid_np(pthread, &tid);

	char *name = NULL;
	FILE *f = crashreporter_open_outfile(gReportName, &name);
	if (f) {
		fprintf(f, "Thread %llu crashed.\n\n", tid);
		crashreporter_dump_mach(f, request->exception, request->codeCnt, request->code, threadState, exceptionState, pthread);
		crashreporter_dump_image_list(f);
		crashreporter_save_outfile(f);
	}

	ABORT("Mach exception occured on thread %llu. A detailed report has been written to the file %s.", tid, name ? name : "(null)");
}

void crashreporter_dump_objc(FILE *f, NSException *e)
{
	@autoreleasepool {
		fprintf(f, "Exception:         %s\n", e.name.UTF8String);
		fprintf(f, "Exception Reason:  %s\n", e.reason.UTF8String);
		fprintf(f, "User Info:         %s\n", e.userInfo.description.UTF8String);
		fprintf(f, "\n");

		if (e.callStackReturnAddresses.count) {
			fprintf(f, "Backtrace:\n");
			for (NSNumber *btAddrNum in e.callStackReturnAddresses) {
				crashreporter_dump_backtrace_line(f, [btAddrNum unsignedLongLongValue]);
			}
			fprintf(f, "\n");
		}
		else if (e.callStackSymbols.count) {
			fprintf(f, "Backtrace:\n");
			for (NSString *symbol in e.callStackSymbols) {
				fprintf(f, "%s\n", symbol.UTF8String);
			}
			fprintf(f, "\n");
		} 
	}
}

void crashreporter_catch_objc(NSException *e)
{
	@autoreleasepool {
		static BOOL hasCrashed = NO;
		if (hasCrashed) {
			exit(187);
		}
		else {
			hasCrashed = YES;
		}

		__uint64_t tid = 0;
		pthread_threadid_np(pthread_self(), &tid);

		char *name = NULL;
		FILE *f = crashreporter_open_outfile(gReportName, &name);
		if (f) {
			fprintf(f, "Thread %llu crashed.\n\n", tid);
			@try {
				crashreporter_dump_objc(f, e);
				crashreporter_dump_image_list(f);
			}
			@catch (NSException *e2) {
				exit(187);
			}
			crashreporter_save_outfile(f);
		}
		ABORT("Objective-C exception occured on thread %llu. A detailed report has been written to the file %s.", tid, name ? name : "(null)");
	}
}

void *crashreporter_listen(void *arg)
{
    int bufsize = 4096;
    mach_msg_header_t* msg = (mach_msg_header_t*)malloc(bufsize);
    
	while (true) {
        
        memset(msg, 0, bufsize);
        msg->msgh_size = bufsize;
        mach_msg_return_t ret = mach_msg(msg, MACH_RCV_MSG|MACH_RCV_LARGE, 0, msg->msgh_size, gExceptionPort, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        
        if(ret == MACH_RCV_TOO_LARGE) {
            ABORT("msg too large: %x", msg->msgh_size);
        }
        
        if(ret != MACH_MSG_SUCCESS) {
            ABORT("recv mach msg failed: %x", ret);
        }

		bool ignored = false;
		__Reply__mach_exception_raise_t reply = {0};
		__Request__mach_exception_raise_t* request = (__Request__mach_exception_raise_t *)msg;

		pid_t pid=0;
		kern_return_t kr = pid_for_task(request->task.name, &pid);
		if(kr != KERN_SUCCESS || pid <= 0) {
			ABORT("pid_for_task failed: pid=%d, error=%x,%s", pid, kr, mach_error_string(kr));
		}

		if(pid != getpid()) {
			ABORT("Mach Exception(%d,%llx,%llx) from another process: %d", request->exception, request->code[0], request->code[1], pid);
		}

		/*
		if(proc_traced(getpid()))
		{
			if(request->exception == EXC_SOFTWARE && request->codeCnt == 2 && request->code[0] == EXC_SOFT_SIGNAL) 
			{
				int signum = (int)request->code[1];
				if(signum < SIGILL || signum > SIGSYS)
				{
					FileLogDebug("Ignoring EXC_SOFTWARE for signal %d", signum);
					reply.RetCode = KERN_SUCCESS;
					reply.NDR = request->NDR;
					ignored = true;
				}
			}
		}//*/

		if(!ignored) crashreporter_catch_mach(request, &reply);

		reply.Head.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(msg->msgh_bits), 0);
		reply.Head.msgh_size = sizeof(__Reply__mach_exception_raise_t);
		reply.Head.msgh_remote_port = msg->msgh_remote_port;
		reply.Head.msgh_local_port = MACH_PORT_NULL;
		reply.Head.msgh_id = msg->msgh_id + 0x64;

		mach_msg(&reply.Head, MACH_SEND_MSG | MACH_MSG_OPTION_NONE, reply.Head.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
	}
}

int gCrashReporterStateKey = 0;
int crashreporter_pause(void)
{
	int key = 0;
	@synchronized(@"CrashReporterStateKey")
	{
		if (gCrashReporterState == kCrashReporterStateActive) {
			task_set_exception_ports(mach_task_self_, EXC_MASK_CRASH_RELATED, MACH_PORT_NULL, 0, 0);
			NSSetUncaughtExceptionHandler(defaultNSExceptionHandler);
			defaultNSExceptionHandler = nil;
			gCrashReporterState = kCrashReporterStatePaused;
		}
		//only allow the last pause to be resumed
		key = ++gCrashReporterStateKey;
	}
	return key;
}

void crashreporter_resume(int key)
{
	@synchronized(@"CrashReporterStateKey")
	{
		if(key == gCrashReporterStateKey)
		{
			if (gCrashReporterState == kCrashReporterStatePaused) {
				task_set_exception_ports(mach_task_self_, EXC_MASK_CRASH_RELATED, gExceptionPort, EXCEPTION_DEFAULT|MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);
				defaultNSExceptionHandler = NSGetUncaughtExceptionHandler();
				NSSetUncaughtExceptionHandler(crashreporter_catch_objc);
				gCrashReporterState = kCrashReporterStateActive;
			}
		}
		else
		{
			JBLogError("crashreporter_resume called with mismatched key: %d (current key: %d)", key, gCrashReporterStateKey);
		}
	}
}


#include <execinfo.h>
void signal_handler(int signo, siginfo_t *info, void *context)
{
	__uint64_t tid = 0;
	pthread_threadid_np(pthread_self(), &tid);

    char *name = NULL;
    FILE *f = crashreporter_open_outfile(gReportName, &name);
    if (f) {
		fprintf(f, "Thread %llu crashed.\n\n", tid);
        
        ucontext_t* ucontext = (ucontext_t*)context;
        fprintf(f, "Signal %s(%d/%d), errno=%d, code=%d, status=%d, addr=%p, value=%p, band=%lx\n\n", strsignal(signo), signo, info->si_signo,
               info->si_errno, info->si_code, info->si_status, info->si_addr, info->si_value.sival_ptr, info->si_band);
        
        fprintf(f, "Register State:\n");
        for(int i = 0; i <= 28; i++) {
            if (i < 10) {
                fprintf(f, " ");
            }
            fprintf(f, " x%d = 0x%016llX", i, ucontext->uc_mcontext->__ss.__x[i]);
            if ((i+1) % (6+1) == 0) {
                fprintf(f, "\n");
            }
            else {
                fprintf(f, ", ");
            }
        }

		arm_thread_state64_t threadState = ucontext->uc_mcontext->__ss;
		arm_thread_state64_t strippedState = threadState;
		__darwin_arm_thread_state64_ptrauth_strip(strippedState);

#ifdef __arm64e__
		uint32_t flags = threadState.__opaque_flags;
		threadState.__opaque_flags |= __DARWIN_ARM_THREAD_STATE64_FLAGS_NO_PTRAUTH;
		threadState.__opaque_flags &= ~(__DARWIN_ARM_THREAD_STATE64_FLAGS_IB_SIGNED_LR|__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_PC|__DARWIN_ARM_THREAD_STATE64_FLAGS_KERNEL_SIGNED_LR);
#else
		uint32_t flags = threadState.__pad;
#endif

		fprintf(f, " lr = 0x%016llX,  pc = 0x%016llX,  sp = 0x%016llX,  fp = 0x%016llX, cpsr= 0x%08X,       flags = 0x%08X\nesr = 0x%08X,         far = 0x%016llX\n\n",
			(uint64_t)__darwin_arm_thread_state64_get_lr(threadState),
			(uint64_t)__darwin_arm_thread_state64_get_pc(threadState),
			(uint64_t)__darwin_arm_thread_state64_get_sp(threadState),
			(uint64_t)__darwin_arm_thread_state64_get_fp(threadState),
			ucontext->uc_mcontext->__ss.__cpsr, flags, 
			ucontext->uc_mcontext->__es.__esr, 
			ucontext->uc_mcontext->__es.__far);

		fprintf(f, "Stripped State:\n");
		fprintf(f, " pc = 0x%016llX,  lr = 0x%016llX,  sp = 0x%016llX,  fp = 0x%016llX\n\n",
			(uint64_t)__darwin_arm_thread_state64_get_pc(strippedState),
			(uint64_t)__darwin_arm_thread_state64_get_lr(strippedState),
			(uint64_t)__darwin_arm_thread_state64_get_sp(strippedState),
			(uint64_t)__darwin_arm_thread_state64_get_fp(strippedState));

        void *callstacks[30] = {0};
        int nptrs = backtrace(callstacks, sizeof(callstacks)/sizeof(callstacks[0]));

        fprintf(f, "Stack trace:\n");
        char** symbols = backtrace_symbols(callstacks, nptrs);
        
        if(symbols != NULL) {
            for(int i = 0; i < nptrs; i++) {
                fprintf(f, "%p\t%s\n", callstacks[i], symbols[i]);
            }
            free(symbols);
        } else {
            printf("no backtrace captured\n");
            return;
        }

        crashreporter_dump_image_list(f);
        
        crashreporter_save_outfile(f);
    }
    
    ABORT("Unexpected signal %d on thread %llu, A detailed report has been written to the file %s.", signo, tid, name ? name : "(null)");
}

int sigcatch[] = {
//SIGQUIT, //->SIG_IGN by launchd in main()
   SIGILL,
   SIGTRAP,
   SIGABRT,
   SIGEMT,
   SIGFPE,
   SIGBUS,
   SIGSEGV,
   SIGSYS
//others ->->SIG_IGN by launchd in main()
};

void crashreporter_start()
{
	char pathbuf[PATH_MAX] = {0};
	uint32_t pathlen = sizeof(pathbuf);
	_NSGetExecutablePath(pathbuf, &pathlen);
	gReportName = strdup(basename(pathbuf));
	
	for(int i=0; i<sizeof(sigcatch)/sizeof(sigcatch[0]); i++) {
		struct sigaction act = {0};
		act.sa_flags = SA_SIGINFO|SA_RESETHAND;
		act.sa_sigaction = signal_handler;
		sigaction(sigcatch[i], &act, NULL);
	}

	if (gCrashReporterState == kCrashReporterStateNotActive) {
		mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &gExceptionPort);
		mach_port_insert_right(mach_task_self_, gExceptionPort, gExceptionPort, MACH_MSG_TYPE_MAKE_SEND);
		pthread_create(&gExceptionThread, NULL, crashreporter_listen, "crashreporter");
		gCrashReporterState = kCrashReporterStatePaused;
		crashreporter_resume(0);
	}
}

