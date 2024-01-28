#include "info.h"
#import <Foundation/Foundation.h>

NSString *NSJBRootPath(NSString *relativePath)
{
	@autoreleasepool {
		return [[NSString stringWithUTF8String:jbinfo(rootPath)] stringByAppendingPathComponent:relativePath];
	}
}