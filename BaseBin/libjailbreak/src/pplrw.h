#import <Foundation/Foundation.h>

typedef enum {
	kPPLRWStatusNotInitialized = 0,
	kPPLRWStatusInitialized = 1
} PPLRWStatus;
extern PPLRWStatus gPPLRWStatus;

uint64_t va_to_pa(uint64_t table, uint64_t virt, bool *err);
void *mapInVirtual(uint64_t pageStart, uint32_t pageCount, uint8_t** mappingStart);
void mappingDestroy(void* ctx);

int physreadbuf(uint64_t physaddr, void* output, size_t size);
int physwritebuf(uint64_t physaddr, const void* input, size_t size);

uint64_t physread64(uint64_t pa);
uint64_t physread_ptr(uint64_t va);
uint32_t physread32(uint64_t pa);
uint16_t physread16(uint64_t pa);
uint8_t physread8(uint64_t pa);

int physwrite64(uint64_t pa, uint64_t v);
int physwrite32(uint64_t pa, uint32_t v);
int physwrite16(uint64_t pa, uint16_t v);
int physwrite8(uint64_t pa, uint8_t v);

int kreadbuf(uint64_t kaddr, void* output, size_t size);
int kwritebuf(uint64_t kaddr, const void* input, size_t size);

uint64_t kread64(uint64_t va);
uint64_t kread_ptr(uint64_t va);
uint32_t kread32(uint64_t va);
uint16_t kread16(uint64_t va);
uint8_t kread8(uint64_t va);

int kwrite64(uint64_t va, uint64_t v);
int kwrite32(uint64_t va, uint32_t v);
int kwrite16(uint64_t va, uint16_t v);
int kwrite8(uint64_t va, uint8_t v);

void PPLRW_updatePlaceholderPage(uint64_t kaddr);
void initPPLPrimitives(uint64_t magicPage);

