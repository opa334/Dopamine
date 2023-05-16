#import <Foundation/Foundation.h>

int reboot3(uint64_t flags, ...);
#define RB2_USERREBOOT (0x2000000000000000llu)

extern NSDictionary* gBootInfo;
uint64_t bootInfo_getUInt64(NSString* name);
uint64_t bootInfo_getSlidUInt64(NSString* name);
NSData* bootInfo_getData(NSString* name);

extern uint64_t gSelfProc;
extern uint64_t gSelfTask;

void primitivesInitializedCallback(void);