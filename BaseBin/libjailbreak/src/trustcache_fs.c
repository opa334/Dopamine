#include "trustcache_fs.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>
#include <fcntl.h>
#include "signatures.h"
#include "trustcache.h"


void walk_machos_in_dir(const char *dir_path, void (^macho_fat_walk)(const char *path, Fat *fat), bool recurse)
{
    DIR *dir = opendir(dir_path);
    if (!dir) {
        perror(dir_path);
        return;
    }

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        /* Skip the current- and parent-directory entries */
        if (strcmp(entry->d_name, ".") == 0 ||
            strcmp(entry->d_name, "..") == 0)
            continue;

        /* Build the full path */
		size_t full_path_size = strlen(dir_path) + strlen(entry->d_name) + 2;
        char *full_path = malloc(full_path_size);
        int written = snprintf(full_path, full_path_size, "%s/%s", dir_path, entry->d_name);

        struct stat st;
        if (lstat(full_path, &st) != 0) {
            perror(full_path);
			free(full_path);
            continue;
        }

        if (S_ISDIR(st.st_mode) && recurse) {
            /* Recurse into sub-directory */
            walk_machos_in_dir(full_path, macho_fat_walk, recurse);
        } else if (S_ISREG(st.st_mode)) {
            /* Regular file – check for Mach-O magic */
			Fat *fat = fat_init_from_path(full_path);
			if (fat) {
				macho_fat_walk(full_path, fat);
				fat_free(fat);
			}
        }
        /* Symlinks, devices, sockets, etc. are silently ignored */

		free(full_path);
    }

    closedir(dir);
}

void directory_collect_untrusted_cdhashes_by_path(const char *directoryPath, bool recursive, cdhash_t **cdhashesOut, uint32_t *cdhashCountOut)
{
	__block cdhash_t *cdhashes = NULL;
	__block uint32_t cdhashCount = 0;

	walk_machos_in_dir(directoryPath, ^(const char *path, Fat *fat){
		printf("Collecting cdhash of %s\n", path);
		cdhash_t *thisCdhashes = NULL;
		uint32_t thiscdhashCount = 0;
		fat_collect_untrusted_cdhashes(fat, &thisCdhashes, &thiscdhashCount);
		cdhashCount += thiscdhashCount;
		cdhashes = realloc(cdhashes, cdhashCount * sizeof(cdhash_t));
		memcpy(&cdhashes[cdhashCount-thiscdhashCount], thisCdhashes, sizeof(cdhash_t) * thiscdhashCount);
	}, recursive);

	*cdhashesOut = cdhashes;
	*cdhashCountOut = cdhashCount;
}

int jb_trustcache_add_file(const char *filePath)
{
	cdhash_t *cdhashes = NULL;
	uint32_t cdhashCount = 0;
	file_collect_untrusted_cdhashes_by_path(filePath, &cdhashes, &cdhashCount);

	if (cdhashes && cdhashCount > 0) {
		jb_trustcache_add_cdhashes(cdhashes, cdhashCount);
		free(cdhashes);
	}

	return 0;
}

int jb_trustcache_add_directory(const char *directoryPath, bool recursive)
{
	cdhash_t *cdhashes = NULL;
	uint32_t cdhashCount = 0;

	directory_collect_untrusted_cdhashes_by_path(directoryPath, recursive, &cdhashes, &cdhashCount);
	if (cdhashes && cdhashCount > 0) {
		printf("Added %u cdhashes\n", cdhashCount);
		jb_trustcache_add_cdhashes(cdhashes, cdhashCount);
		free(cdhashes);
	}

	return 0;
}
