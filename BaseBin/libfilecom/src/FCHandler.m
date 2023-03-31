#import "FCHandler.h"

@implementation FCHandler

- (instancetype)initWithReceiveFilePath:(NSString *)receiveFilePath sendFilePath:(NSString *)sendFilePath
{
	self = [super init];
	if (self) {
		_receiveFilePath = receiveFilePath;
		_sendFilePath = sendFilePath;
		_receiveFd = -1;
		_dispatchSource = nil;
		_ignoreIncoming = NO;

		if (![[NSFileManager defaultManager] fileExistsAtPath:[receiveFilePath stringByDeletingLastPathComponent]])
		{
			[[NSFileManager defaultManager] createDirectoryAtPath:[receiveFilePath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
		}
		if (![[NSFileManager defaultManager] fileExistsAtPath:[sendFilePath stringByDeletingLastPathComponent]])
		{
			[[NSFileManager defaultManager] createDirectoryAtPath:[sendFilePath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
		}

		_sendQueue = dispatch_queue_create("com.opa334.libfilecommunication.sendqueue", DISPATCH_QUEUE_SERIAL);
		_receiveQueue = dispatch_queue_create("com.opa334.libfilecommunication.receivequeue", DISPATCH_QUEUE_SERIAL);

		[self _startListening];
	}
	return self;
}

- (void)_startListening
{
	if (![[NSFileManager defaultManager] fileExistsAtPath:_receiveFilePath])
	{
		[[NSFileManager defaultManager] createFileAtPath:_receiveFilePath contents:[NSData data] attributes:nil];
	}
	
	_receiveFd = open(_receiveFilePath.fileSystemRepresentation, O_EVTONLY);
	if (_receiveFd < 0) {
		NSLog(@"Failed to listen for changes on %@", _receiveFilePath);
		return;
	}

	_dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, _receiveFd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE, _receiveQueue);
	dispatch_source_set_event_handler(_dispatchSource, ^{
		if (_ignoreIncoming) return;

		uintptr_t flags = dispatch_source_get_data(_dispatchSource);
		if (flags & DISPATCH_VNODE_DELETE) {
			dispatch_source_cancel(_dispatchSource);
			[self _startListening];
			return;
		}
		NSError *error;
		NSData *incomingData = [NSData dataWithContentsOfFile:_receiveFilePath options:0 error:&error];
		if (incomingData) {
			NSDictionary *dictionary = [NSPropertyListSerialization propertyListWithData:incomingData options:0 format:nil error:&error];
			if (dictionary) {
				[self receivedMessage:dictionary];
			}
			else {
				NSLog(@"Error decoding incoming data: %@", error);
			}
		}
		else {
			NSLog(@"Error receiving incoming data: %@", error);
		}
	});
	dispatch_resume(_dispatchSource);
}

- (BOOL)sendMessage:(NSDictionary *)message
{
	NSError *error;
	NSData *msgData = [NSPropertyListSerialization dataWithPropertyList:message format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
	if (!msgData) {
		NSLog(@"Error encoding data: %@", error);
	}
	[msgData writeToFile:_sendFilePath atomically:NO];
	return YES;
}

- (void)receivedMessage:(NSDictionary *)message
{
	if (_receiveHandler) _receiveHandler(message);
}

- (void)dealloc
{
	if (_receiveFd != -1) close(_receiveFd);
	if (_dispatchSource) {
		if (!dispatch_source_testcancel(_dispatchSource)) {
			dispatch_source_cancel(_dispatchSource);
		}
	}
	//[[NSFileManager defaultManager] removeItemAtPath:_receiveFilePath error:nil];
}

@end