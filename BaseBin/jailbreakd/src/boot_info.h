__kindof NSObject *bootInfo_getObject(NSString *name);
void bootInfo_setObject(NSString *name, __kindof NSObject *object);

uint64_t bootInfo_getUInt64(NSString *name);
uint64_t bootInfo_getSlidUInt64(NSString *name);
NSData *bootInfo_getData(NSString *name);
NSArray *bootInfo_getArray(NSString *name);
