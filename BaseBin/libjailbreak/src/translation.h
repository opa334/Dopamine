#ifndef TRANSLATION_H
#define TRANSLATION_H

#include <stdint.h>
#include "pte.h"

uint64_t phystokv(uint64_t pa);
uint64_t vtophys_lvl(uint64_t tte_ttep, uint64_t va, uint64_t *leaf_level, uint64_t *leaf_tte_ttep);
uint64_t vtophys(uint64_t tte_ttep, uint64_t va);
uint64_t kvtophys(uint64_t va);
void libjailbreak_translation_init(void);

#endif