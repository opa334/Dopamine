#include <stdlib.h>
#include <string.h>

#include <xpf/xpf.h>

extern bool xpf_supported_16up(void);
extern bool xpf_supported_always(void);
extern PFSection *xpf_pfsec_init(const char *filesetEntryId, const char *segName, const char *sectName);

static PFSection *gKernelAMFIDataSection;
static PFSection *gKernelPrelinkDataSection;

XPFSet gNameCacheSet = {
    .name="namecache",
    .supported=xpf_supported_always,
    .metrics={
            "kernelSymbol.nchashtbl",
            "kernelSymbol.nchashmask",
            NULL
    },
};

XPFSet gAMFIOidsSet = {
    .name="amfi_oids",
    .supported=xpf_supported_16up,
    .metrics={
        "kernelSymbol.launch_env_logging",
        "kernelSymbol.developer_mode_status",
        NULL
    },
};

uint64_t xpf_find_namecache(uint32_t n)
{
    static uint64_t nchashtbl = 0;
    static uint64_t nchashmask = 0;
    if (nchashtbl != 0 && nchashmask != 0) {
        if (n == 1) {
            return nchashtbl;
        } else {
            return nchashmask;
        }
    }

    // MOV W?, #0x4C11DB7 in nchinit->(inline)init_crc32
    uint32_t movzAny = 0, movzAnyMask = 0;
    uint32_t movkAny = 0, movkAnyMask = 0;
    arm64_gen_mov_imm('z', ARM64_REG_ANY, OPT_UINT64(0x1db7), OPT_UINT64_NONE, &movzAny, &movzAnyMask);
    arm64_gen_mov_imm('k', ARM64_REG_ANY, OPT_UINT64(0x4c1), OPT_UINT64(16), &movkAny, &movkAnyMask);
    uint32_t crcFlagInst[] = {
            movzAny,
            movkAny,
    };
    uint32_t crcFlagMask[] = {
            movzAnyMask,
            movkAnyMask,
    };

    __block uint64_t crcFlag = 0;
    PFPatternMetric *metric = pfmetric_pattern_init(crcFlagInst, crcFlagMask, sizeof(crcFlagInst), sizeof(uint32_t));
    pfmetric_run(gXPF.kernelTextSection, metric, ^(uint64_t vmaddr, bool *stop) {
        crcFlag = vmaddr;
        *stop = true;
    });
    pfmetric_free(metric);

	if(!crcFlag) {
		xpf_set_error("Failed to find crcFlag");
		return 0;
	}

    // BL _hashinit BD 2D 0B 94
    uint32_t blAnyInst = 0, blAnyMask = 0;
    arm64_gen_b_l(OPT_BOOL(true), OPT_UINT64_NONE, OPT_UINT64_NONE, &blAnyInst, &blAnyMask);
    uint64_t bl_hashinit = 0;
    bl_hashinit = pfsec_find_next_inst(gXPF.kernelTextSection, crcFlag, 100, blAnyInst, blAnyMask);

    // nchashtbl = hashinit(MAX(CONFIG_NC_HASH, (2 * desiredNodes)), M_CACHE, &nchash);
    // nchashmask = nchash;
    // nchash++;

    uint32_t adrpAnyInst = 0, adrpAnyMask = 0;
    uint32_t strAnyInst = 0, strAnyMask = 0;
    arm64_gen_adr_p(OPT_BOOL(true), OPT_UINT64_NONE, OPT_UINT64_NONE, ARM64_REG_ANY, &adrpAnyInst, &adrpAnyMask);
    arm64_gen_str_imm(0, LDR_STR_TYPE_ANY, ARM64_REG_ANY, ARM64_REG_ANY, OPT_UINT64_NONE, &strAnyInst, &strAnyMask);
    uint32_t hashinitInst[] = {
            adrpAnyInst,
            strAnyInst,
    };
    uint32_t hashinitMask[] = {
            adrpAnyMask,
            strAnyMask,
    };

    metric = pfmetric_pattern_init(hashinitInst, hashinitMask, sizeof(hashinitInst), sizeof(uint32_t));
    pfmetric_run_in_range(gXPF.kernelTextSection, bl_hashinit, bl_hashinit + 20 * 0x4, metric,
                          ^(uint64_t vmaddr, bool *stop) {
                              uint64_t adrp_value = 0, str_value = 0;
                              arm64_dec_adr_p(pfsec_read32(gXPF.kernelTextSection, vmaddr), vmaddr, &adrp_value, NULL,
                                              NULL);
                              arm64_dec_str_imm(pfsec_read32(gXPF.kernelTextSection, vmaddr + 0x4), NULL, NULL,
                                                &str_value, NULL, NULL);
                              if (nchashtbl == 0) {
                                  nchashtbl = adrp_value + str_value;
                              } else if (nchashmask == 0) {
                                  nchashmask = adrp_value + str_value;
                                  *stop = true;
                                  if (nchashtbl != nchashmask - 8) {
                                      nchashtbl = -1;
                                      nchashmask = -1;
                                  }
                              }
                          });
    pfmetric_free(metric);

	if(!nchashtbl || !nchashmask)  {
		xpf_set_error("Failed to find nchash");
		return 0;
	}

    if (n == 1) {
        return nchashtbl;
    } else {
        return nchashmask;
    }
}

uint64_t xpf_find_amfi_oid(int index)
{
	const char* oid_name = NULL;
	const char* oid_descr = NULL;

	if(index==2) {
		oid_name = "developer_mode_status";
		oid_descr = "developer mode status";
	} else if(index==1) {
		oid_name = "launch_env_logging";
		oid_descr = "launch environment logging";
	} else {
		abort();
	}

	PFSection *dataSec = (gKernelAMFIDataSection ?: gXPF.kernelDataSection);
	PFSection *stringSec = (gXPF.kernelAMFIStringSection ?: gXPF.kernelStringSection);
	if (!gXPF.kernelIsArm64e && !gXPF.kernelIsFileset) {
		dataSec = gKernelPrelinkDataSection;
		stringSec = gXPF.kernelPrelinkTextSection;
	}

	__block uint64_t oid_descr_addr = 0;
	PFStringMetric* oid_descr_metric = pfmetric_string_init(oid_descr);
	pfmetric_run(stringSec, oid_descr_metric, ^(uint64_t vmaddr, bool *stop) {
		oid_descr_addr = vmaddr;
		*stop = true;
	});
	pfmetric_free(oid_descr_metric);

	if(!oid_descr_addr) {
		xpf_set_error("Failed to find oid_descr_addr");
		return 0;
	}

	__block uint64_t oid_descr_ptr = 0;
	PFXrefMetric *oid_descr_ptr_metric = pfmetric_xref_init(oid_descr_addr, XREF_TYPE_MASK_POINTER);
	pfmetric_run(dataSec, oid_descr_ptr_metric, ^(uint64_t vmaddr, bool *stop) {
		oid_descr_ptr = vmaddr;
		*stop = true;
	});
	pfmetric_free(oid_descr_ptr_metric);

	if(!oid_descr_ptr)  {
		xpf_set_error("Failed to find oid_descr_ptr");
		return 0;
	}

	uint64_t oid_name_ptr = oid_descr_ptr - 0x18;
	
	uint64_t oid_name_addr = pfsec_read_pointer(dataSec, oid_name_ptr);
	if(!oid_name_addr) {
		xpf_set_error("invalid oid_name_ptr");
		return 0;
	}

	char* oid_name_string = NULL;
	int r = pfsec_read_string(stringSec, oid_name_addr, &oid_name_string);
	if(!oid_name_string || strcmp(oid_name_string, oid_name) != 0) {
		xpf_set_error("Mismatch oid_name and oid_descr");
		return 0;
	}

	return oid_name_ptr;
}

// Call once after xpf_construct_offset_dictionary(), before xpf_stop().
// Keep "namecache" and "amfi_oids" out of that function's sets array.
int roothide_xpf_append_roothide_offsets(xpc_object_t xdict)
{
	if (!xdict || xpc_get_type(xdict) != XPC_TYPE_DICTIONARY ||
		!gXPF.kernel || !gXPF.kernelTextSection || !gXPF.darwinVersion) {
		xpf_set_error("Invalid roothide XPF context or offset dictionary");
		return -1;
	}

	int r = -1;

	if (gXPF.kernelIsFileset) {
		gKernelAMFIDataSection = xpf_pfsec_init("com.apple.driver.AppleMobileFileIntegrity", "__DATA", "__data");
	}
	else {
		gKernelPrelinkDataSection = xpf_pfsec_init(NULL, "__PRELINK_DATA", "__data");
	}

	if (gAMFIOidsSet.supported()) {
		PFSection *dataSec = (gKernelAMFIDataSection ?: gXPF.kernelDataSection);
		PFSection *stringSec = (gXPF.kernelAMFIStringSection ?: gXPF.kernelStringSection);
		if (!gXPF.kernelIsArm64e && !gXPF.kernelIsFileset) {
			dataSec = gKernelPrelinkDataSection;
			stringSec = gXPF.kernelPrelinkTextSection;
		}
		if (!dataSec || !stringSec) {
			xpf_set_error("Missing AMFI data or string section");
			goto out;
		}
	}

	xpf_item_register("kernelSymbol.launch_env_logging", xpf_find_amfi_oid, (void *)(uintptr_t)1);
	xpf_item_register("kernelSymbol.developer_mode_status", xpf_find_amfi_oid, (void *)(uintptr_t)2);

	xpf_item_register("kernelSymbol.nchashtbl", xpf_find_namecache, (void *)(uintptr_t)1);
	xpf_item_register("kernelSymbol.nchashmask", xpf_find_namecache, (void *)(uintptr_t)2);

	r = xpf_offset_dictionary_add_set(xdict, &gNameCacheSet);
	if (r == 0 && gAMFIOidsSet.supported()) {
		r = xpf_offset_dictionary_add_set(xdict, &gAMFIOidsSet);
	}

out:
	if (gKernelAMFIDataSection) {
		pfsec_free(gKernelAMFIDataSection);
		gKernelAMFIDataSection = NULL;
	}
	if (gKernelPrelinkDataSection) {
		pfsec_free(gKernelPrelinkDataSection);
		gKernelPrelinkDataSection = NULL;
	}
	return r;
}

xpc_object_t roothide_xpf_construct_offset_dictionary_wrapper(const char *sets[])
{
	xpc_object_t xdict = xpf_construct_offset_dictionary(sets);
	if (!xdict) return NULL;
	if (roothide_xpf_append_roothide_offsets(xdict) != 0) {
		// xpc_release(xdict);
		return NULL;
	}
	return xdict;
}

