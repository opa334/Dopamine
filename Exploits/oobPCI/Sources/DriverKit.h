//
//  DriverKit.h
//  oobPCI
//
//  Created by Linus Henze.
//  Copyright © 2022 Pinauten GmbH. All rights reserved.
//

#ifndef DriverKit_h
#define DriverKit_h

#include <mach/mach.h>

extern mach_port_t gDKIOPort;
extern mach_port_t gDKServerPort;
extern mach_port_t gDKOrigServerPort;
extern mach_port_t gIOPCIDev;

struct DriverKitRPCHeader {
    uint64_t messageID;
    uint64_t flags;
    uint64_t objCount;
};

#define DECLARE_DK_MESSAGE_COMPLEX(name, msgid, machObjs, objs, attr) \
const uint64_t DKMESSAGE$$$##name##$$$MSGID = msgid; \
const mach_msg_size_t DKMESSAGE$$$##name##$$$MACHOBJS = machObjs; \
const uint64_t DKMESSAGE$$$##name##$$$OBJS = objs; \
typedef struct { \
    mach_msg_header_t header; \
    mach_msg_body_t body; \
    mach_msg_port_descriptor_t descs[machObjs]; \
    struct DriverKitRPCHeader dkHeader; \
    uint64_t dkObjSpace[objs]; \
    struct attr; \
    uint64_t emptySpace; \
} name;

#define DECLARE_DK_MESSAGE(name, msgid, objs, attr) DECLARE_DK_MESSAGE_COMPLEX(name, msgid, objs, objs, attr)

#define DK_MESSAGE_BITS       MACH_MSG_TYPE_COPY_SEND      | (MACH_MSG_TYPE_MAKE_SEND << 8) | MACH_MSGH_BITS_COMPLEX
#define DK_MESSAGE_BITS_REPLY MACH_MSG_TYPE_MOVE_SEND_ONCE | (MACH_MSG_TYPE_MAKE_SEND << 8) | MACH_MSGH_BITS_COMPLEX

#define DK_MESSAGE_INIT_PTR(type, m) memset((m), 0, sizeof(type)); (m)->header.msgh_bits = DK_MESSAGE_BITS; (m)->header.msgh_size = sizeof(type) - 8; (m)->header.msgh_id = 0x4DA2B68C; (m)->body.msgh_descriptor_count = DKMESSAGE$$$##type##$$$MACHOBJS; (m)->dkHeader.messageID = DKMESSAGE$$$##type##$$$MSGID; (m)->dkHeader.objCount = DKMESSAGE$$$##type##$$$OBJS
#define DK_MESSAGE_INIT(type, m) DK_MESSAGE_INIT_PTR(type, &m)

#define DK_MESSAGE_CONSTRUCT(type, m) type m = { \
    .header = { \
        .msgh_bits = DK_MESSAGE_BITS, \
        .msgh_size = sizeof(type) - 8, \
        .msgh_remote_port = 0, \
        .msgh_local_port = 0, \
        .msgh_voucher_port = 0, \
        .msgh_id = 0x4DA2B68C \
    }, \
    .body = { \
        .msgh_descriptor_count = DKMESSAGE$$$##type##$$$MACHOBJS \
    }, \
    .dkHeader = { \
        .messageID = DKMESSAGE$$$##type##$$$MSGID, \
        .flags = 0, \
        .objCount = DKMESSAGE$$$##type##$$$OBJS \
    } \
}

#define DK_MESSAGE_CONSTRUCT_OBJS(type, m, ...) DK_MESSAGE_CONSTRUCT(type, m); DK_MESSAGE_SET_OBJECTS(type, m, ##__VA_ARGS__)

#define DK_MESSAGE_PTR_SET_OBJECTS(type, m, ...) dk_message_set_objects(&(m)->descs[0], DKMESSAGE$$$##type##$$$MACHOBJS, ##__VA_ARGS__)
#define DK_MESSAGE_SET_OBJECTS(type, m, ...)     DK_MESSAGE_PTR_SET_OBJECTS(type, &m, ##__VA_ARGS__)

#define DK_CLASS(name) DKCLASS$$$##name

#define DK_ASSERT_CANCAST(type, msg) dk_assert_can_cast_message(msg, sizeof(type) - 8, DKMESSAGE$$$##type##$$$MSGID, DKMESSAGE$$$##type##$$$MACHOBJS, DKMESSAGE$$$##type##$$$OBJS)
#define DK_CAST(type, msg)           (DK_ASSERT_CANCAST(type, msg); (type*) msg)
#define DK_CAST_OR_NULL(type, msg)   (dk_can_cast_message(msg, sizeof(type) - 8, DKMESSAGE$$$##type##$$$MSGID, DKMESSAGE$$$##type##$$$MACHOBJS, DKMESSAGE$$$##type##$$$OBJS) ? (type*) msg : NULL)

#define DK_RPC(m, type, replName)         type replName; dk_do_rpc(&m.header, &replName.header, sizeof(type)); DK_ASSERT_CANCAST(type, &replName)
#define DK_RECVFROM(port, type, replName) type replName; dk_rpc_recv(port, &replName.header, sizeof(type)); DK_ASSERT_CANCAST(type, &replName)

struct DKAllClassesStruct {
    const char  *name;
    mach_port_t *port;
};

void dk_init(mach_port_t ioService, mach_port_t server);
void user_server_checkin(const char *name, uint64_t tag);
mach_port_t create_dispatch_queue(const char *name);
void dispatch_queue_set_port(mach_port_t queue, mach_port_t port);
void server_register(void);
mach_port_t server_get_provider(mach_port_t queuePort);
void server_terminate(void);

void pcidev_open_session(mach_port_t dev);

uint64_t pcidev_r64(uint64_t offset);
uint64_t pcidev_rPtr(uint64_t offset);
uint32_t pcidev_r32(uint64_t offset);
uint16_t pcidev_r16(uint64_t offset);
uint8_t  pcidev_r8 (uint64_t offset);

void pcidev_w64(uint64_t offset, uint64_t data);
void pcidev_w32(uint64_t offset, uint32_t data);
void pcidev_w16(uint64_t offset, uint16_t data);
void pcidev_w8 (uint64_t offset, uint8_t data);

mach_port_t pcidev_copy_memory(uint64_t index);

void pcidev_set_base_offset(uint64_t offset);

mach_port_t IOBufferMemoryDescriptor_create(uint64_t options, uint64_t size, uint64_t alignment);
void IOBufferMemoryDescriptor_setLength(mach_port_t memoryDescriptor, uint64_t length);

uint64_t IOMemoryDescriptor_map(mach_port_t memoryDescriptor, uint64_t offset, uint64_t len);

mach_port_t IODMACommand_create(void);
void IODMACommand_prepare(mach_port_t command, mach_port_t memoryDescriptor);
void IODMACommand_readFrom(mach_port_t command, mach_port_t from, uint64_t length);
void IODMACommand_writeTo(mach_port_t command, mach_port_t to, uint64_t length);

#endif /* DriverKit_h */
