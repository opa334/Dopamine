#include <sys/types.h>

typedef int cpu_type_t;
typedef int cpu_subtype_t;

struct mach_header {
	uint32_t	magic;
	cpu_type_t	cputype;
	cpu_subtype_t	cpusubtype;
	uint32_t	filetype;
	uint32_t	ncmds;
	uint32_t	sizeofcmds;
	uint32_t	flags;
};


#define	MH_MAGIC	0xfeedface
#define MH_CIGAM	0xcefaedfe

struct mach_header_64 {
	uint32_t	magic;
	cpu_type_t	cputype;
	cpu_subtype_t	cpusubtype;
	uint32_t	filetype;
	uint32_t	ncmds;
	uint32_t	sizeofcmds;
	uint32_t	flags;
	uint32_t	reserved;
};

#define MH_MAGIC_64 0xfeedfacf
#define MH_CIGAM_64 0xcffaedfe

struct load_command {
	uint32_t cmd;
	uint32_t cmdsize;
};

#define LC_CODE_SIGNATURE 0x1d

struct linkedit_data_command {
	uint32_t	cmd;
	uint32_t	cmdsize;
	uint32_t	dataoff;
	uint32_t	datasize;
};

struct fat_header {
	uint32_t	magic;
	uint32_t	nfat_arch;
};

#define FAT_MAGIC	0xcafebabe
#define FAT_CIGAM	0xbebafeca

struct fat_arch {
	cpu_type_t	cputype;
	cpu_subtype_t	cpusubtype;
	uint32_t	offset;
	uint32_t	size;
	uint32_t	align;
};

#define FAT_MAGIC_64	0xcafebabf
#define FAT_CIGAM_64	0xbfbafeca

struct fat_arch_64 {
	cpu_type_t	cputype;
	cpu_subtype_t	cpusubtype;
	uint32_t	offset;
	uint32_t	size;
	uint32_t	align;
};
