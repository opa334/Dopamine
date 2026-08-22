#pragma clang diagnostic push
#pragma ide diagnostic ignored "bugprone-reserved-identifier"

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <unistd.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/event.h>
#include <sys/syscall.h>
#include <libgen.h>

#include "../libjailbreak.h"
#include "unsandbox.h"
#include "common.h"

uint64_t proc_fd_file_glob(uint64_t proc_ptr, int fd)
{
    uint64_t proc_fd = proc_ptr + koffsetof(proc, fd);
    uint64_t ofiles_start = kread_ptr(proc_fd + koffsetof(filedesc, ofiles_start));
    if (!ofiles_start) return 0;
    uint64_t file_proc_ptr = kread_ptr(ofiles_start + (fd * 8));
    if (!file_proc_ptr) return 0;
    return kread_ptr(file_proc_ptr + offsetof(struct fileproc, fp_glob));
}

uint64_t proc_fd_vnode(uint64_t proc_ptr, int fd)
{
    uint64_t file_glob_ptr = proc_fd_file_glob(proc_ptr, fd);
    if (!file_glob_ptr) return 0;
    return kread_ptr(file_glob_ptr + offsetof(struct fileglob, fg_data));
}


static unsigned int crc32tab[256];

void init_crc32(void)
{
    /*
     * the CRC-32 generator polynomial is:
     *   x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^10
     *        + x^8  + x^7  + x^5  + x^4  + x^2  + x + 1
     */
    unsigned int crc32_polynomial = 0x04c11db7;
    unsigned int i, j;

    /*
     * pre-calculate the CRC-32 remainder for each possible octet encoding
     */
    for (i = 0; i < 256; i++) {
        unsigned int crc_rem = i << 24;

        for (j = 0; j < 8; j++) {
            if (crc_rem & 0x80000000) {
                crc_rem = (crc_rem << 1) ^ crc32_polynomial;
            } else {
                crc_rem = (crc_rem << 1);
            }
        }
        crc32tab[i] = crc_rem;
    }
}

unsigned int hash_string(const char *cp, int len)
{
    unsigned hash = 0;

    if (len) {
        while (len--) {
            hash = crc32tab[((hash >> 24) ^ (unsigned char)*cp++)] ^ hash << 8;
        }
    } else {
        while (*cp != '\0') {
            hash = crc32tab[((hash >> 24) ^ (unsigned char)*cp++)] ^ hash << 8;
        }
    }
    /*
     * the crc generator can legitimately generate
     * a 0... however, 0 for us means that we
     * haven't computed a hash, so use 1 instead
     */
    if (hash == 0) {
        hash = 1;
    }
    return hash;
}

int unsandbox(const char* dir, const char* file)
{
    if (@available(iOS 16.4, *)) {
        return unsandbox2(dir, file);
    } else {
        return unsandbox1(dir, file);
    }
}

#pragma clang diagnostic pop