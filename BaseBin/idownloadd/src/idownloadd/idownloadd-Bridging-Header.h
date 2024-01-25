//
//  idownloadd-Bridging-Header.h
//  idownloadd
//
//  Created by Lars Fröder on 08.06.23.
//

#ifndef idownloadd_Bridging_Header_h
#define idownloadd_Bridging_Header_h

#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/primitives.h>
#import <libjailbreak/jbclient_xpc.h>

uint64_t c_getkslide(void);
uint64_t c_getkbase(void);
bool c_kcall_supported(void);
int c_kcall(uint64_t *result, uint64_t func, int argc, const uint64_t *argv);
uint64_t c_kalloc(uint64_t *addr, uint64_t size);

#endif /* idownloadd_Bridging_Header_h */
