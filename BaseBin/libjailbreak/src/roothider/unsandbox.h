

#define XNU_PTRAUTH_SIGNED_PTR(x)

typedef struct {
    union {
        uint64_t lck_mtx_data;
        uint64_t lck_mtx_tag;
    };
    union {
        struct {
            uint16_t lck_mtx_waiters;
            uint8_t lck_mtx_pri;
            uint8_t lck_mtx_type;
        };
        struct {
            struct _lck_mtx_ext_ *lck_mtx_ptr;
        };
    };
} lck_mtx_t;

LIST_HEAD(buflists, buf);
typedef struct vnode* vnode_t;
typedef uint32_t kauth_action_t;
typedef struct vnode_resolve* vnode_resolve_t;
struct vnode {
    lck_mtx_t v_lock;                       /* vnode mutex */
    TAILQ_ENTRY(vnode) v_freelist;          /* vnode freelist */
    TAILQ_ENTRY(vnode) v_mntvnodes;         /* vnodes for mount point */
    TAILQ_HEAD(, namecache) v_ncchildren;   /* name cache entries that regard us as their parent */
    LIST_HEAD(, namecache) v_nclinks;       /* name cache entries that name this vnode */
    vnode_t  v_defer_reclaimlist;           /* in case we have to defer the reclaim to avoid recursion */
    uint32_t v_listflag;                    /* flags protected by the vnode_list_lock (see below) */
    uint32_t v_flag;                        /* vnode flags (see below) */
    uint16_t v_lflag;                       /* vnode local and named ref flags */
    uint8_t  v_iterblkflags;                /* buf iterator flags */
    uint8_t  v_references;                  /* number of times io_count has been granted */
    int32_t  v_kusecount;                   /* count of in-kernel refs */
    int32_t  v_usecount;                    /* reference count of users */
    int32_t  v_iocount;                     /* iocounters */
    void *   XNU_PTRAUTH_SIGNED_PTR("vnode.v_owner") v_owner; /* act that owns the vnode */
    uint16_t v_type;                        /* vnode type */
    uint16_t v_tag;                         /* type of underlying data */
    uint32_t v_id;                          /* identity of vnode contents */
    union {
        struct mount    * XNU_PTRAUTH_SIGNED_PTR("vnode.v_data") vu_mountedhere;  /* ptr to mounted vfs (VDIR) */
        struct socket   * XNU_PTRAUTH_SIGNED_PTR("vnode.vu_socket") vu_socket;     /* unix ipc (VSOCK) */
        struct specinfo * XNU_PTRAUTH_SIGNED_PTR("vnode.vu_specinfo") vu_specinfo;   /* device (VCHR, VBLK) */
        struct fifoinfo * XNU_PTRAUTH_SIGNED_PTR("vnode.vu_fifoinfo") vu_fifoinfo;   /* fifo (VFIFO) */
        struct ubc_info * XNU_PTRAUTH_SIGNED_PTR("vnode.vu_ubcinfo") vu_ubcinfo;    /* valid for (VREG) */
    } v_un;
    struct  buflists v_cleanblkhd;          /* clean blocklist head */
    struct  buflists v_dirtyblkhd;          /* dirty blocklist head */
    struct klist v_knotes;                  /* knotes attached to this vnode */
    /*
	 * the following 4 fields are protected
	 * by the name_cache_lock held in
	 * excluive mode
	 */
    kauth_cred_t    XNU_PTRAUTH_SIGNED_PTR("vnode.v_cred") v_cred; /* last authorized credential */
    kauth_action_t  v_authorized_actions;   /* current authorized actions for v_cred */
    int             v_cred_timestamp;       /* determine if entry is stale for MNTK_AUTH_OPAQUE */
    int             v_nc_generation;        /* changes when nodes are removed from the name cache */
    /*
     * back to the vnode lock for protection
     */
    int32_t         v_numoutput;            /* num of writes in progress */
    int32_t         v_writecount;           /* reference count of writers */
    uint32_t        v_holdcount;            /* reference to keep vnode from being freed after reclaim */
    const char *v_name;                     /* name component of the vnode */
    vnode_t XNU_PTRAUTH_SIGNED_PTR("vnode.v_parent") v_parent;                       /* pointer to parent vnode */
    struct lockf    *v_lockf;               /* advisory lock list head */
    int(**v_op)(void *);                    /* vnode operations vector */
    mount_t XNU_PTRAUTH_SIGNED_PTR("vnode.v_mount") v_mount;                        /* ptr to vfs we are in */
    void *  v_data;                         /* private data for fs */
//#if CONFIG_MACF
    struct label *v_label;                  /* MAC security label */
//#endif
//#if CONFIG_TRIGGERS
    vnode_resolve_t v_resolve;              /* trigger vnode resolve info (VDIR only) */
//#endif /* CONFIG_TRIGGERS */
#if CONFIG_FIRMLINKS
    vnode_t v_fmlink;                       /* firmlink if set (VDIR only), Points to source
	                                         *  if VFLINKTARGET is set, if  VFLINKTARGET is not
	                                         *  set, points to target */
#endif /* CONFIG_FIRMLINKS */
#if CONFIG_IO_COMPRESSION_STATS
    io_compression_stats_t io_compression_stats;            /* IO compression statistics */
#endif /* CONFIG_IO_COMPRESSION_STATS */

#if CONFIG_IOCOUNT_TRACE
    vnode_iocount_trace_t v_iocount_trace;
#endif /* CONFIG_IOCOUNT_TRACE */

    uint64_t unknown;
};

struct fileproc {
    uint32_t fp_iocount;
    uint32_t fp_vflags;
    uint16_t fp_flags;
    uint16_t fp_guard_attrs;
    uint64_t fp_glob;
    union {
        uint64_t fp_wset;
        uint64_t fp_guard;
    };
};

struct fileglob {
    struct {
        uint64_t le_next;
        uint64_t le_prev;
    } f_msglist;
    uint32_t fg_flag;
    uint32_t fg_count;
    uint32_t fg_msgcount;
    int32_t fg_lflags;
    uint64_t fg_cred;
    uint64_t fg_ops;
    int64_t fg_offset;
    uint64_t fg_data;
    uint64_t fg_vn_data;
    uint64_t fg_lock[2];
};

int unsandbox1(const char* dir, const char* file);
int unsandbox2(const char* dir, const char* file);

void init_crc32(void);
unsigned int hash_string(const char *cp, int len);

uint64_t proc_fd_file_glob(uint64_t proc_ptr, int fd);
uint64_t proc_fd_vnode(uint64_t proc_ptr, int fd);

