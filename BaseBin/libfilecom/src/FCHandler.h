#import <Foundation/Foundation.h>

@interface FCHandler : NSObject
{
	NSString *_receiveFilePath;
	NSString *_sendFilePath;
	int _receiveFd;
	dispatch_source_t _dispatchSource;
	dispatch_queue_t _sendQueue;
	dispatch_queue_t _receiveQueue;
	BOOL _ignoreIncoming;
}

@property (nonatomic, copy) void (^receiveHandler)(NSDictionary *); 

- (instancetype)initWithReceiveFilePath:(NSString *)receiveFilePath sendFilePath:(NSString *)sendFilePath;

- (BOOL)sendMessage:(NSDictionary *)message;
- (void)receivedMessage:(NSDictionary *)message;


@end