#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/launchd.h>
#import "bind_mount.h"
#import <sys/param.h>
#import <sys/mount.h>

int kernel_mount(const char* fstype, uint64_t pvp, uint64_t vp, const char *mountPath, uint64_t data, size_t datalen, int syscall_flags, uint32_t kern_flags)
{
	size_t fstype_len = strlen(fstype) + 1;
	uint64_t kern_fstype = kalloc(fstype_len);
	kwritebuf(kern_fstype, fstype, fstype_len);

	size_t mountPath_len = strlen(mountPath) + 1;
	uint64_t kern_mountPath = kalloc(mountPath_len);
	kwritebuf(kern_mountPath, mountPath, mountPath_len);

	uint64_t kernel_mount_kaddr = bootInfo_getSlidUInt64(@"kernel_mount");
	uint64_t kerncontext_kaddr = bootInfo_getSlidUInt64(@"kerncontext");

	int ret = (int)kcall(kernel_mount_kaddr, 9, (uint64_t[]){kern_fstype, pvp, vp, kern_mountPath, data, datalen, syscall_flags, kern_flags, kerncontext_kaddr});
	kfree(kern_fstype, fstype_len);
	kfree(kern_mountPath, mountPath_len);

	return ret;
}

struct __attribute__((__packed__)) unmount_args {
    const char *path;
	uint32_t flags;
};

/*int kernel_unmount(const char *path, uint32_t flags)
{
	int fd = open(path, O_RDONLY);
	if (fd < 0) return -1;
	uint64_t vnode = proc_get_vnode_by_file_descriptor(self_proc(), fd);
	close(fd);

	uint64_t mp = vnode_get_mount(vnode);
	NSLog(@"/usr/lib mp: %llX\n", mp);

	int fd2 = open("/usr", O_RDONLY);
	if (fd2 < 0) return -1;
	uint64_t vnode2 = proc_get_vnode_by_file_descriptor(self_proc(), fd2);
	close(fd2);
	uint64_t mp2 = vnode_get_mount(vnode2);
	NSLog(@"/usr mp: %llX\n", mp2);


	int fd3 = open("/usr/lib/dyld", O_RDONLY);
	if (fd3 < 0) return -1;
	uint64_t vnode3 = proc_get_vnode_by_file_descriptor(self_proc(), fd3);
	close(fd3);
	uint64_t mp3 = vnode_get_mount(vnode3);
	NSLog(@"/usr/lib/dyld mp: %llX\n", mp3);


	uint32_t refcnt = kread32(mp + 0x10);
	kwrite32(mp + 0x10, refcnt + 1);

	uint64_t safedounmount_kaddr = bootInfo_getSlidUInt64(@"safedounmount");
	uint64_t kerncontext_kaddr = bootInfo_getSlidUInt64(@"kerncontext");

	NSLog(@"safedounmount(%llX, %llX, %llX)", mp, (uint64_t)flags, kerncontext_kaddr);
	return 0;

	//return (int)kcall(safedounmount_kaddr, 3, (uint64_t[]){mp, (uint64_t)flags, kerncontext_kaddr});
}*/

int launchd_unmount(const char *path, uint32_t flags) {
	xpc_object_t msg = xpc_dictionary_create_empty();
	xpc_dictionary_set_bool(msg, "jailbreak", true);
	xpc_dictionary_set_uint64(msg, "id", LAUNCHD_JB_MSG_UNMOUNT);
	xpc_dictionary_set_string(msg, "path", path);
	xpc_dictionary_set_uint64(msg, "flags", flags);
	xpc_object_t reply = launchd_xpc_send_message(msg);

	if (!reply) return -10;

	return (int)xpc_dictionary_get_int64(reply, "result");
}

int bindMount(const char *source, const char *target)
{
	NSString *sourcePath = [[NSString stringWithUTF8String:source] stringByResolvingSymlinksInPath];
	NSString *targetPath = [[NSString stringWithUTF8String:target] stringByResolvingSymlinksInPath];

	int fd = open(sourcePath.fileSystemRepresentation, O_RDONLY);
	if (fd < 0) {
		JBLogError("Bind mount: Failed to open %s", sourcePath.UTF8String);
		return 1;
	}

	uint64_t vnode = proc_get_vnode_by_file_descriptor(self_proc(), fd);
	JBLogDebug("Bind mount: Got vnode 0x%llX for path \"%s\"", vnode, sourcePath.fileSystemRepresentation);

	uint64_t parent_vnode = kread_ptr(vnode + 0xC0);
	JBLogDebug("Bind mount: Got parent vnode: 0x%llX", parent_vnode);

	int mount_ret = (int)kernel_mount("bindfs", parent_vnode, vnode, targetPath.fileSystemRepresentation, (uint64_t)targetPath.fileSystemRepresentation, 8, MNT_RDONLY, KERNEL_MOUNT_NOAUTH);
	JBLogDebug("Bind mount: kernel_mount returned %d (%s)", mount_ret, strerror(mount_ret));
	return mount_ret;
}

int mountFakeLibBindMount(void)
{
	if (isFakeLibBindMountActive()) return 0;
	NSString *fakeLibPath = prebootPath(@"basebin/.fakelib");
	NSString *libPath = @"/usr/lib";
	return bindMount(libPath.fileSystemRepresentation, fakeLibPath.fileSystemRepresentation);
}

int unmountFakeLibBindMount(void)
{
	if (!isFakeLibBindMountActive()) return 0;
	//NSString *fakeLibPath = prebootPath(@"basebin/.fakelib");
	int ret = launchd_unmount("/usr/lib", 0);
	NSLog(@"launchd_unmount: %d", ret);
	return ret;
	//return kernel_unmount("/usr/lib", MNT_FORCE);
}