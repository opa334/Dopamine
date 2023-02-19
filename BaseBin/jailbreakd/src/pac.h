#import <Foundation/Foundation.h>

void pac_loop(void);

uint64_t kcall(uint64_t func, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, uint64_t a8);
uint64_t initPACPrimitives(uint64_t kernelAllocation);
void finalizePACPrimitives(void);
void destroyPACPrimitives(void);

uint64_t kalloc(uint64_t size);
uint64_t kfree(uint64_t addr, uint64_t size);