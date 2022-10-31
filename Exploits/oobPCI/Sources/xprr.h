//
//  xprr.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef xprr_h
#define xprr_h

#define PTE_TO_PERM(pte)  ((((pte) >> 4ULL) & 0xC) | (((pte) >> 52ULL) & 2) | (((pte) >> 54ULL) & 1))
#define _PERM_TO_PTE(perm) ((((perm) & 0xC) << 4ULL) | (((perm) & 2) << 52ULL) | (((perm) & 1) << 54ULL))
#define PERM_TO_PTE(perm) _PERM_TO_PTE((uint64_t) (perm))

#define PERM_KRW_URW 0x7 // R/W for kernel and user

#define PTE_NON_GLOBAL      (1ULL << 11ULL)
#define PTE_VALID           (1ULL << 10ULL) // Access flag
#define PTE_OUTER_SHAREABLE (2ULL << 8ULL)
#define PTE_INNER_SHAREABLE (3ULL << 8ULL)

#define PTE_LEVEL3_ENTRY (PTE_VALID | 0x3ULL)

#endif /* xprr_h */
