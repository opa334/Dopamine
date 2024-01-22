// Used for supporting third party legacy software that still calls this function

#include "jbclient_xpc.h"
#include "physrw.h"
#include "kalloc_pt.h"
#include "primitives_IOSurface.h"

int jbdInitPPLRW(void)
{
	if (jbclient_root_get_physrw() == 0) {
		libjailbreak_physrw_init();
		libjailbreak_IOSurface_primitives_init();
		if (@available(iOS 16.0, *)) {
			libjailbreak_kalloc_pt_init();
		}
		return 0;
	}
	return -1;
}