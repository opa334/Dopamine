#import <Foundation/Foundation.h>

extern NSDictionary* gBootInfo;
uint64_t bootInfo_getUInt64(NSString* name);
uint64_t bootInfo_getSlidUInt64(NSString* name);
NSData* bootInfo_getData(NSString* name);

extern uint64_t gSelfProc;
extern uint64_t gSelfTask;