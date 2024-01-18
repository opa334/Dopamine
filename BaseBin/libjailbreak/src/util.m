#include "info.h"
#import <Foundation/Foundation.h>

NSString *NSJBRootPath(NSString *relativePath)
{
	return [[NSString stringWithUTF8String:jbinfo(rootPath)] stringByAppendingPathComponent:relativePath];
}