#ifndef LIBROOT_CONVERT_H
#define LIBROOT_CONVERT_H

int libroot_convert_rootfs(const char *path, char *fullPathOut, size_t fullPathSize);
int libroot_convert_jbroot(const char *path, char *fullPathOut, size_t fullPathSize);

#endif