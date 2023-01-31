//
//  DriverKit.c
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#include "DriverKit.h"
#include "generated/device.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

// Create the DriverKit Classes
#define DK_DECLARE_CLASS(name) mach_port_t DKCLASS$$$##name;
#include "DriverKitClasses.h"
#undef DK_DECLARE_CLASS

struct DKAllClassesStruct DKAllClasses[] = {
    #define DK_DECLARE_CLASS(name) { #name, &DKCLASS$$$##name },
    #undef DriverKitClasses_h
    #include "DriverKitClasses.h"
    #undef DK_DECLARE_CLASS
};

mach_port_t gDKIOPort         = 0;
mach_port_t gDKServerPort     = 0;
mach_port_t gDKOrigServerPort = 0;
mach_port_t gIOPCIDev         = 0;

void dk_resolve_class(const char *name, mach_port_t *port) {
    struct __attribute__((packed)) {
        uint32_t size;
        char name[96];
        char super[96];
        uint32_t stuff[11];
        uint64_t flags;
        uint64_t resv[8];
    } resolve;
    
    _Static_assert(sizeof(resolve) == 0x138, "Bad size!");
    
    memset(&resolve, 0, sizeof(resolve));
    resolve.size = sizeof(resolve);
    strncpy(resolve.name, name, 96);
    
    uint64_t output[2] = { 0, 0 };
    mach_msg_type_number_t inband_outputCnt = 0;
    mach_msg_type_number_t scalar_outputCnt = 2;
    mach_vm_size_t         ool_output_size  = 0;
    kern_return_t kr = io_connect_method(gDKIOPort, 0x00001000, NULL, 0, (char*) &resolve, sizeof(resolve), 0, 0, NULL, &inband_outputCnt, output, &scalar_outputCnt, 0, &ool_output_size);
    
    if (kr != KERN_SUCCESS) {
        printf("Failed to get DK Class '%s'! [io_connect_method error %x]\n", name, kr);
        exit(-1);
    }
    
    *port = (mach_port_t) output[0];
}

void dk_message_set_objects(mach_msg_port_descriptor_t *descs, mach_msg_size_t descCount, ...) {
    va_list vl;
    va_start(vl, descCount);
    
    while (descCount--) {
        descs->name        = va_arg(vl, mach_port_t);
        descs->disposition = MACH_MSG_TYPE_COPY_SEND;
        descs->type        = MACH_MSG_PORT_DESCRIPTOR;
        descs++;
    }
    
    va_end(vl);
}

void dk_init(mach_port_t ioService, mach_port_t server) {
    gDKIOPort     = ioService;
    gDKServerPort = server;
    for (size_t i = 0; i < (sizeof(DKAllClasses) / sizeof(DKAllClasses[0])); i++) {
        dk_resolve_class(DKAllClasses[i].name, DKAllClasses[i].port);
    }
}

void dk_rpc_recv(mach_port_t port, mach_msg_header_t *rpl, mach_msg_size_t rplSize) {
    if (rpl && rplSize) {
        kern_return_t kr = mach_msg(rpl, MACH_RCV_MSG|MACH_RCV_LARGE, 0, rplSize, port, 0, 0);
        if (kr != KERN_SUCCESS) {
            printf("dk_rpc_recv: Receive failed! [%x]\n", kr);
            if (kr == MACH_RCV_TOO_LARGE) {
                printf("dk_rpc_recv: Receive expected %x bytes, but only got %x!\n", rpl->msgh_size, rplSize);
            }
            
            exit(-1);
        }
    }
}

void dk_do_rpc(mach_msg_header_t *hdr, mach_msg_header_t *rpl, mach_msg_size_t rplSize) {
    mach_port_t local = mig_get_reply_port();
    
    hdr->msgh_remote_port = gDKServerPort;
    hdr->msgh_local_port  = local;
    kern_return_t kr = mach_msg(hdr, MACH_SEND_MSG, hdr->msgh_size, 0, 0, 0, 0);
    if (kr != KERN_SUCCESS) {
        puts("dk_send_message: Send failed!");
        exit(-1);
    }
    
    dk_rpc_recv(local, rpl, rplSize);
    
    mig_put_reply_port(local);
}

bool dk_can_cast_message(void *msg, size_t requiredSize, uint64_t msgId, mach_msg_size_t machObjs, uint64_t objs) {
    uint8_t *message = (uint8_t*) msg;
    
    mach_msg_header_t *hdr = (mach_msg_header_t*) message;
    if (hdr->msgh_size != requiredSize) {
        printf("dk_can_cast_message: Bad size, expected %llx, got %x!\n", (uint64_t) requiredSize, hdr->msgh_size);
        
        // Maybe an error?
        uint64_t **addr = (uint64_t**)((uintptr_t) message + hdr->msgh_size - 8);
        printf("Err: %p\n", (void*) *addr);
        
        return false;
    }
    
    if (hdr->msgh_id != 0x4DA2B68C && hdr->msgh_id != 0x4DA2B68D) {
        printf("dk_can_cast_message: Bad msgh_id, got %x!\n", hdr->msgh_id);
        return false;
    }
    
    message += sizeof(mach_msg_header_t);
    
    if (!(hdr->msgh_bits & MACH_MSGH_BITS_COMPLEX)) {
        if (machObjs || objs) {
            puts("dk_can_cast_message: Not a complex message!");
            return false;
        }
    } else {
        mach_msg_body_t *body = (mach_msg_body_t*) message;
        if (body->msgh_descriptor_count != machObjs) {
            printf("dk_can_cast_message: Bad descriptor count, expected %x, got %x!\n", machObjs, body->msgh_descriptor_count);
            return false;
        }
        
        message += sizeof(mach_msg_body_t) + (sizeof(mach_msg_port_descriptor_t) * machObjs);
    }
    
    struct DriverKitRPCHeader *dkHeader = (struct DriverKitRPCHeader*) message;
    if (dkHeader->messageID && dkHeader->messageID != msgId) {
        printf("dk_can_cast_message: Bad message id, expected %llx, got %llx!\n", msgId, dkHeader->messageID);
        return false;
    }
    
    if (dkHeader->objCount != objs) {
        printf("dk_can_cast_message: Bad object count, expected %llx, got %llx!\n", objs, dkHeader->objCount);
        return false;
    }
    
    return true;
}

void dk_assert_can_cast_message(void *message, size_t requiredSize, uint64_t msgId, mach_msg_size_t machObjs, uint64_t objs) {
    if (!dk_can_cast_message(message, requiredSize, msgId, machObjs, objs)) {
        exit(-1);
    }
}

#pragma pack(4)
DECLARE_DK_MESSAGE(DKCheckinMessage, 0xC1DBAEE5E75E22B9, 2, {
    uint64_t pad;
    char name[64];
    uint64_t tag;
    uint64_t options;
})
DECLARE_DK_MESSAGE(DKCheckinMessageReply, 0xC1DBAEE5E75E22B9, 1, {})

DECLARE_DK_MESSAGE(DKCreateQueueMessage, 0xac000428df2a91d0, 1, {
    uint64_t pad;
    char name[256];
    uint64_t flags;
})
DECLARE_DK_MESSAGE(DKCreateQueueMessageReply, 0xac000428df2a91d0, 1, {})

DECLARE_DK_MESSAGE_COMPLEX(DKSetQueuePortMessage, 0xC437E970B5609767, 2, 1, {})
DECLARE_DK_MESSAGE(DKSetQueuePortMessageReply, 0xC437E970B5609767, 0, {})

DECLARE_DK_MESSAGE(DKRegisterMessage, 0xe9722c2bb1347c28, 1, {})
DECLARE_DK_MESSAGE(DKRegisterMessageReply, 0xe9722c2bb1347c28, 0, {})

DECLARE_DK_MESSAGE(DKStartMessage, 0xab6f76dde6d693f2, 2, {})

DECLARE_DK_MESSAGE(DKPCIOpenMessage, 0xd395e45429887c65, 2, {
    uint32_t openClose;
    uint32_t flags;
})
DECLARE_DK_MESSAGE(DKPCIOpenMessageReply, 0xd395e45429887c65, 0, {})

DECLARE_DK_MESSAGE(DKPCIMemoryMessage, 0x8d1327073fe3df0b, 2, {
    uint64_t action;
    uint64_t offset;
    uint64_t data;
    uint32_t flags;
})
DECLARE_DK_MESSAGE(DKPCIMemoryMessageReply, 0x8d1327073fe3df0b, 0, {
    uint64_t result;
})

DECLARE_DK_MESSAGE(DKPCIMemoryCopyMessage, 0x8fbfd4a80b3ed3f1, 2, {
    uint64_t index;
})
DECLARE_DK_MESSAGE(DKPCIMemoryCopyMessageReply, 0x8fbfd4a80b3ed3f1, 1, {})

DECLARE_DK_MESSAGE(DKIOMemoryBufferInit, 0xb78de684e17d5a4b, 1, {
    uint64_t options;
    uint64_t size;
    uint64_t alignment;
})
DECLARE_DK_MESSAGE(DKIOMemoryBufferInitReply, 0xb78de684e17d5a4b, 1, {})

DECLARE_DK_MESSAGE(DKIOMemoryBufferSetLength, 0xc115230c191a6a9a, 1, {
    uint64_t length;
})
DECLARE_DK_MESSAGE(DKIOMemoryBufferSetLengthReply, 0xc115230c191a6a9a, 0, {})

DECLARE_DK_MESSAGE(DKIOMemoryMap, 0xC5E69B0414FF6EE5, 1, {
    uint64_t options;
    uint64_t address;
    uint64_t offset;
    uint64_t length;
    uint64_t alignment;
})
DECLARE_DK_MESSAGE(DKIOMemoryMapReply, 0xC5E69B0414FF6EE5, 1, {})

DECLARE_DK_MESSAGE(DKIOMemoryMapGetState, 0xFC92B3D7F2D48EC7, 1, {})
DECLARE_DK_MESSAGE(DKIOMemoryMapGetStateReply, 0xFC92B3D7F2D48EC7, 0, {
    uint64_t length;
    uint64_t offset;
    uint64_t options;
    uint64_t address;
})

DECLARE_DK_MESSAGE(DKIODMACommandInit, 0xf296a92bb435af2e, 2, {
    uint64_t options;
    uint64_t specOpts;
    uint64_t maxAddressBits;
    uint64_t reserved[16];
})
DECLARE_DK_MESSAGE(DKIODMACommandInitReply, 0xf296a92bb435af2e, 1, {})

DECLARE_DK_MESSAGE(DKIODMACommandPrepare, 0xF88A8C08B75B1110, 2, {
    uint64_t options;
    uint64_t offset;
    uint64_t length;
    uint64_t segCount;
    // Variable number of segments - Not required for oobPCI
})
DECLARE_DK_MESSAGE(DKIODMACommandPrepareReply, 0xF88A8C08B75B1110, 1, {})

DECLARE_DK_MESSAGE(DKIODMACommandRW, 0xc41cd97d9b3042ee, 2, {
    uint64_t options;
    uint64_t dmaOffset;
    uint64_t length;
    uint64_t dataOffset;
})
DECLARE_DK_MESSAGE(DKIODMACommandRWReply, 0xc41cd97d9b3042ee, 0, {})

void user_server_checkin(const char *name, uint64_t tag) {
    DK_MESSAGE_CONSTRUCT_OBJS(DKCheckinMessage, msg, DK_CLASS(IOUserServer), 0);
    
    strncpy(&msg.name[0], name, 64);
    msg.tag     = tag;
    msg.options = 0;
    
    DK_RPC(msg, DKCheckinMessageReply, reply);
    
    if (reply.descs[0].name == 0) {
        puts("user_server_checkin: Failed to get descriptor!");
        exit(-1);
    }
    
    gDKOrigServerPort = gDKServerPort;
    gDKServerPort     = reply.descs[0].name;
}

mach_port_t create_dispatch_queue(const char *name) {
    DK_MESSAGE_CONSTRUCT_OBJS(DKCreateQueueMessage, msg, DK_CLASS(IODispatchQueue));
    
    strncpy(&msg.name[0], name, 256);
    msg.flags = 0;
    
    DK_RPC(msg, DKCreateQueueMessageReply, reply);
    
    if (reply.descs[0].name == 0) {
        puts("create_dispatch_queue: Failed to get queue!");
        exit(-1);
    }
    
    return reply.descs[0].name;
}

void dispatch_queue_set_port(mach_port_t queue, mach_port_t port) {
    DK_MESSAGE_CONSTRUCT_OBJS(DKSetQueuePortMessage, msg, queue, port);
    
    DK_RPC(msg, DKSetQueuePortMessageReply, reply);
}

void server_register(void) {
    DK_MESSAGE_CONSTRUCT_OBJS(DKRegisterMessage, msg, gDKServerPort);
    
    DK_RPC(msg, DKRegisterMessageReply, reply);
}

mach_port_t server_get_provider(mach_port_t queuePort) {
    DK_RECVFROM(queuePort, DKStartMessage, reply);
    
    mach_port_deallocate(mach_task_self_, gDKIOPort);
    gDKIOPort = 0;
    
    return reply.descs[1].name;
}

DK_MESSAGE_CONSTRUCT(DKPCIMemoryMessage, gPCIMemoryR64Message);
DK_MESSAGE_CONSTRUCT(DKPCIMemoryMessage, gPCIMemoryR32Message);
DK_MESSAGE_CONSTRUCT(DKPCIMemoryMessage, gPCIMemoryR16Message);
DK_MESSAGE_CONSTRUCT(DKPCIMemoryMessage, gPCIMemoryR8Message);

DK_MESSAGE_CONSTRUCT(DKPCIMemoryMessage, gPCIMemoryW64Message);
DK_MESSAGE_CONSTRUCT(DKPCIMemoryMessage, gPCIMemoryW32Message);
DK_MESSAGE_CONSTRUCT(DKPCIMemoryMessage, gPCIMemoryW16Message);
DK_MESSAGE_CONSTRUCT(DKPCIMemoryMessage, gPCIMemoryW8Message);

DK_MESSAGE_CONSTRUCT(DKPCIMemoryCopyMessage, gPCIMemoryCopyMessage);

uint64_t pcidevOffsetAdjust = 0;

void pcidev_open_session(mach_port_t dev) {
    gIOPCIDev = dev;
    
    DK_MESSAGE_CONSTRUCT_OBJS(DKPCIOpenMessage, msg, dev, dev);
    
    msg.openClose = 1;
    msg.flags     = 0;
    
    //DK_RPC(msg, DKPCIOpenMessageReply, reply);
    
    uint64_t replyBuf[100];
    
    // This RPC may fail if we already opened the device - Just ignore the error
    // (Happens when the exploit is run multiple times)
    dk_do_rpc(&msg.header, (mach_msg_header_t*) replyBuf, sizeof(replyBuf));
    
    // Setup all the messages
    DK_MESSAGE_SET_OBJECTS(DKPCIMemoryMessage, gPCIMemoryR64Message, dev, dev);
    gPCIMemoryR64Message.action = 0x80100;
    DK_MESSAGE_SET_OBJECTS(DKPCIMemoryMessage, gPCIMemoryR32Message, dev, dev);
    gPCIMemoryR32Message.action = 0x40100;
    DK_MESSAGE_SET_OBJECTS(DKPCIMemoryMessage, gPCIMemoryR16Message, dev, dev);
    gPCIMemoryR16Message.action = 0x20100;
    DK_MESSAGE_SET_OBJECTS(DKPCIMemoryMessage, gPCIMemoryR8Message,  dev, dev);
    gPCIMemoryR8Message.action  = 0x10100;
    
    DK_MESSAGE_SET_OBJECTS(DKPCIMemoryMessage, gPCIMemoryW64Message, dev, dev);
    gPCIMemoryW64Message.action = 0x80200;
    DK_MESSAGE_SET_OBJECTS(DKPCIMemoryMessage, gPCIMemoryW32Message, dev, dev);
    gPCIMemoryW32Message.action = 0x40200;
    DK_MESSAGE_SET_OBJECTS(DKPCIMemoryMessage, gPCIMemoryW16Message, dev, dev);
    gPCIMemoryW16Message.action = 0x20200;
    DK_MESSAGE_SET_OBJECTS(DKPCIMemoryMessage, gPCIMemoryW8Message,  dev, dev);
    gPCIMemoryW8Message.action  = 0x10200;
    
    DK_MESSAGE_SET_OBJECTS(DKPCIMemoryCopyMessage, gPCIMemoryCopyMessage, dev, dev);
}

uint64_t pcidev_r64(uint64_t offset) {
    gPCIMemoryR64Message.offset = offset + pcidevOffsetAdjust;
    
    DK_RPC(gPCIMemoryR64Message, DKPCIMemoryMessageReply, reply);
    
    return reply.result;
}

uint32_t pcidev_r32(uint64_t offset) {
    gPCIMemoryR32Message.offset = offset + pcidevOffsetAdjust;
    
    DK_RPC(gPCIMemoryR32Message, DKPCIMemoryMessageReply, reply);
    
    return (uint32_t) reply.result;
}

uint16_t pcidev_r16(uint64_t offset) {
    gPCIMemoryR16Message.offset = offset + pcidevOffsetAdjust;
    
    DK_RPC(gPCIMemoryR16Message, DKPCIMemoryMessageReply, reply);
    
    return (uint16_t) reply.result;
}

uint8_t pcidev_r8(uint64_t offset) {
    gPCIMemoryR8Message.offset = offset + pcidevOffsetAdjust;
    
    DK_RPC(gPCIMemoryR8Message, DKPCIMemoryMessageReply, reply);
    
    return (uint8_t) reply.result;
}

void pcidev_w64(uint64_t offset, uint64_t data) {
    gPCIMemoryW64Message.offset = offset + pcidevOffsetAdjust;
    gPCIMemoryW64Message.data   = data;
    
    DK_RPC(gPCIMemoryW64Message, DKPCIMemoryMessageReply, reply);
}

void pcidev_w32(uint64_t offset, uint32_t data) {
    gPCIMemoryW32Message.offset = offset + pcidevOffsetAdjust;
    gPCIMemoryW32Message.data   = data;
    
    DK_RPC(gPCIMemoryW32Message, DKPCIMemoryMessageReply, reply);
}

void pcidev_w16(uint64_t offset, uint16_t data) {
    gPCIMemoryW16Message.offset = offset + pcidevOffsetAdjust;
    gPCIMemoryW16Message.data   = data;
    
    DK_RPC(gPCIMemoryW16Message, DKPCIMemoryMessageReply, reply);
}

void pcidev_w8(uint64_t offset, uint8_t data) {
    gPCIMemoryW8Message.offset = offset + pcidevOffsetAdjust;
    gPCIMemoryW8Message.data   = data;
    
    DK_RPC(gPCIMemoryW8Message, DKPCIMemoryMessageReply, reply);
}

void pcidev_set_base_offset(uint64_t offset) {
    pcidevOffsetAdjust = offset;
}

mach_port_t pcidev_copy_memory(uint64_t index) {
    gPCIMemoryCopyMessage.index = index;
    
    DK_RPC(gPCIMemoryCopyMessage, DKPCIMemoryCopyMessageReply, reply);
    
    return reply.descs[0].name;
}

mach_port_t IOBufferMemoryDescriptor_create(uint64_t options, uint64_t size, uint64_t alignment) {
    DK_MESSAGE_CONSTRUCT_OBJS(DKIOMemoryBufferInit, msg, DK_CLASS(IOBufferMemoryDescriptor));
    
    msg.options   = options;
    msg.size      = size;
    msg.alignment = alignment;
    
    DK_RPC(msg, DKIOMemoryBufferInitReply, reply);
    
    mach_port_t port = reply.descs[0].name;
    if (MACH_PORT_VALID(port)) {
        IOBufferMemoryDescriptor_setLength(port, size);
    }
    
    return port;
}

void IOBufferMemoryDescriptor_setLength(mach_port_t memoryDescriptor, uint64_t length) {
    DK_MESSAGE_CONSTRUCT_OBJS(DKIOMemoryBufferSetLength, msg, memoryDescriptor);
    
    msg.length = length;
    
    DK_RPC(msg, DKIOMemoryBufferSetLengthReply, reply);
}

uint64_t IOMemoryDescriptor_map(mach_port_t memoryDescriptor, uint64_t offset, uint64_t len) {
    DK_MESSAGE_CONSTRUCT_OBJS(DKIOMemoryMap, msg, memoryDescriptor);
    
    msg.options   = 0;
    msg.address   = 0;
    msg.offset    = offset;
    msg.length    = len;
    msg.alignment = 0;
    
    DK_RPC(msg, DKIOMemoryMapReply, reply);
    
    mach_port_t mapInfo = reply.descs[0].name;
    
    DK_MESSAGE_CONSTRUCT_OBJS(DKIOMemoryMapGetState, msgState, mapInfo);
    
    DK_RPC(msgState, DKIOMemoryMapGetStateReply, replyState);
    
    return replyState.address;
}

mach_port_t IODMACommand_create(void) {
    DK_MESSAGE_CONSTRUCT_OBJS(DKIODMACommandInit, msg, DK_CLASS(IODMACommand), gDKServerPort);
    
    msg.options  = 0;
    msg.specOpts = 0;
    msg.maxAddressBits = 32;
    
    for (size_t i = 0; i < 16; i++) {
        msg.reserved[i] = 0;
    }
    
    DK_RPC(msg, DKIODMACommandInitReply, reply);
    
    return reply.descs[0].name;
}

void IODMACommand_prepare(mach_port_t command, mach_port_t memoryDescriptor) {
    DK_MESSAGE_CONSTRUCT_OBJS(DKIODMACommandPrepare, msg, command, memoryDescriptor);
    
    msg.options  = 0;
    msg.offset   = 0;
    msg.length   = 0;
    msg.segCount = 0;
    
    uint64_t replyBuf[100];
    
    // RPC will fail, but that's ok
    // DMA Command will be prepared anyway
    dk_do_rpc(&msg.header, (mach_msg_header_t*) replyBuf, sizeof(replyBuf));
}

void IODMACommand_readFrom(mach_port_t command, mach_port_t from, uint64_t length) {
    // Read from other buffer into dma command
    DK_MESSAGE_CONSTRUCT_OBJS(DKIODMACommandRW, msg, command, from);
    
    msg.options    = 0x2;
    msg.dmaOffset  = 0;
    msg.length     = length;
    msg.dataOffset = 0;
    
    DK_RPC(msg, DKIODMACommandRWReply, reply);
}

void IODMACommand_writeTo(mach_port_t command, mach_port_t to, uint64_t length) {
    // Write from dma command to other buffer
    DK_MESSAGE_CONSTRUCT_OBJS(DKIODMACommandRW, msg, command, to);
    
    msg.options    = 0x1;
    msg.dmaOffset  = 0;
    msg.length     = length;
    msg.dataOffset = 0;
    
    DK_RPC(msg, DKIODMACommandRWReply, reply);
}
