#import "fileobserve/OPFileLeaf.h"
#import "trustcache_structs.h"

@interface JBDFileLeaf : OPFileLeaf
{
	bool _loaded;
	struct stat _sb;
	struct cdhashes _cdh;
}
- (BOOL)ensureLoaded;
- (uint64_t)hashCount;
- (trustcache_entry)entryForHashIndex:(int)entryIndex;
@end