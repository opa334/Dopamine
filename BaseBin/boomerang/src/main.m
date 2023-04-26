#import <Foundation/Foundation.h>
#import <libjailbreak/libjailbreak.h>
#import <libjailbreak/handoff.h>
#import <libjailbreak/kcall.h>
#import <libfilecom/FCHandler.h>
#import <libjailbreak/launchd.h>

FCHandler *gHandler;

int launchdInitPPLRW(void)
{
	xpc_object_t msg = xpc_dictionary_create_empty();
	xpc_dictionary_set_bool(msg, "jailbreak", true);
	xpc_dictionary_set_uint64(msg, "id", LAUNCHD_JB_MSG_ID_GET_PPLRW);
	xpc_object_t reply = launchd_xpc_send_message(msg);

	int error = xpc_dictionary_get_int64(reply, "error");
	if (error == 0) {
		uint64_t magicPage = xpc_dictionary_get_uint64(reply, "magicPage");
		initPPLPrimitives(magicPage);
		return 0;
	}
	else {
		return error;
	}
}

void getPrimitives(void)
{
	dispatch_semaphore_t sema = dispatch_semaphore_create(0);
	// Receive PPLRW
	gHandler.receiveHandler = ^(NSDictionary *message)
	{
		NSString *identifier = message[@"id"];
		if (identifier) {
			if ([identifier isEqualToString:@"receivePPLRW"])
			{
				uint64_t magicPage = [(NSNumber*)message[@"magicPage"] unsignedLongLongValue];
				if (magicPage) {
					initPPLPrimitives(magicPage);
				}
				dispatch_semaphore_signal(sema);
			}
		}
	};
	[gHandler sendMessage:@{ @"id" : @"getPPLRW", @"pid" : @(getpid()) }];

	dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

	recoverPACPrimitives();

	// Tell launchd we're done, this will trigger the userspace reboot (that this process should survive)
	[gHandler sendMessage:@{ @"id" : @"primitivesInitialized" }];
}

void sendPrimitives(void)
{
	dispatch_semaphore_t sema = dispatch_semaphore_create(0);
	gHandler.receiveHandler = ^(NSDictionary *message) {
		NSString *identifier = message[@"id"];
		if (identifier) {
			if ([identifier isEqualToString:@"getPPLRW"]) {
				uint64_t magicPage = 0;
				int ret = handoffPPLPrimitives(1, &magicPage);
				[gHandler sendMessage:@{@"id" : @"receivePPLRW", @"magicPage" : @(magicPage), @"errorCode" : @(ret), @"boomerangPid" : @(getpid())}];
			}
			else if ([identifier isEqualToString:@"signThreadState"]) {
				uint64_t actContextKptr = [(NSNumber*)message[@"actContext"] unsignedLongLongValue];
				signState(actContextKptr);
				[gHandler sendMessage:@{@"id" : @"signedThreadState"}];
			}
			else if ([identifier isEqualToString:@"primitivesInitialized"])
			{
				dispatch_semaphore_signal(sema); // DONE, exit
			}
		}
	};
	dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
}

int main(int argc, char* argv[])
{
	setsid();
	gHandler = [[FCHandler alloc] initWithReceiveFilePath:prebootPath(@"basebin/.communication/launchd_to_boomerang") sendFilePath:prebootPath(@"basebin/.communication/boomerang_to_launchd")];
	getPrimitives();
	sendPrimitives();
	return 0;
}