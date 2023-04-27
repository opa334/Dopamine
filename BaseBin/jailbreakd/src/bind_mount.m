#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import "bind_mount.h"

uint64_t kernel_mount(const char* fstype, uint64_t pvp, uint64_t vp, const char *mountPath, uint64_t data, size_t datalen, int syscall_flags, uint32_t kern_flags)
{
	size_t fstype_len = strlen(fstype) + 1;
	uint64_t kern_fstype = kalloc(fstype_len);
	kwritebuf(kern_fstype, fstype, fstype_len);

	size_t mountPath_len = strlen(mountPath) + 1;
	uint64_t kern_mountPath = kalloc(mountPath_len);
	kwritebuf(kern_mountPath, mountPath, mountPath_len);

	uint64_t kernel_mount_kaddr = bootInfo_getSlidUInt64(@"kernel_mount");
	uint64_t kerncontext_kaddr = bootInfo_getSlidUInt64(@"kerncontext");

	uint64_t ret = kcall(kernel_mount_kaddr, 9, (uint64_t[]){kern_fstype, pvp, vp, kern_mountPath, data, datalen, syscall_flags, kern_flags, kerncontext_kaddr});
	kfree(kern_fstype, fstype_len);
	kfree(kern_mountPath, mountPath_len);

	return ret;
}

uint64_t bindMount(const char *source, const char *target)
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

	uint64_t mount_ret = kernel_mount("bindfs", parent_vnode, vnode, targetPath.fileSystemRepresentation, (uint64_t)targetPath.fileSystemRepresentation, 8, MNT_RDONLY, KERNEL_MOUNT_NOAUTH);
	JBLogDebug("Bind mount: kernel_mount returned %lld (%s)", mount_ret, strerror(mount_ret));
	return mount_ret;
}