#ifndef ROOTHIDE_COMPAT_H
#define ROOTHIDE_COMPAT_H

#include <libjailbreak/jbroot.h>

#define jbroot(path) JBROOT_PATH(path)
#define rootfs(path) JBROOT_PATH(path)

#endif
