//
//  misc.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

uint64_t __stack_chk_guard = 0x467567753135;

void __chkstk_darwin(void) {
    // Do nothing
    // *unsafe*
}

void __attribute__((noreturn)) __stack_chk_fail(void) {
    puts("*** STACK CHECK FAILED ***");
    
    exit(-1);
}

void status_update(const char *status) {
    printf("Status: %s\n", status);
}

#undef memcpy
#undef strncpy
#undef strcpy
#undef memset
#undef strlen

#pragma clang optimize off
void* __memcpy_chk(void *dest, const void *src, size_t len, size_t destlen) {
    if (len > destlen) {
        puts("*** __memcpy_chk: OVERFLOW ***");
        
        exit(-1);
    }
    
    return memcpy(dest, src, len);
}

void* memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = (uint8_t*) dst;
    uint8_t *s = (uint8_t*) src;
    
    while (n--) {
        *d++ = *s++;
    }
    
    return dst;
}

char* strncpy(char *dst, const char *src, size_t n) {
    char *d = dst;
    char *s = (char*) src;
    
    while (n-- && *s) {
        *d++ = *s++;
    }
    
    while (n--) {
        *d++ = 0;
    }
    
    return dst;
}

char* __strncpy_chk(char *dst, const char *src, size_t n, size_t dstlen) {
    if (n > dstlen) {
        puts("*** __strncpy_chk: OVERFLOW ***");
        
        exit(-1);
    }
    
    return strncpy(dst, src, n);
}

char* __strcpy_chk(char *dst, const char *src, size_t dstlen) {
    char *d = dst;
    while (*src && dstlen--) {
        *d++ = *src++;
    }
    
    if (!dstlen) {
        puts("*** __strcpy_chk: OVERFLOW ***");
        
        exit(-1);
    }
    
    *d = 0;
    
    return dst;
}

char* strcpy(char *dst, const char *src) {
    return __strcpy_chk(dst, src, -1);
}

size_t strlen(const char *s) {
    size_t res = 0;
    while (*s++) {
        res++;
    }
    
    return res;
}

void* memset(void *ptr, int value, size_t count) {
    uint8_t *buf = ptr;
    
    // Align buf
    while (((uintptr_t) buf & 0x7) && count) {
        *buf = (uint8_t) value;
        buf++;
        count--;
    }
    
    // Construct 64-bit value
    uint64_t value8 = (uint64_t) (uint8_t) value;
    value8 |= (value8 << 8);
    value8 |= (value8 << 16);
    value8 |= (value8 << 32);
    
    // Write in 8-byte steps
    size_t count8 = count & ~0x7ULL;
    for (size_t i = 0; i < count8; i += 8) {
        *(uint64_t*) (buf + i) = value8;
    }
    
    // Write in 1-byte steps
    for (size_t i = count8; i < count; i++) {
        *(uint8_t*) (buf + i) = (uint8_t) value;
    }
    
    return ptr;
}

void * __memset_chk(void *ptr, int value, size_t count, size_t dstlen) {
    if (count > dstlen) {
        puts("*** __memset_chk: OVERFLOW ***");
        
        exit(-1);
    }
    
    return memset(ptr, value, count);
}

int mig_strncpy(char *dst, const char *src, int n) {
    char *d = dst;
    char *s = (char*) src;
    
    while (n-- && *s) {
        *d++ = *s++;
    }
    
    if (!n) {
        d--;
    }
    
    *d++ = 0;
    
    return (int) (d - dst);
}

int mig_strncpy_zerofill(char *dst, const char *src, int n) {
    int count = mig_strncpy(dst, src, n);
    
    n   -= count;
    dst += count;
    
    while (n--) {
        *dst++ = 0;
    }
    
    return count;
}
#pragma clang optimize on
