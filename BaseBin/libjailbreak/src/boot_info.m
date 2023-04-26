#import <Foundation/Foundation.h>
#import "util.h"

#define BOOT_INFO_PATH prebootPath(@"basebin/boot_info.plist")

void bootInfo_setObject(NSString *name, __kindof NSObject *object)
{
	NSURL *bootInfoURL = [NSURL fileURLWithPath:BOOT_INFO_PATH isDirectory:NO];
	NSMutableDictionary *bootInfo = [NSDictionary dictionaryWithContentsOfURL:bootInfoURL error:nil].mutableCopy ?: [NSMutableDictionary new];
	if (object) {
		bootInfo[name] = object;
	}
	else {
		[bootInfo removeObjectForKey:name];
	}
	[bootInfo writeToURL:bootInfoURL atomically:YES];
}

__kindof NSObject *bootInfo_getObject(NSString *name)
{
	NSURL *bootInfoURL = [NSURL fileURLWithPath:BOOT_INFO_PATH isDirectory:NO];
	NSDictionary *bootInfo = [NSDictionary dictionaryWithContentsOfURL:bootInfoURL error:nil];
	return bootInfo[name];
}

uint64_t bootInfo_getUInt64(NSString *name)
{
	NSNumber* num = bootInfo_getObject(name);
	if ([num isKindOfClass:NSNumber.class])
	{
		return num.unsignedLongLongValue;
	}
	return 0;
}

uint64_t bootInfo_getSlidUInt64(NSString *name)
{
	uint64_t kernelslide = bootInfo_getUInt64(@"kernelslide");
	return bootInfo_getUInt64(name) + kernelslide;
}

NSData *bootInfo_getData(NSString *name)
{
	NSData* data = bootInfo_getObject(name);
	if ([data isKindOfClass:NSData.class])
	{
		return data;
	}
	return nil;
}

NSArray *bootInfo_getArray(NSString *name)
{
	NSArray* array = bootInfo_getObject(name);
	if ([array isKindOfClass:NSArray.class])
	{
		return array;
	}
	return nil;
}