#include "primitives.h"
#include "translation.h"
#include "pte.h"
#include <errno.h>
#include <string.h>

#define min(a,b) (((a)<(b))?(a):(b))
struct kernel_primitives gPrimitives = { 0 };

// Wrappers physical <-> virtual

int _kreadbuf_phys(uint64_t kaddr, void* output, size_t size)
{
	memset(output, 0, size);
	uint64_t va = kaddr;
	uint8_t *data = output;
	size_t sizeLeft = size;

	while (sizeLeft > 0) {
		uint64_t virtPage = va & ~P_PAGE_MASK;
		uint64_t pageOffset = va & P_PAGE_MASK;
		uint64_t readSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

		uint64_t physPage = kvtophys(virtPage);
		if (physPage == 0 && errno != 0) {
			return errno;
		}

		int pr = physreadbuf(physPage + pageOffset, &data[size - sizeLeft], readSize);
		if (pr != 0) {
			return pr;
		}

		va += readSize;
		sizeLeft -= readSize;
	}

	return 0;
}

int _kwritebuf_phys(uint64_t kaddr, const void* input, size_t size)
{
	uint64_t va = kaddr;
	const uint8_t *data = input;
	size_t sizeLeft = size;

	while (sizeLeft > 0) {
		uint64_t virtPage = va & ~P_PAGE_MASK;
		uint64_t pageOffset = va & P_PAGE_MASK;
		uint64_t writeSize = min(sizeLeft, P_PAGE_SIZE - pageOffset);

		uint64_t physPage = kvtophys(virtPage);
		if (physPage == 0 && errno != 0) {
			return errno;
		}

		int pr = physwritebuf(physPage + pageOffset, &data[size - sizeLeft], writeSize);
		if (pr != 0) {
			return pr;
		}

		va += writeSize;
		sizeLeft -= writeSize;
	}

	return 0;
}

int _physreadbuf_virt(uint64_t physaddr, void* output, size_t size)
{
	return 0;
}

int _physwritebuf_virt(uint64_t physaddr, const void* input, size_t size)
{
	return 0;
}

// Wrappers to gPrimitives

int kreadbuf(uint64_t kaddr, void* output, size_t size)
{
	if (gPrimitives.kreadbuf) {
		return gPrimitives.kreadbuf(kaddr, output, size);
	}
	else if (gPrimitives.physreadbuf) {
		return _kreadbuf_phys(kaddr, output, size);
	}
	return -1;
}

int kwritebuf(uint64_t kaddr, const void* input, size_t size)
{
	if (gPrimitives.kwritebuf) {
		return gPrimitives.kwritebuf(kaddr, input, size);
	}
	else if (gPrimitives.physwritebuf) {
		return _kwritebuf_phys(kaddr, input, size);
	}
	return -1;
}

int physreadbuf(uint64_t physaddr, void* output, size_t size)
{
	if (gPrimitives.physreadbuf) {
		return gPrimitives.physreadbuf(physaddr, output, size);
	}
	else if (gPrimitives.kreadbuf) {
		return _physreadbuf_virt(physaddr, output, size);
	}
	return -1;
}

int physwritebuf(uint64_t physaddr, const void* input, size_t size)
{
	if (gPrimitives.physwritebuf) {
		return gPrimitives.physwritebuf(physaddr, input, size);
	}
	else if (gPrimitives.kwritebuf) {
		return _physwritebuf_virt(physaddr, input, size);
	}
	return -1;
}

// Convenience Wrappers

static uint64_t __attribute((naked)) __xpaci(uint64_t a)
{
	asm(".long 0xDAC143E0"); // XPACI X0
	asm("ret");
}

uint64_t unsign_kptr(uint64_t a)
{
	// If a looks like a non-pac'd pointer just return it
	if ((a & 0xFFFFFF0000000000) == 0xFFFFFF0000000000) {
		return a;
	}
	return __xpaci(a);
}

uint64_t physread64(uint64_t pa)
{
	uint64_t v;
	physreadbuf(pa, &v, sizeof(v));
	return v;
}

uint64_t physread_ptr(uint64_t pa)
{
	return unsign_kptr(physread64(pa));
}

uint32_t physread32(uint64_t pa)
{
	uint32_t v;
	physreadbuf(pa, &v, sizeof(v));
	return v;
}

uint16_t physread16(uint64_t pa)
{
	uint16_t v;
	physreadbuf(pa, &v, sizeof(v));
	return v;
}

uint8_t physread8(uint64_t pa)
{
	uint8_t v;
	physreadbuf(pa, &v, sizeof(v));
	return v;
}


int physwrite64(uint64_t pa, uint64_t v)
{
	return physwritebuf(pa, &v, sizeof(v));
}

int physwrite32(uint64_t pa, uint32_t v)
{
	return physwritebuf(pa, &v, sizeof(v));
}

int physwrite16(uint64_t pa, uint16_t v)
{
	return physwritebuf(pa, &v, sizeof(v));
}

int physwrite8(uint64_t pa, uint8_t v)
{
	return physwritebuf(pa, &v, sizeof(v));
}


uint64_t kread64(uint64_t va)
{
	uint64_t v;
	kreadbuf(va, &v, sizeof(v));
	return v;
}

uint64_t kread_ptr(uint64_t va)
{
	return unsign_kptr(kread64(va));
}

uint32_t kread32(uint64_t va)
{
	uint32_t v;
	kreadbuf(va, &v, sizeof(v));
	return v;
}

uint16_t kread16(uint64_t va)
{
	uint16_t v;
	kreadbuf(va, &v, sizeof(v));
	return v;
}

uint8_t kread8(uint64_t va)
{
	uint8_t v;
	kreadbuf(va, &v, sizeof(v));
	return v;
}


int kwrite64(uint64_t va, uint64_t v)
{
	return kwritebuf(va, &v, sizeof(v));
}

int kwrite32(uint64_t va, uint32_t v)
{
	return kwritebuf(va, &v, sizeof(v));
}

int kwrite16(uint64_t va, uint16_t v)
{
	return kwritebuf(va, &v, sizeof(v));
}

int kwrite8(uint64_t va, uint8_t v)
{
	return kwritebuf(va, &v, sizeof(v));
}

int kalloc_with_options(uint64_t *addr, uint64_t size, kalloc_options options)
{
	if (options == KALLOC_OPTION_GLOBAL && gPrimitives.kalloc_global) {
		return gPrimitives.kalloc_global(addr, size);
	}
	else if (options == KALLOC_OPTION_PROCESS && gPrimitives.kalloc_user) {
		return gPrimitives.kalloc_user(addr, size);
	}
	return -1;
}

int kalloc(uint64_t *addr, uint64_t size)
{
	return kalloc_with_options(addr, size, KALLOC_OPTION_GLOBAL);
}

int kfree(uint64_t addr, uint64_t size)
{
	if (gPrimitives.kfree_global) {
		return gPrimitives.kfree_global(addr, size);
	}
	return -1;
}