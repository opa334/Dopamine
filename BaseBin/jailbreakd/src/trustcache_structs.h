#import "machoparse/cdhash.h"
#import <uuid/uuid.h>

// 743 cdhashes fit into one page
#define TC_ENTRY_COUNT_PER_PAGE 743

typedef struct sTrustcache_entry
{
	uint8_t hash[CS_CDHASH_LEN];
	uint8_t hash_type;
	uint8_t flags;
} __attribute__((__packed__)) trustcache_entry;

typedef struct sTrustcache_file
{
	uint32_t version;
	uuid_t uuid;
	uint32_t length;
	trustcache_entry entries[TC_ENTRY_COUNT_PER_PAGE];
} __attribute__((__packed__)) trustcache_file;

typedef struct sTrustcache_page
{
	uint64_t nextPtr;
	uint64_t selfPtr;
	trustcache_file file;
} __attribute__((__packed__)) trustcache_page;

