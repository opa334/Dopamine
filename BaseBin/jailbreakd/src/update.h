#import <Foundation/Foundation.h>
NSString *trollStoreRootHelperPath(void);
int basebinUpdateFromTar(NSString *basebinPath, bool rebootWhenDone);
int jbUpdateFromTIPA(NSString *tipaPath, bool rebootWhenDone);