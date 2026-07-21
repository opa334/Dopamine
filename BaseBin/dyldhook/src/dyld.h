const char *_simple_getenv(char **envp, char *key);
int _simple_dprintf(int fd, const char *format, ...); 
uint64_t msyscall_errno(uint64_t syscall, ...);