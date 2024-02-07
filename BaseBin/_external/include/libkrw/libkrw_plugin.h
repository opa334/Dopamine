#ifndef LIBKRW_PLUGIN_H
#define LIBKRW_PLUGIN_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

/**
 * libkrw - Library for kernel read/write
 *
 * The purpose of this library is to provide a standard interface for common
 * kernel memory operations. Subsets of those have historically been exported
 * by most jailbreaks, but the provided interfaces are increasingly shifting,
 * thus calling for a standard interface.
 *
 * It is understood that hardly any jailbreak provides the necessary primitives
 * to implement ALL of the below functions. Thus, an implementer of this API
 * is free to implement any subset of their choosing, even an empty one, and
 * simply "stub" the remaining functions to return `ENOTSUP` unconditionally.
 *
 * All functions imported by this library are expected to return an `int` status
 * code, where:
 * - The value `0` indicates success.
 * - The values `1` through `255` indicate failure and correspond to their
 *   definitions in <errno.h> (or are reserved, if no such definition exists).
 * - All other return values are implementation-defined, but indicate failure.
 *
 * Notable conditions where values from <errno.h> should be used include:
 * - `EPERM`    The requested operation requires root, an entitlement, or some
 *              other form of elevated privileges.
 * - `EINVAL`   An invalid argument was provided to the function.
 * - `EDEVERR`  The requested operation is supported in this implementation, but
 *              could not be completed for some reason.
 * - `ENOTSUP`  The requested operation is not supported in this implementation.
 *
 * Further shall be noted that due to the inherently unsafe nature of direct
 * kernel memory accesses, functions that take kernel addresses as arguments
 * from the caller may panic the kernel, and implementers of this interface may
 * choose to defend against that, but are not expected to do so. They ARE
 * however expected to defend against causing kernel panics in functions that do
 * NOT take kernel addresses as arguments.
**/

typedef int (*krw_kbase_func_t)(uint64_t *addr);
typedef int (*krw_kread_func_t)(uint64_t from, void *to, size_t len);
typedef int (*krw_kwrite_func_t)(void *from, uint64_t to, size_t len);
typedef int (*krw_kmalloc_func_t)(uint64_t *addr, size_t size);
typedef int (*krw_kdealloc_func_t)(uint64_t addr, size_t size);
typedef int (*krw_kcall_func_t)(uint64_t func, size_t argc, const uint64_t *argv, uint64_t *ret);
typedef int (*krw_physread_func_t)(uint64_t from, void *to, size_t len, uint8_t granule);
typedef int (*krw_physwrite_func_t)(void *from, uint64_t to, size_t len, uint8_t granule);

// This struct must only be extended so that old plugins can still load
#define LIBKRW_HANDLERS_VERSION 0
struct krw_handlers_s {
    uint64_t version;
    krw_kbase_func_t kbase;
    krw_kread_func_t kread;
    krw_kwrite_func_t kwrite;
    krw_kmalloc_func_t kmalloc;
    krw_kdealloc_func_t kdealloc;
    krw_kcall_func_t kcall;
    krw_physread_func_t physread;
    krw_physwrite_func_t physwrite;
};

typedef struct krw_handlers_s* krw_handlers_t;

/**
 * krw_initializer_t - plugin initialization prototype
 *
 * Called krw_initializer_t krw_initializer is called when a plugin is opened to
 * determine if read/write primitives are available
 *
 * krw_initializer should set as many of handlers->kread, handlers->kwrite, handlers->kbase,
 * handlers->kmalloc, and handlers->kdealloc as possible on success - any not set will
 * return unsupported.
 *
 * Called krw_initializer_t kcall_initializer is called when a plugin is opened to
 * determine if read/write primitives are available.  It is passed a structure containing
 * populated kread/kwrite functions
 *
 * kcall_initializer should set as many of handlers->kcall, handlers->physread, and
 * handlers->physwrite as possible on success.  any not set will return unsupported.
 *
 * Retuns 0 if read/write are supported by this plugin
**/
typedef int (*krw_plugin_initializer_t)(krw_handlers_t handlers);

#ifdef __cplusplus
}
#endif

#endif
