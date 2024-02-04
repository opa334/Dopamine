#include "paths.h"
#include <stddef.h>
#include <stdint.h>
#include <string.h>

int libroot_convert_rootfs(const char *path, char *fullPathOut, size_t fullPathSize)
{
	if (!fullPathOut || fullPathSize == 0) return -1;

	const char *prefix = libroot_get_root_prefix();
	const char *jbRootPrefix = libroot_get_jbroot_prefix();
	size_t jbRootPrefixLen = strlen(jbRootPrefix);

	if (path[0] == '/') {
		// This function has two different purposes
		// If what we have is a subpath of the jailbreak root, strip the jailbreak root prefix
		// Else, add the rootfs prefix
		if (!strncmp(path, jbRootPrefix, jbRootPrefixLen)) {
			strlcpy(fullPathOut, &path[jbRootPrefixLen], fullPathSize);
		}
		else {
			strlcpy(fullPathOut, prefix, fullPathSize);
			strlcat(fullPathOut, path, fullPathSize);
		}
	}
	else {
		// Don't modify relative paths
		strlcpy(fullPathOut, path, fullPathSize);
	}

	return 0;
}

int libroot_convert_jbroot(const char *path, char *fullPathOut, size_t fullPathSize)
{
	if (!fullPathOut || fullPathSize == 0) return -1;

	const char *prefix = libroot_get_jbroot_prefix();

	if (path[0] == '/') {
		strlcpy(fullPathOut, prefix, fullPathSize);
		strlcat(fullPathOut, path, fullPathSize);
	}
	else {
		// Don't modify relative paths
		strlcpy(fullPathOut, path, fullPathSize);
	}

	return 0;
}
