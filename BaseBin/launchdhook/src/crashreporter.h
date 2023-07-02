typedef int                             exception_type_t;
typedef integer_t                       exception_data_type_t;

typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t msgh_body;
    mach_msg_port_descriptor_t thread;
    mach_msg_port_descriptor_t task;
    int unused1;
    exception_type_t exception;
    exception_data_type_t code;
    int unused2;
    int subcode;
    NDR_record_t ndr;
} exception_raise_request; // the bits we need at least

typedef struct {
    mach_msg_header_t header;
    NDR_record_t ndr;
    kern_return_t retcode;
} exception_raise_reply;

typedef struct {
    mach_msg_header_t header;
    NDR_record_t ndr;
    kern_return_t retcode;
    int flavor;
    mach_msg_type_number_t new_stateCnt;
    natural_t new_state[614];
} exception_raise_state_reply;

void crashreporter_start(void);