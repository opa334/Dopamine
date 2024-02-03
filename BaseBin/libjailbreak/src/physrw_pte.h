#ifndef PHYSRW_PTE_H
#define PHYSRW_PTE_H

#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>

int physrw_pte_handoff(pid_t pid);
int libjailbreak_physrw_pte_init(bool receivedHandoff);

#endif