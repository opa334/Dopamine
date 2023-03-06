#define PTE_NON_GLOBAL      (1 << 11)
#define PTE_VALID           (1 << 10) // Access flag
#define PTE_OUTER_SHAREABLE (2 << 8)
#define PTE_INNER_SHAREABLE (3 << 8)

#define PTE_LEVEL3_ENTRY    PTE_VALID | 0x3

#define KRW_URW_PERM        (0x60000000000040)

#define PTE_RESERVED        (0x3)
#define PTE_REUSEABLE       (0x1)
#define PTE_UNUSED          (0x0)

#define P_PAGE_SIZE 0x4000
#define P_PAGE_MASK 0x3FFF

#define PTE_TO_PERM(pte)  ((((pte) >> 4ULL) & 0xC) | (((pte) >> 52ULL) & 2) | (((pte) >> 54ULL) & 1))
#define _PERM_TO_PTE(perm) ((((perm) & 0xC) << 4ULL) | (((perm) & 2) << 52ULL) | (((perm) & 1) << 54ULL))
#define PERM_TO_PTE(perm) _PERM_TO_PTE((uint64_t) (perm))