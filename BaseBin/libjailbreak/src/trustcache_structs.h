#ifndef TRUSTCACHE_STRUCTS_H
#define TRUSTCACHE_STRUCTS_H

#include <uuid/uuid.h>
#include <choma/CSBlob.h>
#include <stdint.h>

// TODO: Move to ChOma?
#define CS_CDHASH_LEN 20

typedef uint8_t cdhash_t[CS_CDHASH_LEN];

typedef struct trustcache_entry_v1
{
	cdhash_t hash;
	uint8_t hash_type;
	uint8_t flags;
} __attribute__((__packed__)) trustcache_entry_v1;

typedef struct s_trustcache_file_v1
{
	uint32_t version;
	uuid_t uuid;
	uint32_t length;
	trustcache_entry_v1 entries[];
} __attribute__((__packed__)) trustcache_file_v1;

#define JB_MAGIC 0x424a424a424a424a // "JBJBJBJB"
typedef struct jb_trustcache
{
	// On iOS 15, the trustcache struct has a size of 0x10
	// On iOS 16, it has one of 0x28, we just have to make sure our field is bigger
	uint8_t trustcache[0x40];
	uint64_t magic;
	trustcache_file_v1 file;
} __attribute__((__packed__)) jb_trustcache;

#define JB_TRUSTCACHE_SIZE 0x4000
#define JB_TRUSTCACHE_ENTRY_COUNT ((JB_TRUSTCACHE_SIZE - sizeof(jb_trustcache)) / sizeof(trustcache_entry_v1))

#endif