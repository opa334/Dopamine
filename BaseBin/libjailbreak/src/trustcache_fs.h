#ifndef TRUSTCACHE_FS_H
#define TRUSTCACHE_FS_H

#import <stdbool.h>

int jb_trustcache_add_file(const char *filePath);
int jb_trustcache_add_directory(const char *directoryPath, bool recursive);

#endif