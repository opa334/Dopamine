#include <stdlib.h>
#include <string.h>

int envbuf_len(const char *envp[])
{
	if (envp == NULL) return 1;

	int k = 0;
	const char *env = envp[k++];
	while (env != NULL) {
		env = envp[k++];
	}
	return k;
}

char **envbuf_mutcopy(const char *envp[])
{
	if (envp == NULL) return NULL;

	int len = envbuf_len(envp);
	char **envcopy = malloc(len * sizeof(char *));

	for (int i = 0; i < len-1; i++) {
		envcopy[i] = strdup(envp[i]);
	}
	envcopy[len-1] = NULL;

	return envcopy;
}

void envbuf_free(char *envp[])
{
	if (envp == NULL) return;

	int len = envbuf_len((const char**)envp);
	for (int i = 0; i < len-1; i++) {
		free(envp[i]);
	}
	free(envp);
}

int envbuf_find(const char *envp[], const char *name)
{
	if (envp) {
		unsigned long nameLen = strlen(name);
		int k = 0;
		const char *env = envp[k++];
		while (env != NULL) {
			unsigned long envLen = strlen(env);
			if (envLen > nameLen) {
				if (!strncmp(env, name, nameLen)) {
					if (env[nameLen] == '=') {
						return k-1;
					}
				}
			}
			env = envp[k++];
		}
	}
	return -1;
}

const char *envbuf_getenv(const char *envp[], const char *name)
{
	if (envp) {
		unsigned long nameLen = strlen(name);
		int envIndex = envbuf_find(envp, name);
		if (envIndex >= 0) {
			return &envp[envIndex][nameLen+1];
		}
	}
	return NULL;
}

void envbuf_setenv(char **envpp[], const char *name, const char *value)
{
	if (envpp) {
		char **envp = *envpp;
		if (!envp) {
			// treat NULL as [NULL]
			envp = malloc(sizeof(const char *));
			envp[0] = NULL;
		}

		char *envToSet = malloc(strlen(name)+strlen(value)+2);
		strcpy(envToSet, name);
		strcat(envToSet, "=");
		strcat(envToSet, value);

		int existingEnvIndex = envbuf_find((const char **)envp, name);
		if (existingEnvIndex >= 0) {
			// if already exists: deallocate old variable, then replace pointer
			free(envp[existingEnvIndex]);
			envp[existingEnvIndex] = envToSet;
		}
		else {
			// if doesn't exist yet: increase env buffer size, place at end
			int prevLen = envbuf_len((const char **)envp);
			*envpp = realloc(envp, (prevLen+1)*sizeof(const char *));
			envp = *envpp;
			envp[prevLen-1] = envToSet;
			envp[prevLen] = NULL;
		}
	}
}

void envbuf_unsetenv(char **envpp[], const char *name)
{
	if (envpp) {
		char **envp = *envpp;
		if (!envp) return;

		int existingEnvIndex = envbuf_find((const char **)envp, name);
		if (existingEnvIndex >= 0) {
			free(envp[existingEnvIndex]);
			int prevLen = envbuf_len((const char **)envp);
			for (int i = existingEnvIndex; i < (prevLen-1); i++) {
				envp[i] = envp[i+1];
			}
			*envpp = realloc(envp, (prevLen-1)*sizeof(const char *));
		}
	}
}
