//
//  oobPCI.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//


#ifndef oobPCI_h
#define oobPCI_h

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>

bool oobPCI_init(uint64_t *kBase, uint64_t *virtBase, uint64_t *physBase);

#endif /* oobPCI_h */
