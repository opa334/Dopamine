//
// Created by Ylarod on 2024/3/15.
//

#ifndef EXEC_PATCH_H
#define EXEC_PATCH_H

#import <stdbool.h>
#include <stdlib.h>

int spawnExecPatchAdd(int pid, bool resume);
int spawnExecPatchDel(int pid);

int execTraceProcess(pid_t pid, uint64_t traced);
int execTraceCancel(pid_t pid, uint64_t detached);

#endif //EXEC_PATCH_H
