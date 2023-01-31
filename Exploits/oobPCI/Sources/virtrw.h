#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>

uint64_t (^kread64)(uint64_t kaddr);
uint32_t (^kread32)(uint64_t kaddr);

void (^kwrite64)(uint64_t kaddr, uint64_t val);
void (^kwrite32)(uint64_t kaddr, uint32_t val);

void kreadbuf(uint64_t kaddr, void* output, size_t size);
void kwritebuf(uint64_t kaddr, void* input, size_t size);

uint16_t kread16(uint64_t kaddr);
uint8_t kread8(uint64_t kaddr);

void kwrite16(uint64_t kaddr, uint16_t val);
void kwrite8(uint64_t kaddr, uint8_t val);

uint64_t kread_ptr(uint64_t kaddr);
