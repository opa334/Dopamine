int xpc_pipe_receive(mach_port_t port, xpc_object_t* message);
void xpc_dictionary_get_audit_token(xpc_object_t xdict, audit_token_t *token);
int xpc_pipe_routine_reply(xpc_object_t reply);
xpc_object_t xpc_dictionary_create_empty(void);
xpc_object_t xpc_pipe_create_from_port(mach_port_t port, uint32_t flags);
int xpc_pipe_routine(xpc_object_t pipe, xpc_object_t request, xpc_object_t* reply);