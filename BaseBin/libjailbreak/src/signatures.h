#ifndef SIGNATURES_H
#define SIGNATURES_H

#include <choma/CodeDirectory.h>

typedef uint8_t cdhash_t[CS_CDHASH_LEN];
void macho_collect_untrusted_cdhashes(const char *path, const char *callerPath, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut);

#endif