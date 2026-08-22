#include <Foundation/Foundation.h>
#include <unistd.h>
#include <pthread.h>
#include <mach/mach.h>

#include "../libjailbreak.h"
#include "common.h"
#include "ptrace.h"
#include "log.h"

#ifndef __MigPackStructs
#define __MigPackStructs
#endif
#include "mach_exc.h" //mig -arch arm64 -arch arm64e mach_exc.defs

NSLock* trace_data_lock = nil;
NSMutableDictionary* trace_data_record = nil;

typedef struct {
    pid_t pid;
    bool cancelled;
    uint64_t    traced_flag_addr;
    uint64_t    detached_flag_addr;
    mach_port_t           task;
    exception_mask_t       saved_masks[EXC_TYPES_COUNT];
    mach_port_t            saved_ports[EXC_TYPES_COUNT];
    exception_behavior_t   saved_behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t  saved_flavors[EXC_TYPES_COUNT];
    mach_msg_type_number_t saved_exception_types_count;
} trace_data_t;

static void finish_process_trace(trace_data_t* trace_data, bool success)
{
    pid_t pid = trace_data->pid;

    if(!success) {
        //we hosted the exec*ed process so we have to deal with it if patching failed
        /* note: SIGSTOP on PT_DETACH doesn't work on processes
         that was not really paused (PT_ATTACHEXC without exception port set). */
        for (uint32_t i = 0; i < trace_data->saved_exception_types_count; ++i) {
            task_set_exception_ports(trace_data->task, trace_data->saved_masks[i], trace_data->saved_ports[i], trace_data->saved_behaviors[i], trace_data->saved_flavors[i]);
        }
        ptrace(PT_DETACH, pid, NULL, SIGSTOP);
        kill(pid, SIGQUIT); //core dump
        kill(pid, SIGKILL);
    }

    for (uint32_t i = 0; i < trace_data->saved_exception_types_count; ++i) {
        if(MACH_PORT_VALID(trace_data->saved_ports[i])) {
            mach_port_deallocate(mach_task_self(), trace_data->saved_ports[i]);
        }
    }

    [trace_data_record removeObjectForKey:@(pid)];
    free((void*)trace_data);
}

static void* exception_server(void* arg)
{
    mach_port_t port = (mach_port_t)(uintptr_t)arg;

    int bufsize = 4096;
    mach_msg_header_t* msg = (mach_msg_header_t*)malloc(bufsize);
    
	while (true) {
        
        memset(msg, 0, bufsize);
        msg->msgh_size = bufsize;
        mach_msg_return_t ret = mach_msg(msg, MACH_RCV_MSG|MACH_RCV_LARGE, 0, msg->msgh_size, port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);

        if(ret != MACH_MSG_SUCCESS) {
            JBLogError("mach_msg error=%x\n", ret);
            usleep(10*1000);
            continue;
        }

        __Request__mach_exception_raise_t *request = (__Request__mach_exception_raise_t*)msg;

        __Reply__mach_exception_raise_t reply = {0};

        reply.NDR = request->NDR;
        reply.RetCode = KERN_SUCCESS;
        // reply.RetCode = KERN_FAILURE;

        pid_t pid=0;
        kern_return_t kr = pid_for_task(request->task.name, &pid);
        if(kr != KERN_SUCCESS || pid<=0) {
            JBLogError("pid_for_task (task=%x pid=%d) failed: %x, %s\n", request->task.name, pid, kr, mach_error_string(kr));
            continue;
        }

        arm_thread_state64_t threadState={0};
        mach_msg_type_number_t threadStateCount = ARM_THREAD_STATE64_COUNT;
        thread_get_state(request->thread.name, ARM_THREAD_STATE64, (thread_state_t)&threadState, &threadStateCount);

        arm_exception_state64_t exceptionState;
        mach_msg_type_number_t exceptionStateCount = ARM_EXCEPTION_STATE64_COUNT;
        thread_get_state(request->thread.name, ARM_EXCEPTION_STATE64, (thread_state_t)&exceptionState, &exceptionStateCount);
        
        __darwin_arm_thread_state64_ptrauth_strip(threadState);
        uint64_t pc = (uint64_t)__darwin_arm_thread_state64_get_pc(threadState);

        JBLogDebug("pid=%d exception: type=%d ncode=%d code=0x%llX(%lld) subcode=0x%llX(%lld) thread=%x pc=%p\n", pid, request->exception, request->codeCnt, 
            request->code[0], request->code[0], request->code[1], request->code[1],
            request->thread.name, (void*)pc);

        [trace_data_lock lock];
        trace_data_t* trace_data = (trace_data_t*)[[trace_data_record objectForKey:@(pid)] pointerValue];

        if(!trace_data) {
            JBLogError("no trace data for pid=%d, %s\n", pid, proc_get_path(pid,NULL));
        }
        else if (request->exception == EXC_SOFTWARE && request->codeCnt == 2 && request->code[0] == EXC_SOFT_SIGNAL) 
        {
            JBLogDebug("exec* pid=%d cancelled=%d got signal: %d\n", pid, trace_data->cancelled, (int)request->code[1]);

            trace_data->task = request->task.name;

            switch(request->code[1]) {
                case SIGSTOP: {
                    bool data=true;
                    kern_return_t kr = vm_write(request->task.name, trace_data->traced_flag_addr, (mach_vm_address_t)&data, sizeof(data));
                    if(kr != KERN_SUCCESS) {
                        JBLogError("vm_write error: %x, %s\n", kr, mach_error_string(kr));
                        finish_process_trace(trace_data, false);
                        trace_data = NULL;
                        break;
                    }
                    // JBLogDebug("PT_THUPDATE=%d, %d\n", ptrace(PT_THUPDATE, pid, (caddr_t)(uintptr_t)request->thread.name, 0), errno);
                    int ret = ptrace(PT_CONTINUE, pid, (caddr_t)1, 0);
                    if(ret != 0) {
                        JBLogError("PT_CONTINUE error: %d, %s\n", errno, strerror(errno));
                        finish_process_trace(trace_data, false);
                        trace_data = NULL;
                        break;
                    }

                    break;
                }
                
                // Our original task port isn't valid anymore check for a SIGTRAP
                // We got a SIGTRAP which indicates we might have exec'ed and possibly
                // lost our old task port during the exec, so we just need to switch over
                // to using this new task port
                case SIGTRAP: {
                    if(trace_data->cancelled == false)
                    {
                        if(roothide_patch_proc(pid) != 0) {
                            JBLogError("roothide_patch_proc failed for pid=%d, %s\n", pid, proc_get_path(pid,NULL));
                            finish_process_trace(trace_data, false);
                            trace_data = NULL;
                            break;
                        }
                    }
                    else
                    {
                        bool data=true;
                        kern_return_t kr = vm_write(request->task.name, trace_data->detached_flag_addr, (mach_vm_address_t)&data, sizeof(data));
                        if(kr != KERN_SUCCESS) {
                            JBLogError("vm_write error: %x, %s\n", kr, mach_error_string(kr));
                            finish_process_trace(trace_data, false);
                            trace_data = NULL;
                            break;
                        }
                    }

                    bool exception_port_restore_failed = false;
                    for (uint32_t i = 0; i < trace_data->saved_exception_types_count; ++i) {
                        kern_return_t kr = task_set_exception_ports(request->task.name, trace_data->saved_masks[i], 
                                                trace_data->saved_ports[i], trace_data->saved_behaviors[i], trace_data->saved_flavors[i]);
                        if(kr != KERN_SUCCESS) {
                            JBLogError("task_set_exception_ports[%d] error: %x, %s\n", i, kr, mach_error_string(kr));
                            exception_port_restore_failed = true;
                            break;
                        }
                    }

                    if(exception_port_restore_failed) {
                        finish_process_trace(trace_data, false);
                        trace_data = NULL;
                        break;
                    }

                    int ret = ptrace(PT_DETACH, pid, NULL, 0);
                    if(ret != 0) {
                        JBLogError("PT_DETACH error: %d, %s\n", errno, strerror(errno));
                        finish_process_trace(trace_data, false);
                        trace_data = NULL;
                        break;
                    }

                    JBLogDebug("exec* pid=%d patched and resumed\n", pid);
                    finish_process_trace(trace_data, true);
                    trace_data = NULL;
                    break;
                }

                default:
                    JBLogError("unknown signal code: %d from %d,%s\n", (int)request->code[1], pid);
                    break;
            }
        } else {
            JBLogError("unexpected exception type: %d from %d,%s\n", request->exception, pid, proc_get_path(pid,NULL));
        }

        trace_data = NULL;
        [trace_data_lock unlock];

		reply.Head.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(msg->msgh_bits), 0);
		reply.Head.msgh_size = sizeof(__Reply__mach_exception_raise_t);
		reply.Head.msgh_remote_port = msg->msgh_remote_port;
		reply.Head.msgh_local_port = MACH_PORT_NULL;
		reply.Head.msgh_id = msg->msgh_id + 0x64;

		mach_msg(&reply.Head, MACH_SEND_MSG | MACH_MSG_OPTION_NONE, reply.Head.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
	}
}

int execTraceProcess(pid_t pid, uint64_t traced)
{
    static mach_port_t exception_port = MACH_PORT_NULL;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        trace_data_lock = [[NSLock alloc] init];
        trace_data_record = [[NSMutableDictionary alloc] init];

        mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &exception_port);
        mach_port_insert_right(mach_task_self(), exception_port, exception_port, MACH_MSG_TYPE_MAKE_SEND);

        pthread_t thread;
        pthread_create(&thread, NULL, exception_server, (void*)(uintptr_t)exception_port);

        __uint64_t tid = 0;
        pthread_threadid_np(thread, &tid);
        JBLogDebug("exception_server thread: %x tid=%d", thread, tid);
    });

    if(!proc_cantrace(pid)) {
        JBLogError("can't be able to trace process: %d", pid);
        return -1;
    }

    mach_port_t task=MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if(kr != KERN_SUCCESS || !MACH_PORT_VALID(task)) {
        JBLogError("task_for_pid(%d,task=%x) error: %x, %s", pid, task, kr, mach_error_string(kr));
        return -1;
    }

    int ret = 0;
    
    trace_data_t* trace_data = (trace_data_t*)malloc(sizeof(trace_data_t));
    memset(trace_data, 0, sizeof(trace_data_t));
    trace_data->traced_flag_addr = traced;
    trace_data->pid = pid;

    kr = task_get_exception_ports(task, EXC_MASK_SOFTWARE, trace_data->saved_masks, &trace_data->saved_exception_types_count, 
                                            trace_data->saved_ports, trace_data->saved_behaviors, trace_data->saved_flavors);
    if(kr == KERN_SUCCESS) {

        kr = task_set_exception_ports(task, EXC_MASK_SOFTWARE, exception_port, EXCEPTION_DEFAULT|MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);
        if(kr == KERN_SUCCESS) {

            [trace_data_lock lock];

            trace_data_t* existing_trace_data = (trace_data_t*)[[trace_data_record objectForKey:@(pid)] pointerValue];
            if(existing_trace_data) { // pid reused by kernel?
                JBLogError("trace data already exists for pid=%d", pid);
                finish_process_trace(existing_trace_data, true);
                existing_trace_data = NULL;
            }

            [trace_data_record setObject:[NSValue valueWithPointer:trace_data] forKey:@(pid)];

            int ret = ptrace(PT_ATTACHEXC, pid, NULL, 0);
            if(ret != 0) {
                JBLogError("attach error: %d, %s", errno, strerror(errno));
                [trace_data_record removeObjectForKey:@(pid)];
                free(trace_data);
                ret = -1;
            }
            
            [trace_data_lock unlock];
    
        } else {
            JBLogError("task_set_exception_ports error: %x, %s", kr, mach_error_string(kr));
            ret = -1;
        }
    
    } else {
        JBLogError("task_get_exception_ports error: %x, %s", kr, mach_error_string(kr));
        ret = -1;
    }

    mach_port_deallocate(mach_task_self(), task);

    return ret;
}

int execTraceCancel(pid_t pid, uint64_t detached)
{
    int ret = -1;
    [trace_data_lock lock];
    trace_data_t* trace_data = (trace_data_t*)[[trace_data_record objectForKey:@(pid)] pointerValue];
    if(trace_data) {
        trace_data->cancelled = true;
        trace_data->detached_flag_addr = detached;
        ret = kill(pid, SIGTRAP);
    } else {
        JBLogError("no trace data for pid=%d", pid);
    }
    [trace_data_lock unlock];
    return ret;
}