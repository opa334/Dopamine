#ifndef HANDOFF_H
#define HANDOFF_H

uint64_t pmap_alloc_page_table(uint64_t pmap);
int handoffPPLPrimitives(pid_t pid);

#endif
