#import <Foundation/Foundation.h>

extern NSDictionary* gBootInfo;
uint64_t bootInfo_getUInt64(NSString* name);
uint64_t bootInfo_getSlidUInt64(NSString* name);
NSData* bootInfo_getData(NSString* name);

extern uint64_t gSelfProc;
extern uint64_t gSelfTask;

typedef enum {
	kPPLStatusNotInitialized = 0,
	kPPLStatusInitialized = 1
} PPLStatus;

typedef enum {
	kPACStatusNotInitialized = 0,
	kPACStatusPrepared = 1,
	kPACStatusFinalized = 2
} PACStatus;

extern PPLStatus gPPLStatus;
extern PACStatus gPACStatus;

void PPLInitializedCallback(void);
void PACInitializedCallback(void);