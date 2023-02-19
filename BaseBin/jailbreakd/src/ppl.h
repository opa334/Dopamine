#import <Foundation/Foundation.h>

typedef enum {
	kPPLStatusNotInitialized = 0,
	kPPLStatusInitialized = 1
} PPLStatus;
extern PPLStatus gPPLStatus;

void *mapInRange(uint64_t pageStart, uint32_t pageCount, uint8_t** mappingStart);
void mappingDestroy(void* ctx);

void physreadbuf(uint64_t physaddr, void* output, size_t size);
void physwritebuf(uint64_t physaddr, const void* input, size_t size);

uint64_t physread64(uint64_t pa);
uint64_t physread_ptr(uint64_t va);
uint32_t physread32(uint64_t pa);
uint16_t physread16(uint64_t pa);
uint8_t physread8(uint64_t pa);

void physwrite64(uint64_t pa, uint64_t v);
void physwrite32(uint64_t pa, uint32_t v);
void physwrite16(uint64_t pa, uint16_t v);
void physwrite8(uint64_t pa, uint8_t v);

void kreadbuf(uint64_t kaddr, void* output, size_t size);
void kwritebuf(uint64_t kaddr, const void* input, size_t size);

uint64_t kread64(uint64_t va);
uint64_t kread_ptr(uint64_t va);
uint32_t kread32(uint64_t va);
uint16_t kread16(uint64_t va);
uint8_t kread8(uint64_t va);

void kwrite64(uint64_t va, uint64_t v);
void kwrite32(uint64_t va, uint32_t v);
void kwrite16(uint64_t va, uint16_t v);
void kwrite8(uint64_t va, uint8_t v);

void initPPLPrimitives(uint64_t magicPage);
int handoffPPLPrimitives(pid_t pid, uint64_t *mapOut);