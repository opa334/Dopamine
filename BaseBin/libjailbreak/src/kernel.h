#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>

struct system_info {
	struct {
		uint64_t slide;
		uint64_t base;
		uint64_t virtBase;
		uint64_t virtSize;
		uint64_t physBase;
		uint64_t physSize;
		uint64_t cpuTTEP;
		uint64_t exceptionLevel;
		uint64_t pointer_mask;
		uint64_t T1SZ_BOOT;
		uint64_t ARM_TT_L1_INDEX_MASK;
	} kernelConstant;

	struct {
		// Functions
		uint64_t perfmon_dev_open;
		uint64_t vn_kqfilter;
		uint64_t proc_find;
		uint64_t proc_rele;
		uint64_t kalloc_data_external;
		uint64_t kfree_data_external;
		uint64_t ml_sign_thread_state;
		uint64_t pmap_alloc_page_for_kern;
		uint64_t pmap_create_options;
		uint64_t pmap_enter_options_addr;
		uint64_t pmap_mark_page_as_ppl_page;
		uint64_t pmap_nest;
		uint64_t pmap_remove_options;
		uint64_t pmap_set_nested;
		uint64_t hw_lck_ticket_reserve_orig_allow_invalid;
		uint64_t exception_return;

		// Variables
		uint64_t perfmon_devices;
		uint64_t cdevsw;
		uint64_t allproc;
		uint64_t gPhysBase;
		uint64_t gPhysSize;
		uint64_t gVirtBase;
		uint64_t cpu_ttep;
		uint64_t ptov_table;
		uint64_t vm_first_phys;
		uint64_t vm_first_phys_ppnum;
		uint64_t vm_last_phys;
		uint64_t pv_head_table;
		uint64_t pp_attr_table;
		uint64_t vm_page_array_beginning_addr;
		uint64_t vm_page_array_ending_addr;
		uint64_t pmap_image4_trust_caches;
		uint64_t ppl_trust_cache_rt;
	} kernelSymbol;

	struct {
		uint64_t pacda;
		uint64_t hw_lck_ticket_reserve_orig_allow_invalid_signed;
		uint64_t ldp_x0_x1_x8;
		uint64_t br_x22;
		uint64_t exception_return_after_check;
		uint64_t exception_return_after_check_no_restore;
		uint64_t str_x0_x19_ldr_x20;
		uint64_t str_x8_x9;
	} kernelGadget;

	struct {
		struct {
			uint32_t list_next;
			uint32_t list_prev;
			uint32_t task;
			uint32_t pptr;
			uint32_t proc_ro;
			uint32_t svuid;
			uint32_t svgid;
			uint32_t pid;
			uint32_t fd;
			uint32_t flag;
			uint32_t textvp;

			uint32_t ucred;
			uint32_t csflags;
			uint32_t struct_size;
		} proc;

		struct {
			bool exists;
			uint32_t ucred;
			uint32_t csflags;
		} proc_ro;

		struct {
			uint64_t ofiles_start;
		} filedesc;

		struct {
			uint32_t uid;
			uint32_t svuid;
			uint32_t groups;
			uint32_t svgid;
			uint32_t label;
		} ucred;

		struct {
			uint32_t map;
			uint32_t threads;
			uint32_t itk_space;
			uint32_t task_can_transfer_memory_ownership;
		} task;

		struct {
			uint32_t recover;
			uint32_t machine_kstackptr;
			uint32_t machine_CpuDatap;
			uint32_t machine_contextData;
		} thread;

		struct {
			uint32_t table;
			size_t table_entry_size;
		} ipc_space;

		struct {
			uint32_t kobject;
		} ipc_port;

		struct {
			uint32_t hdr;
			uint32_t pmap;
			uint32_t flags;
		} vm_map;

		struct {
			uint32_t links;
			uint32_t nentries;
		} vm_map_header;

		struct {
			uint32_t links;
			uint32_t flags;
		} vm_map_entry;

		struct {
			uint32_t prev;
			uint32_t next;
			uint32_t min;
			uint32_t max;
		} vm_map_links;

		struct {
			uint32_t tte;
			uint32_t ttep;
			uint32_t tt_entry_free;
			uint32_t wx_allowed;
			uint32_t type;
		} pmap;

		struct {
			uint32_t next;
		} tt_free_entry;

		struct {
			uint32_t next;
			uint32_t this;
			uint32_t struct_size;
		} trustcache;
	} kernelStruct;
};

extern struct system_info gSystemInfo;

#define KERNEL_CONSTANTS_ITERATE(ctx, iterator) \
	iterator(ctx, kernelConstant.slide); \
    iterator(ctx, kernelConstant.base); \
    iterator(ctx, kernelConstant.virtBase); \
    iterator(ctx, kernelConstant.virtSize); \
    iterator(ctx, kernelConstant.physBase); \
    iterator(ctx, kernelConstant.physSize); \
    iterator(ctx, kernelConstant.cpuTTEP); \
    iterator(ctx, kernelConstant.exceptionLevel); \
    iterator(ctx, kernelConstant.pointer_mask); \
    iterator(ctx, kernelConstant.T1SZ_BOOT); \
    iterator(ctx, kernelConstant.ARM_TT_L1_INDEX_MASK);

#define KERNEL_SYMBOLS_ITERATE(ctx, iterator) \
    iterator(ctx, kernelSymbol.perfmon_dev_open); \
    iterator(ctx, kernelSymbol.vn_kqfilter); \
    iterator(ctx, kernelSymbol.proc_find); \
    iterator(ctx, kernelSymbol.proc_rele); \
    iterator(ctx, kernelSymbol.kalloc_data_external); \
    iterator(ctx, kernelSymbol.kfree_data_external); \
    iterator(ctx, kernelSymbol.ml_sign_thread_state); \
    iterator(ctx, kernelSymbol.pmap_alloc_page_for_kern); \
    iterator(ctx, kernelSymbol.pmap_create_options); \
    iterator(ctx, kernelSymbol.pmap_enter_options_addr); \
    iterator(ctx, kernelSymbol.pmap_mark_page_as_ppl_page); \
    iterator(ctx, kernelSymbol.pmap_nest); \
    iterator(ctx, kernelSymbol.pmap_remove_options); \
    iterator(ctx, kernelSymbol.pmap_set_nested); \
    iterator(ctx, kernelSymbol.hw_lck_ticket_reserve_orig_allow_invalid); \
    iterator(ctx, kernelSymbol.exception_return); \
	\
    iterator(ctx, kernelSymbol.perfmon_devices); \
    iterator(ctx, kernelSymbol.cdevsw); \
    iterator(ctx, kernelSymbol.allproc); \
    iterator(ctx, kernelSymbol.gPhysBase); \
    iterator(ctx, kernelSymbol.gPhysSize); \
    iterator(ctx, kernelSymbol.gVirtBase); \
    iterator(ctx, kernelSymbol.cpu_ttep); \
    iterator(ctx, kernelSymbol.ptov_table); \
    iterator(ctx, kernelSymbol.vm_first_phys); \
    iterator(ctx, kernelSymbol.vm_first_phys_ppnum); \
    iterator(ctx, kernelSymbol.vm_last_phys); \
    iterator(ctx, kernelSymbol.pv_head_table); \
    iterator(ctx, kernelSymbol.pp_attr_table); \
    iterator(ctx, kernelSymbol.vm_page_array_beginning_addr); \
    iterator(ctx, kernelSymbol.vm_page_array_ending_addr); \
    iterator(ctx, kernelSymbol.pmap_image4_trust_caches); \
    iterator(ctx, kernelSymbol.ppl_trust_cache_rt);

#define KERNEL_GADGETS_ITERATE(ctx, iterator) \
    iterator(ctx, kernelGadget.pacda); \
    iterator(ctx, kernelGadget.hw_lck_ticket_reserve_orig_allow_invalid_signed); \
    iterator(ctx, kernelGadget.ldp_x0_x1_x8); \
    iterator(ctx, kernelGadget.br_x22); \
    iterator(ctx, kernelGadget.exception_return_after_check); \
    iterator(ctx, kernelGadget.exception_return_after_check_no_restore); \
    iterator(ctx, kernelGadget.str_x0_x19_ldr_x20); \
    iterator(ctx, kernelGadget.str_x8_x9);

#define KERNEL_STRUCTS_ITERATE(ctx, iterator) \
    iterator(ctx, kernelStruct.proc.list_next); \
    iterator(ctx, kernelStruct.proc.list_prev); \
    iterator(ctx, kernelStruct.proc.task); \
    iterator(ctx, kernelStruct.proc.pptr); \
    iterator(ctx, kernelStruct.proc.proc_ro); \
    iterator(ctx, kernelStruct.proc.svuid); \
    iterator(ctx, kernelStruct.proc.svgid); \
    iterator(ctx, kernelStruct.proc.pid); \
    iterator(ctx, kernelStruct.proc.fd); \
    iterator(ctx, kernelStruct.proc.flag); \
    iterator(ctx, kernelStruct.proc.textvp); \
    iterator(ctx, kernelStruct.proc.ucred); \
    iterator(ctx, kernelStruct.proc.csflags); \
    iterator(ctx, kernelStruct.proc.struct_size); \
	\
    iterator(ctx, kernelStruct.proc_ro.exists); \
    iterator(ctx, kernelStruct.proc_ro.ucred); \
    iterator(ctx, kernelStruct.proc_ro.csflags); \
	\
    iterator(ctx, kernelStruct.filedesc.ofiles_start); \
	\
    iterator(ctx, kernelStruct.ucred.uid); \
    iterator(ctx, kernelStruct.ucred.svuid); \
    iterator(ctx, kernelStruct.ucred.groups); \
    iterator(ctx, kernelStruct.ucred.svgid); \
    iterator(ctx, kernelStruct.ucred.label); \
	\
    iterator(ctx, kernelStruct.task.map); \
    iterator(ctx, kernelStruct.task.threads); \
    iterator(ctx, kernelStruct.task.itk_space); \
    iterator(ctx, kernelStruct.task.task_can_transfer_memory_ownership); \
	\
    iterator(ctx, kernelStruct.thread.machine_contextData); \
    iterator(ctx, kernelStruct.thread.machine_kstackptr); \
    iterator(ctx, kernelStruct.thread.machine_CpuDatap); \
    iterator(ctx, kernelStruct.thread.machine_contextData); \
	\
    iterator(ctx, kernelStruct.ipc_space.table); \
    iterator(ctx, kernelStruct.ipc_space.table_entry_size); \
	\
    iterator(ctx, kernelStruct.ipc_port.kobject); \
	\
    iterator(ctx, kernelStruct.vm_map.hdr); \
    iterator(ctx, kernelStruct.vm_map.pmap); \
    iterator(ctx, kernelStruct.vm_map.flags); \
	\
    iterator(ctx, kernelStruct.vm_map_header.links); \
    iterator(ctx, kernelStruct.vm_map_header.nentries); \
	\
    iterator(ctx, kernelStruct.vm_map_entry.links); \
    iterator(ctx, kernelStruct.vm_map_entry.flags); \
	\
    iterator(ctx, kernelStruct.vm_map_links.prev); \
    iterator(ctx, kernelStruct.vm_map_links.next); \
    iterator(ctx, kernelStruct.vm_map_links.min); \
    iterator(ctx, kernelStruct.vm_map_links.max); \
	\
    iterator(ctx, kernelStruct.pmap.tte); \
    iterator(ctx, kernelStruct.pmap.ttep); \
    iterator(ctx, kernelStruct.pmap.tt_entry_free); \
    iterator(ctx, kernelStruct.pmap.wx_allowed); \
    iterator(ctx, kernelStruct.pmap.type); \
	\
    iterator(ctx, kernelStruct.tt_free_entry.next); \
	\
    iterator(ctx, kernelStruct.trustcache.next); \
    iterator(ctx, kernelStruct.trustcache.this); \
    iterator(ctx, kernelStruct.trustcache.struct_size);

#define SYSTEM_INFO_ITERATE(ctx, iterator) \
    KERNEL_CONSTANTS_ITERATE(ctx, iterator); \
    KERNEL_SYMBOLS_ITERATE(ctx, iterator); \
    KERNEL_GADGETS_ITERATE(ctx, iterator); \
    KERNEL_STRUCTS_ITERATE(ctx, iterator);

#define SYSTEM_INFO_SERIALIZE_COMPONENT(xdict, name) xpc_dictionary_set_uint64(xdict, #name, gSystemInfo.name)
#define SYSTEM_INFO_SERIALIZE(xdict) SYSTEM_INFO_ITERATE(xdict, SYSTEM_INFO_SERIALIZE_COMPONENT)

#define SYSTEM_INFO_DESERIALIZE_COMPONENT(xdict, name) gSystemInfo.name = xpc_dictionary_get_uint64(xdict, #name)
#define SYSTEM_INFO_DESERIALIZE(xdict) SYSTEM_INFO_ITERATE(xdict, SYSTEM_INFO_DESERIALIZE_COMPONENT)

#define kconstant(name) (gSystemInfo.kernelConstant.name)
#define ksymbol(name) (gSystemInfo.kernelConstant.slide + gSystemInfo.kernelSymbol.name)
#define kgadget(name) (gSystemInfo.kernelConstant.slide + gSystemInfo.kernelGadget.name)
#define koffsetof(structname, member) (gSystemInfo.kernelStruct.structname.member)
#define ksizeof(structname) (gSystemInfo.kernelStruct.structname.struct_size)

uint64_t proc_find(pid_t pidToFind);
uint64_t proc_task(uint64_t proc);
int proc_rele(uint64_t proc);
uint64_t proc_self(void);
uint64_t task_self(void);
uint64_t vm_map_self(void);
uint64_t pmap_self(void);