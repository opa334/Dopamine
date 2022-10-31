//
//  Fugu15KRW.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef Fugu15KRW_h
#define Fugu15KRW_h

#include <mach/mach.h>

// Yes, Fugu15KRW supports versioning
// No, I don't plan to actually increase the version number
#define FUGU15KRW_VERSION_0       (uint64_t) 0
#define FUGU15KRW_VERSION_CURRENT FUGU15KRW_VERSION_0

#define FUGU15KRW_ERROR_BAD_SIZE    (uint64_t) 1
#define FUGU15KRW_ERROR_BAD_VERSION (uint64_t) 2
#define FUGU15KRW_ERROR_BAD_REQ_ID  (uint64_t) 3

#define FUGU15KRW_REQ_PPL     (mach_msg_id_t) 0xF1500
#define FUGU15KRW_REQ_THSIGN  (mach_msg_id_t) 0xF1501
#define FUGU15KRW_REQ_OFFSETS (mach_msg_id_t) 0xF1502

#define FUGU15KRW_REPLY_PPL     (mach_msg_id_t) 0x52F1500
#define FUGU15KRW_REPLY_THSIGN  (mach_msg_id_t) 0x52F1501
#define FUGU15KRW_REPLY_OFFSETS (mach_msg_id_t) 0x52F1502

#define FUGU15KRW_REPLY_ERROR   (mach_msg_id_t) 0x46457272

typedef struct {
    mach_msg_header_t mach_header;
    uint64_t version;    // Our version
    uint64_t versionMin; // The minimum version the server has to support
} Fugu15KRWRequestCommon;

typedef struct {
    mach_msg_header_t mach_header;
    uint64_t version; // Server version
} Fugu15KRWReplyCommon;

typedef struct {
    Fugu15KRWRequestCommon header;
} Fugu15PPLMapRequest;

typedef struct {
    Fugu15KRWReplyCommon header;
    uint64_t mapAddr;
} Fugu15PPLMapReply;

typedef struct {
    Fugu15KRWRequestCommon header;
    uint64_t signAddr;
} Fugu15ThSignRequest;

typedef struct {
    Fugu15KRWReplyCommon header;
} Fugu15ThSignReply;

typedef struct {
    Fugu15KRWRequestCommon header;
} Fugu15OffsetsRequest;

typedef struct {
    Fugu15KRWReplyCommon header;
    uint64_t virtualBase;  // As reported in the boot args structure
    uint64_t physicalBase; // As reported in the boot args structure
    uint64_t vKernelBase;  // pKernelBase = vKernelBase - virtualBase + physicalBase
    uint64_t kernelSlide;  // vKernelBase - default kernel load address
    uint64_t kernelTTEP;   // Root translation table of the kernel, physical address
} Fugu15OffsetsReply;

typedef struct {
    Fugu15KRWReplyCommon header;
    uint64_t errorCode;
} Fugu15ErrorReply;

#endif /* Fugu15KRW_h */
