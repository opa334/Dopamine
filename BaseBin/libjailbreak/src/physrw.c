#include "physrw.h"
#include "primitives.h"
#include "kernel.h"
#include "translation.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *physrw_phystouaddr(uint64_t pa)
{
	errno = 0;

	uint64_t physBase = kconstant(physBase), physSize = kconstant(physSize);
	bool doBoundaryCheck = (physBase != 0 && physSize != 0);
	if (doBoundaryCheck) {
		if (pa < physBase || pa >= (physBase + physSize)) {
			errno = 1030;
			return 0;
		}
	}

	return (void *)(pa + PPLRW_USER_MAPPING_OFFSET);
}

void *physrw_kvtouaddr(uint64_t va)
{
	uint64_t pa = kvtophys(va);
	if (!pa) return 0;
	return physrw_phystouaddr(pa);
}

int physrw_physreadbuf(uint64_t pa, void* output, size_t size)
{
	void *uaddr = physrw_phystouaddr(pa);
	if (!uaddr && errno != 0) {
		memset(output, 0x0, size);
		return errno;
	}

	asm volatile("dmb sy");
	memcpy(output, uaddr, size);
	return 0;
}

int physrw_physwritebuf(uint64_t pa, const void* input, size_t size)
{
	void *uaddr = physrw_phystouaddr(pa);
	if (!uaddr && errno != 0) {
		return errno;
	}

	memcpy(uaddr, input, size);
	asm volatile("dmb sy");
	return 0;
}

int physrw_init(void)
{
	gPrimitives.physreadbuf = physrw_physreadbuf;
	gPrimitives.physwritebuf = physrw_physwritebuf;
	return 0;
}