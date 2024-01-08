#include "translation.h"
#include "primitives.h"
#include "kernel.h"
#include <errno.h>
#include <stdio.h>

// Address translation physical <-> virtual

uint64_t phystokv(uint64_t pa)
{
	const uint64_t PTOV_TABLE_SIZE = 8;
	struct ptov_table_entry {
		uint64_t pa;
		uint64_t va;
		uint64_t len;
	} ptov_table[PTOV_TABLE_SIZE];
	kreadbuf(ksymbol(ptov_table), &ptov_table[0], sizeof(ptov_table));

	for (uint64_t i = 0; (i < PTOV_TABLE_SIZE) && (ptov_table[i].len != 0); i++) {
		if ((pa >= ptov_table[i].pa) && (pa < (ptov_table[i].pa + ptov_table[i].len))) {
			return pa - ptov_table[i].pa + ptov_table[i].va;
		}
	}

	return pa - kconstant(physBase) + kconstant(virtBase);
}

uint64_t vtophys_lvl(uint64_t tte_ttep, uint64_t va, uint64_t *leaf_level, uint64_t *leaf_tte_ttep)
{
	errno = 0;
	const uint64_t ROOT_LEVEL = PMAP_TT_L1_LEVEL;
	const uint64_t LEAF_LEVEL = *leaf_level;

	uint64_t pa = 0;

	bool physical = !(bool)(tte_ttep & 0xf000000000000000);

	for (uint64_t curLevel = ROOT_LEVEL; curLevel <= LEAF_LEVEL; curLevel++) {
		uint64_t offMask, shift, indexMask, validMask, typeMask, typeBlock;
		switch (curLevel) {
			case PMAP_TT_L0_LEVEL: {
				offMask = ARM_16K_TT_L0_OFFMASK;
				shift = ARM_16K_TT_L0_SHIFT;
				indexMask = ARM_16K_TT_L0_INDEX_MASK;
				validMask = ARM_TTE_VALID;
				typeMask = ARM_TTE_TYPE_MASK;
				typeBlock = ARM_TTE_TYPE_BLOCK;
				break;
			}
			case PMAP_TT_L1_LEVEL: {
				offMask = ARM_16K_TT_L1_OFFMASK;
				shift = ARM_16K_TT_L1_SHIFT;
				indexMask = ARM_16K_TT_L1_INDEX_MASK;
				validMask = ARM_TTE_VALID;
				typeMask = ARM_TTE_TYPE_MASK;
				typeBlock = ARM_TTE_TYPE_BLOCK;
				break;
			}
			case PMAP_TT_L2_LEVEL: {
				offMask = ARM_16K_TT_L2_OFFMASK;
				shift = ARM_16K_TT_L2_SHIFT;
				indexMask = ARM_16K_TT_L2_INDEX_MASK;
				validMask = ARM_TTE_VALID;
				typeMask = ARM_TTE_TYPE_MASK;
				typeBlock = ARM_TTE_TYPE_BLOCK;
				break;
			}
			case PMAP_TT_L3_LEVEL: {
				offMask = ARM_16K_TT_L3_OFFMASK;
				shift = ARM_16K_TT_L3_SHIFT;
				indexMask = ARM_16K_TT_L3_INDEX_MASK;
				validMask = ARM_PTE_TYPE_VALID;
				typeMask = ARM_PTE_TYPE_MASK;
				typeBlock = ARM_TTE_TYPE_L3BLOCK;
				break;
			}
			default: {
				errno = 1041;
				return 0;
			}
		}

		uint64_t tteIndex = (va & indexMask) >> shift;
		uint64_t tteEntry = 0;
		if (gPrimitives.physreadbuf && physical) {
			uint64_t tte_pa = tte_ttep + (tteIndex * sizeof(uint64_t));
			tteEntry = physread64(tte_pa);
			if (tteEntry) {
				if (leaf_tte_ttep) *leaf_tte_ttep = tte_pa;
				if (leaf_level) *leaf_level = curLevel;
			}
		}
		else if (gPrimitives.kreadbuf && !physical) {
			uint64_t tte_va = tte_ttep + (tteIndex * sizeof(uint64_t));
			tteEntry = kread64(tte_va);
			if (tteEntry) {
				if (leaf_tte_ttep) *leaf_tte_ttep = tte_va;
				if (leaf_level) *leaf_level = curLevel;
			}
		}
		else {
			errno = 1043;
			return 0;
		}

		//printf("tteEntry: 0x%llx\n", tteEntry);

		if ((tteEntry & validMask) != validMask) {
			errno = 1042;
			return 0;
		}

		if ((tteEntry & typeMask) == typeBlock) {
			pa = ((tteEntry & ARM_TTE_PA_MASK & ~offMask) | (va & offMask));
			break;
		}

		if (physical) {
			tte_ttep = tteEntry & ARM_TTE_TABLE_MASK;
		}
		else {
			tte_ttep = phystokv(tteEntry & ARM_TTE_TABLE_MASK);
		}
	}

	return pa;
}

uint64_t vtophys(uint64_t tte_ttep, uint64_t va)
{
	uint64_t level = PMAP_TT_L3_LEVEL;
	return vtophys_lvl(tte_ttep, va, &level, NULL);
}

uint64_t kvtophys(uint64_t va)
{
	return vtophys(kconstant(cpuTTEP), va);
}