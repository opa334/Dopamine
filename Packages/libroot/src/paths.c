#include <libjailbreak/jbclient_xpc.h>

const char *libroot_get_root_prefix(void)
{
	return "";
}

const char *libroot_get_jbroot_prefix(void)
{
	return jbclient_get_jbroot();
}

const char *libroot_get_boot_uuid(void)
{
	return jbclient_get_boot_uuid();
}
