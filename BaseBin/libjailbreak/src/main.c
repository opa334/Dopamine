#include "jbclient_xpc.h"
#include <stdlib.h>
#include "physrw.h"
#include "kalloc_pt.h"
#include "primitives_IOSurface.h"
#include "info.h"
#include "translation.h"
#include <xpc/xpc.h>

int jbclient_initialize_primitives(void)
{
	if (getuid() != 0) return -1;

	xpc_object_t xSystemInfo = NULL;
	if (jbclient_root_get_sysinfo(&xSystemInfo) == 0) {
		SYSTEM_INFO_DESERIALIZE(xSystemInfo);
		xpc_release(xSystemInfo);
		if (jbclient_root_get_physrw() == 0) {
			libjailbreak_physrw_init();
			libjailbreak_translation_init();
			libjailbreak_IOSurface_primitives_init();
			if (__builtin_available(iOS 16.0, *)) {
				libjailbreak_kalloc_pt_init();
			}

			/*if (jbinfo(usesPACBypass)) {
				uint64_t stack = 0;
				if (kalloc(&stack, 0x10000) == 0) {
					uint64_t arcContext;
					if (jbclient_root_get_kcall(stack, &arcContext) == 0) {
						// TODO: Init kcall
					}
				}
			}*/

			return 0;
		}
	}

	return -1;
}

// Used for supporting third party legacy software that still calls this function
int jbdInitPPLRW(void)
{
	return jbclient_initialize_primitives();
}
