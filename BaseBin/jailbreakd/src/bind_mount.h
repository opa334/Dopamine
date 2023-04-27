#define KERNEL_MOUNT_NOAUTH             0x01 /* Don't check the UID of the directory we are mounting on */
#define MNT_RDONLY      0x00000001      /* read only filesystem */

uint64_t bindMount(const char *source, const char *target);