int envbuf_len(const char *envp[]);
char **envbuf_mutcopy(const char *envp[]);
void envbuf_free(char *envp[]);
int envbuf_find(const char *envp[], const char *name);
const char *envbuf_getenv(const char *envp[], const char *name);
void envbuf_setenv(char **envpp[], const char *name, const char *value);
void envbuf_unsetenv(char **envpp[], const char *name);