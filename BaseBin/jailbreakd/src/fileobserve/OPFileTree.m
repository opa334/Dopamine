//
//  OPFileTree.m
//  fileobserver
//
//  Created by Lars Fröder on 15.02.23.
//

#import "OPFileTree.h"

#import "OPFileNode.h"
#import "OPFileLeaf.h"

void stream_callback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[])
{
    OPFileTree *originatingTree = (__bridge id)clientCallBackInfo;
    [originatingTree receivedEvents:numEvents forPaths:eventPaths withFlags:eventFlags andIds:eventIds];
}

@implementation OPFileTree

+ (instancetype)treeForObservingPath:(NSString *)path
{
    return [[OPFileTree alloc] initWithPath:path];
}

- (instancetype)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        _observePath = path;
        _leafClass = OPFileLeaf.class;
    }
    return self;
}

- (void)openTree
{
    _rootNode = [OPFileNode rootNodeWithName:_observePath.fileSystemRepresentation tree:self];
    
    NSArray *pathsToWatch = @[
        _observePath,
    ];
    
    NSString *dispatchQueueName = [NSString stringWithFormat:@"com.opa334.fileobserver.%@", [NSUUID UUID].UUIDString];
    _eventDispatchQueue = dispatch_queue_create(dispatchQueueName.UTF8String, DISPATCH_QUEUE_SERIAL);
    
    FSEventStreamContext context;
    context.info = (__bridge void*)self;
    context.version = 0;
    context.release = NULL;
    context.retain = NULL;
    context.copyDescription = NULL;
    
    _stream = FSEventStreamCreate(NULL, &stream_callback, &context, (__bridge CFArrayRef)pathsToWatch, kFSEventStreamEventIdSinceNow, 0, (kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagIgnoreSelf));
    
    FSEventStreamSetDispatchQueue(_stream, _eventDispatchQueue);
    FSEventStreamStart(_stream);
}

- (id<OPFileItem>)itemForPath:(NSString *)path
{
    if ([path isEqualToString:_observePath]) {
        return _rootNode;
    }

    if ([path hasPrefix:_observePath]) {
        NSString *relativePath = [path substringFromIndex:_observePath.length+1];
        return [_rootNode itemForSubPath:relativePath];
    }
    return nil;
}

- (void)receivedEvents:(size_t)numEvents forPaths:(void *)eventPaths withFlags:(const FSEventStreamEventFlags[])eventFlags andIds:(const FSEventStreamEventId[])eventIds
{
    NSArray *nsEventPaths = (__bridge id)eventPaths;
    
    for (int i = 0; i < numEvents; i++) {
        FSEventStreamEventId eventId = eventIds[i];
        FSEventStreamEventFlags eventFlag = eventFlags[i];
        NSString *eventPath = nsEventPaths[i];

        if (eventFlag & kFSEventStreamEventFlagMustScanSubDirs) {
            [self mustRescan];
            return;
        }
        
        if (eventFlag & kFSEventStreamEventFlagItemIsSymlink)
        {
            NSLog(@"[%llu] Ignored %@, it's a symlink", eventId, eventPath);
            continue;
        }
        
        id<OPFileItem> fileItem = [self itemForPath:eventPath];
        if (!fileItem) {
            NSLog(@"[%llu] Ignored %@ be cause we determined we don't care about it (sorry)", eventId, eventPath);
            continue;
        }

        NSLog(@"[%llu] Received event flags %u for file %@", eventId, eventFlag, eventPath);

        BOOL eventPathExists = [[NSFileManager defaultManager] fileExistsAtPath:eventPath];
        int actionToTake = -1; // 0: Created, 1: Modified, 2: Deleted

        // This API is fishy so we have to do some extra logic to figure out what it tries to tell us
        if (eventFlag & kFSEventStreamEventFlagItemRenamed) {
            actionToTake = eventPathExists ? 0 : 2;
        }
        else {
            if ((eventFlag & (kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved)) == (kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved)) {
                actionToTake = eventPathExists ? 0 : 2;
            }
            else if (eventFlag & kFSEventStreamEventFlagItemCreated) {
                actionToTake = 0;
            }
            else if (eventFlag & kFSEventStreamEventFlagItemRemoved) {
                actionToTake = 2;
            }
            else if (eventFlag & kFSEventStreamEventFlagItemModified) {
                actionToTake = 1;
            }
        }

        switch (actionToTake) {
            case 0:
            [fileItem createReceived];
            break;

            case 1:
            [fileItem modifyReceived];
            break;

            case 2:
            [fileItem deleteReceived];
            break;
        }
    }
}

- (void)enumerateLeafs:(void (^)(__kindof OPFileLeaf *leaf, BOOL *stop))enumBlock
{
    [_rootNode enumerateLeafs:enumBlock];
}

- (BOOL)shouldIncludeItemAtPath:(NSString *)path
{
    return YES;
}

- (void)mustRescan
{
    //Implemented by subclasses
}

- (void)dealloc
{
    FSEventStreamStop(_stream);
    FSEventStreamInvalidate(_stream);
}

@end
