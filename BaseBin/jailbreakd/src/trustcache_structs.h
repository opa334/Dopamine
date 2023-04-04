#import <uuid/uuid.h>
#import <CoreFoundation/CoreFoundation.h>
#import <libjailbreak/csblob.h>

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
	trustcache_entry entries[];
} __attribute__((__packed__)) trustcache_file;

typedef struct sTrustcache_page
{
	uint64_t nextPtr;
	uint64_t selfPtr;
	trustcache_file file;
} __attribute__((__packed__)) trustcache_page;

