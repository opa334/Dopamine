#define CS_CDHASH_LEN 20

typedef enum CS_BLOB_TYPE
{
    CSSLOT_CODEDIRECTORY =   0x0,
    CSSLOT_REQUIREMENTS =     0x2,
    CSSLOT_ENTITLEMENTS =     0x5,
    CSSLOT_DER_ENTITLEMENTS = 0x7,
	CSSLOT_ALTERNATE_CODEDIRECTORIES = 0x1000, /* first alternate CodeDirectory, if any */
	CSSLOT_ALTERNATE_CODEDIRECTORY_MAX = 5,         /* max number of alternate CD slots */
	CSSLOT_ALTERNATE_CODEDIRECTORY_LIMIT = CSSLOT_ALTERNATE_CODEDIRECTORIES + CSSLOT_ALTERNATE_CODEDIRECTORY_MAX, /* one past the last */
    CSSLOT_SIGNATURESLOT =     0x10000
} CS_BLOB_TYPE;

struct CSSuperBlob {
	uint32_t magic;
	uint32_t length;
	uint32_t count;
};

struct CSBlob {
	uint32_t type;
	uint32_t offset;
};

typedef struct __CodeDirectory {
	uint32_t magic;					/* magic number (CSMAGIC_CODEDIRECTORY) */
	uint32_t length;				/* total length of CodeDirectory blob */
	uint32_t version;				/* compatibility version */
	uint32_t flags;					/* setup and mode flags */
	uint32_t hashOffset;			/* offset of hash slot element at 0xindex zero */
	uint32_t identOffset;			/* offset of identifier string */
	uint32_t nSpecialSlots;			/* number of special hash slots */
	uint32_t nCodeSlots;			/* number of ordinary (code) hash slots */
	uint32_t codeLimit;				/* limit to main image signature range */
	uint8_t hashSize;				/* size of each hash in bytes */
	uint8_t hashType;				/* type of hash (cdHashType* constants) */
	uint8_t platform;				/* platform identifier; zero if not platform binary */
	uint8_t	pageSize;				/* log2(page size in bytes); 0 => infinite */
	uint32_t spare2;				/* unused (must be zero) */
	/* Version 0x20100 */
	uint32_t scatterOffset;				/* offset of optional scatter vector */
	/* Version 0x20200 */
	uint32_t teamOffset;				/* offset of optional team identifier */
	/* followed by dynamic content as located by offset fields above */
} CS_CodeDirectory;

// we only care about the first two fields
typedef struct __BlobWrapper {
	uint32_t magic;					/* magic number (CSMAGIC_CODEDIRECTORY) */
	uint32_t length;				/* total length of CodeDirectory blob */
} CS_BlobWrapper;

#define CS_MAGIC_DETACHED_SIGNATURE 0xFADE0CC1
#define CS_MAGIC_EMBEDDED_SIGNATURE 0xFADE0CC0
#define CS_MAGIC_REQUIREMENTS 0xFADE0C01
#define CS_MAGIC_CODEDIRECTORY 0xFADE0C02
#define CS_MAGIC_EMBEDDED_ENTITLEMENTS 0xFADE7171
#define CS_MAGIC_ENTITLEMENTS_DER 0xFADE7172
#define CS_MAGIC_BLOB_WRAPPER 0xFADE0B01

#define CS_HASHTYPE_SHA160_160 1
#define CS_HASHTYPE_SHA256_256 2
#define CS_HASHTYPE_SHA256_160 3
#define CS_HASHTYPE_SHA384_384 4
