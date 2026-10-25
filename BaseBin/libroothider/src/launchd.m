#import <Foundation/Foundation.h>

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <unistd.h>
#include <libgen.h>
#include <substrate.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <IOKit/IOKitLib.h>

#include <libjailbreak/libjailbreak.h>

extern int new_xpc_pipe_routine_reply(xpc_object_t reply);
extern int (*orig_xpc_pipe_routine_reply)(xpc_object_t reply);
extern xpc_object_t new_xpc_dictionary_create_reply(xpc_object_t original);
extern xpc_object_t (*orig_xpc_dictionary_create_reply)(xpc_object_t original);

mach_port_t startAlternativeJBServer(void(^message_handler)(xpc_object_t))
{
    mach_port_t port = MACH_PORT_NULL;
	mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
	mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND);
	JBLogDebug("Alternative jbserver port: %x", port);

	static dispatch_source_t source; //retain the dispatch source
	dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);
	source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, (uintptr_t)port, 0, queue);
	dispatch_source_set_event_handler(source, ^{
		JBLogDebug("received message from jailbreakd");
		xpc_object_t xdict = NULL;
		int err = xpc_pipe_receive(port, &xdict);
		if(err == 0) {
			message_handler(xdict);
			// xpc_release(xdict);
		}
	});
	dispatch_resume(source);
	return port;
}


struct sysctl_oid {
	struct sysctl_oid_list *  oid_parent;
	SLIST_ENTRY(sysctl_oid) oid_link;
	int             oid_number;
	int             oid_kind;
	void            *oid_arg1;
	int             oid_arg2;
	const char      *oid_name;
	int             (*oid_handler)();
	const char      *oid_fmt;
	const char      *oid_descr; /* offsetof() field / long description */
	int             oid_version;
	int             oid_refcnt;
};

void oid_remove(struct sysctl_oid_list* oid_parent, struct sysctl_oid* oid)
{
    JBLogDebug("oid_remove: %p %p \n", oid_parent, oid);
    uint64_t pnext = UNSIGN_PTR((uint64_t)oid_parent);
    while(true) {
        uint64_t current = kread64(pnext);
        if(!current) break;

        struct sysctl_oid current_oid = {0};
        kreadbuf(current, &current_oid, sizeof(current_oid));

        char name[64]={0};
        kreadbuf((uint64_t)current_oid.oid_name, &name, sizeof(name));
        JBLogDebug("oid_remove: current_oid=%p number=%d name=%s\n", current, current_oid.oid_number, name);
        
        if(current == (uint64_t)oid) {
            uint64_t next = (uint64_t)current_oid.oid_link.sle_next;
            JBLogDebug("oid_remove: found@%p remove %p next->%p\n", pnext-gSystemInfo.kernelConstant.slide, current-gSystemInfo.kernelConstant.slide, next-gSystemInfo.kernelConstant.slide);
            kwrite64(pnext, next);
            break;
        }

        pnext = current + offsetof(struct sysctl_oid, oid_link.sle_next);
    }
}
void oid_insert(struct sysctl_oid_list* oid_parent, struct sysctl_oid* oid)
{
    JBLogDebug("oid_insert: %p %p \n", oid_parent, oid);

    struct sysctl_oid insert_oid = {0};
    kreadbuf((uint64_t)oid, &insert_oid, sizeof(insert_oid));

    uint64_t pnext = UNSIGN_PTR((uint64_t)oid_parent);
    while(true) {
        uint64_t current = kread64(pnext);
        if(!current) {
            JBLogDebug("oid_insert: insert at end %p\n", pnext-gSystemInfo.kernelConstant.slide);
            kwrite64((uint64_t)oid + offsetof(struct sysctl_oid, oid_link.sle_next), 0);
            kwrite64(pnext, (uint64_t)oid);
            break;
        }

        struct sysctl_oid current_oid = {0};
        kreadbuf(current, &current_oid, sizeof(current_oid));

        char name[64]={0};
        kreadbuf((uint64_t)current_oid.oid_name, &name, sizeof(name));
        JBLogDebug("oid_insert: current_oid=%p number=%d name=%s\n", current, current_oid.oid_number, name);
        
        if(insert_oid.oid_number < current_oid.oid_number) {
            JBLogDebug("oid_insert: insert@%p before %p\n", pnext-gSystemInfo.kernelConstant.slide, current-gSystemInfo.kernelConstant.slide);
            kwrite64((uint64_t)oid + offsetof(struct sysctl_oid, oid_link.sle_next), current);
            kwrite64(pnext, (uint64_t)oid);
            break;
        }

        pnext = current + offsetof(struct sysctl_oid, oid_link.sle_next);
    }
}

void hideDeveloperMode()
{
    uint64_t developer_mode_status_oidp = ksymbol(developer_mode_status)-offsetof(struct sysctl_oid,oid_name);
    uint64_t launch_env_logging_oidp = ksymbol(launch_env_logging)-offsetof(struct sysctl_oid,oid_name);

    struct sysctl_oid developer_mode_status={0};
    kreadbuf(developer_mode_status_oidp, &developer_mode_status, sizeof(developer_mode_status));

    struct sysctl_oid launch_env_logging={0};
    kreadbuf(launch_env_logging_oidp, &launch_env_logging, sizeof(launch_env_logging));

    //detach
    oid_remove(developer_mode_status.oid_parent, (struct sysctl_oid*)developer_mode_status_oidp);
    oid_remove(launch_env_logging.oid_parent, (struct sysctl_oid*)launch_env_logging_oidp);

    //reorder
    kwrite32(developer_mode_status_oidp+offsetof(struct sysctl_oid,oid_number), (uint64_t)launch_env_logging.oid_number);
    kwrite32(launch_env_logging_oidp+offsetof(struct sysctl_oid,oid_number), (uint64_t)developer_mode_status.oid_number);

    //exchange data
    kwrite64(developer_mode_status_oidp+offsetof(struct sysctl_oid,oid_name), (uint64_t)launch_env_logging.oid_name);
    kwrite64(launch_env_logging_oidp+offsetof(struct sysctl_oid,oid_name), (uint64_t)developer_mode_status.oid_name);

    kwrite64(developer_mode_status_oidp+offsetof(struct sysctl_oid,oid_descr), (uint64_t)launch_env_logging.oid_descr);
    kwrite64(launch_env_logging_oidp+offsetof(struct sysctl_oid,oid_descr), (uint64_t)developer_mode_status.oid_descr);

    kwrite32(developer_mode_status_oidp+offsetof(struct sysctl_oid,oid_kind), (uint64_t)launch_env_logging.oid_kind);
    kwrite32(launch_env_logging_oidp+offsetof(struct sysctl_oid,oid_kind), (uint64_t)developer_mode_status.oid_kind);

    //attach
    oid_insert(developer_mode_status.oid_parent, (struct sysctl_oid*)developer_mode_status_oidp);
    oid_insert(launch_env_logging.oid_parent, (struct sysctl_oid*)launch_env_logging_oidp);
}

void fix__iosConnect()
{
    MSImageRef IOSurfaceImage = MSGetImageByName("/System/Library/Frameworks/IOSurface.framework/IOSurface");
    JBLogDebug("IOSurfaceImage=%p\n", IOSurfaceImage);
    assert(IOSurfaceImage != NULL);

    io_service_t* __iosService = MSFindSymbol(IOSurfaceImage, "__iosService");
    io_connect_t* __iosConnect = MSFindSymbol(IOSurfaceImage, "__iosConnect");
    assert(__iosService != NULL && __iosConnect != NULL);

    JBLogDebug("__iosService=%p __iosConnect=%p\n", __iosService, __iosConnect);
    JBLogDebug("*__iosService=%d *__iosConnect=%d\n", *__iosService, *__iosConnect);
    
    io_connect_t old__iosConnect = *__iosConnect;

    if(old__iosConnect) {

        assert(*__iosService != 0);

        kern_return_t kr = IOServiceOpen(*__iosService, mach_task_self(), 0, __iosConnect);
        JBLogDebug("IOServiceOpen kr=%x, new iosConnect=%d\n", kr, *__iosConnect);
        assert(kr == KERN_SUCCESS);

        kr = IOServiceClose(old__iosConnect);
        assert(kr == KERN_SUCCESS);
    }
}

int (*orig_bind)(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int new_bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen)
{
    if (addr->sa_family == AF_INET && addrlen >= sizeof(struct sockaddr_in)) {
        struct sockaddr_in addr_in = *(struct sockaddr_in*)addr;
        unsigned int port = ntohs(addr_in.sin_port);
        if (port == 0) {
			int ret = -1;
			for(port=IPPORT_HIFIRSTAUTO; port<=IPPORT_HILASTAUTO; port++)
			{
				addr_in.sin_port = htons(port);
				ret = orig_bind(sockfd, (struct sockaddr*)&addr_in, addrlen);
				if(ret==0 || errno!=EADDRINUSE) {
					break;
				}
			}
			return ret;
        }
    } else if (addr->sa_family == AF_INET6 && addrlen >= sizeof(struct sockaddr_in6)) {
        struct sockaddr_in6 addr_in6 = *(struct sockaddr_in6*)addr;
        unsigned int port = ntohs(addr_in6.sin6_port);
        if (port == 0) {
			int ret = -1;
			for(port=IPPORT_HIFIRSTAUTO; port<=IPPORT_HILASTAUTO; port++)
			{
				addr_in6.sin6_port = htons(port);
				ret = orig_bind(sockfd, (struct sockaddr*)&addr_in6, addrlen);
				if(ret==0 || errno!=EADDRINUSE) {
					break;
				}
			}
			return ret;
        }
    }
    return orig_bind(sockfd, addr, addrlen);
}

NSMutableSet<NSString*>* StoredAppIdentifiers = nil;

void loadAppStoredIdentifiers()
{
    StoredAppIdentifiers = [[NSMutableSet alloc] init];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *applicationsPath = @"/private/var/containers/Bundle/Application/";
    
    NSError *error = nil;
    NSArray *appContainers = [fileManager contentsOfDirectoryAtPath:applicationsPath error:&error];
    if (error) {
        JBLogError("Error reading Application directory: %s", error.description.UTF8String);
        abort();
    }
    
    for (NSString *containerUUID in appContainers) 
    {
        NSString *containerPath = [applicationsPath stringByAppendingPathComponent:containerUUID];

        NSString *metadataPlistPath = [containerPath stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *metadataPlist = [NSDictionary dictionaryWithContentsOfFile:metadataPlistPath];
        NSString *MCMMetadataIdentifier = metadataPlist[@"MCMMetadataIdentifier"];
        if(!MCMMetadataIdentifier) {
            JBLogDebug("Skipping container with no MCMMetadataIdentifier: %s", containerPath.UTF8String);
            continue;
        }

        if([fileManager fileExistsAtPath:[containerPath stringByAppendingPathComponent:@"_TrollStore"]]
            || [fileManager fileExistsAtPath:[containerPath stringByAppendingPathComponent:@"_TrollStoreLite"]])
        {
            JBLogDebug("Skipping trollstored app container: %s : %s", MCMMetadataIdentifier.UTF8String, containerPath.UTF8String);
            continue;
        }

        if(![fileManager fileExistsAtPath:[containerPath stringByAppendingPathComponent:@"iTunesMetadata.plist"]])
        {
            JBLogDebug("Skipping non-stored app container: %s : %s", MCMMetadataIdentifier.UTF8String, containerPath.UTF8String);
            continue;
        }

        NSArray *containerContents = [fileManager contentsOfDirectoryAtPath:containerPath error:nil];
        for (NSString *item in containerContents)
        {
            if ([item hasSuffix:@".app"]) 
            {
                NSString *appPath = [containerPath stringByAppendingPathComponent:item];
                NSString *infoPlistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
                NSString *appBundleID = infoPlist[@"CFBundleIdentifier"];

                if([appBundleID isEqualToString:MCMMetadataIdentifier]==NO) {
                    JBLogDebug("*** Mismatched Bundle ID and MCMMetadataIdentifier: %s != %s : %s", appBundleID.UTF8String, MCMMetadataIdentifier.UTF8String, appPath.UTF8String);
                }
                
                if(![fileManager fileExistsAtPath:[appPath stringByAppendingPathComponent:@"SC_Info"]])
                {
                    JBLogDebug("Skipping non-encrypted app: %s", appPath.UTF8String);
                    continue;
                }

                if (appBundleID) {
                    JBLogDebug("App: %s -> %s", item.UTF8String, appBundleID.UTF8String);
                    [StoredAppIdentifiers addObject:appBundleID];
                } else {
                    JBLogDebug("*** No Bundle ID found: %s", appPath.UTF8String);
                    continue;
                }
                
                NSString *plugInsPath = [appPath stringByAppendingPathComponent:@"PlugIns"];
                if ([fileManager fileExistsAtPath:plugInsPath]) 
                {
                    NSArray *plugIns = [fileManager contentsOfDirectoryAtPath:plugInsPath error:nil];
                    for (NSString *plugIn in plugIns) 
                    {
                        NSString *plugInPath = [plugInsPath stringByAppendingPathComponent:plugIn];
                        NSString *plugInInfoPath = [plugInPath stringByAppendingPathComponent:@"Info.plist"];
                        NSDictionary *plugInInfo = [NSDictionary dictionaryWithContentsOfFile:plugInInfoPath];
                        NSString *plugInBundleID = plugInInfo[@"CFBundleIdentifier"];
                        
                        if (plugInBundleID) {
                            JBLogDebug("  PlugIn: %s -> %s", plugIn.UTF8String, plugInBundleID.UTF8String);
                            [StoredAppIdentifiers addObject:plugInBundleID];
                        } else {
                            JBLogDebug("  *** No Bundle ID found: %s", plugInPath.UTF8String);
                        }
                    }
                }

                NSString *extensionsPath = [appPath stringByAppendingPathComponent:@"Extensions"];
                if ([fileManager fileExistsAtPath:extensionsPath]) 
                {
                    NSArray *extensions = [fileManager contentsOfDirectoryAtPath:extensionsPath error:nil];
                    for (NSString *extension in extensions) 
                    {
                        NSString *extensionPath = [extensionsPath stringByAppendingPathComponent:extension];
                        NSString *extensionInfoPath = [extensionPath stringByAppendingPathComponent:@"Info.plist"];
                        NSDictionary *extensionInfo = [NSDictionary dictionaryWithContentsOfFile:extensionInfoPath];
                        NSString *extensionBundleID = extensionInfo[@"CFBundleIdentifier"];
                        
                        if (extensionBundleID) {
                            JBLogDebug("  Extensions: %s -> %s", extension.UTF8String, extensionBundleID.UTF8String);
                            [StoredAppIdentifiers addObject:extensionBundleID];
                        } else {
                            JBLogDebug("  *** No Bundle ID found: %s", extensionPath.UTF8String);
                        }
                    }
                }
            }
        }
    }
}

void roothider_launchd_postinit(bool firstLoad)
{
    if (__builtin_available(iOS 16.0, *))
    {
        if(firstLoad)
        {
            hideDeveloperMode();
        }

		MSHookFunction(&bind, (void*)new_bind, &orig_bind); //fix network issues on iOS16+
    }

	loadAppStoredIdentifiers();

	MSHookFunction(&xpc_pipe_routine_reply, (void*)new_xpc_pipe_routine_reply, &orig_xpc_pipe_routine_reply);
	MSHookFunction(&xpc_dictionary_create_reply, (void*)new_xpc_dictionary_create_reply, &orig_xpc_dictionary_create_reply);
}
