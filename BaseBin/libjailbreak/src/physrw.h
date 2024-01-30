#ifndef PHYSRW_H
#define PHYSRW_H

#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>

#define PPLRW_USER_MAPPING_OFFSET   0x7000000000
#define PPLRW_USER_MAPPING_TTEP_IDX (PPLRW_USER_MAPPING_OFFSET / 0x1000000000)

int physrw_handoff(pid_t pid);
int libjailbreak_physrw_init(bool receivedHandoff);

#endif
