struct proc_bsdinfo {
	uint32_t                pbi_flags;              /* 64bit; emulated etc */
	uint32_t                pbi_status;
	uint32_t                pbi_xstatus;
	uint32_t                pbi_pid;
	uint32_t                pbi_ppid;
	uid_t                   pbi_uid;
	gid_t                   pbi_gid;
	uid_t                   pbi_ruid;
	gid_t                   pbi_rgid;
	uid_t                   pbi_svuid;
	gid_t                   pbi_svgid;
	uint32_t                rfu_1;                  /* reserved */
	char                    pbi_comm[MAXCOMLEN];
	char                    pbi_name[2 * MAXCOMLEN];  /* empty if no name is registered */
	uint32_t                pbi_nfiles;
	uint32_t                pbi_pgid;
	uint32_t                pbi_pjobc;
	uint32_t                e_tdev;                 /* controlling tty dev */
	uint32_t                e_tpgid;                /* tty process group id */
	int32_t                 pbi_nice;
	uint64_t                pbi_start_tvsec;
	uint64_t                pbi_start_tvusec;
};

#define PROC_PIDTBSDINFO                3
#define PROC_PIDTBSDINFO_SIZE           (sizeof(struct proc_bsdinfo))