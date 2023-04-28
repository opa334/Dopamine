#define KERNEL_MOUNT_NOAUTH             0x01 /* Don't check the UID of the directory we are mounting on */
#define MNT_RDONLY      0x00000001      /* read only filesystem */

int kernel_unmount(const char *path, uint32_t flags);
uint64_t kernel_mount(const char* fstype, uint64_t pvp, uint64_t vp, const char *mountPath, uint64_t data, size_t datalen, int syscall_flags, uint32_t kern_flags);

uint64_t bindMount(const char *source, const char *target);