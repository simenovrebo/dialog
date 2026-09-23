//
//  Dialog2.mm
//  Dialog2
//
//  Created by Ciaran Walsh on 19/11/2007.
//

#import "Dialog2.h"
#import "TMDCommand.h"
#import "CLIProxy.h"
#import <oak/ipc.h>

@protocol TMPlugInController
- (CGFloat)version;
@end

@interface Dialog2 : NSObject
{
	int _listenSocket;
	dispatch_source_t _acceptSource;
	std::string _socketPath;
}
- (id)initWithPlugInController:(id <TMPlugInController>)aController;
@end

@implementation Dialog2
- (id)initWithPlugInController:(id <TMPlugInController>)aController
{
	NSApp = NSApplication.sharedApplication;
	if(self = [self init])
	{
		oak::ipc::remove_stale_sockets(kDialogServerSocketName);
		_socketPath   = oak::ipc::socket_path(kDialogServerSocketName, getpid());
		_listenSocket = oak::ipc::listen(_socketPath);
		if(_listenSocket == -1)
		{
			NSLog(@"couldn't setup dialog server: %s", strerror(errno)), NSBeep();
			return self;
		}

		int listenSocket = _listenSocket;
		__weak Dialog2* weakSelf = self;
		_acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, listenSocket, 0, dispatch_get_main_queue());
		dispatch_source_set_event_handler(_acceptSource, ^{
			int fd = oak::ipc::accept(listenSocket);
			if(fd == -1)
				return;

			// Read the request in the background, so that a client that does not send one cannot block TextMate
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				struct timeval timeout = { 10, 0 };
				setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

				std::string data;
				std::vector<int> fds;
				NSDictionary* options;
				if(oak::ipc::receive_message(fd, &data, &fds))
					options = [NSPropertyListSerialization propertyListWithData:[NSData dataWithBytes:data.data() length:data.size()] options:NSPropertyListImmutable format:nullptr error:nullptr];

				timeout = { 0, 0 };
				setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

				dispatch_async(dispatch_get_main_queue(), ^{
					if([options isKindOfClass:[NSDictionary class]] && fds.size() == 3 && weakSelf)
					{
						[weakSelf dispatch:[[CLIProxy alloc] initWithOptions:options fileDescriptors:fds connection:fd]];
					}
					else
					{
						for(int fileDescriptor : fds)
							close(fileDescriptor);
						close(fd);
					}
				});
			});
		});
		dispatch_resume(_acceptSource);

		if(NSString* path = [[NSBundle bundleForClass:[self class]] pathForResource:@"tm_dialog2" ofType:nil])
		{
			char* oldDialog = getenv("DIALOG");
			if(oldDialog == NULL || ![@(oldDialog) isEqualToString:path])
			{
				if(oldDialog)
					setenv("DIALOG_1", oldDialog, 1);
				setenv("DIALOG", [path UTF8String], 1);
			}

			setenv("DIALOG_SOCKET", _socketPath.c_str(), 1);
		}

		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:NSApp];
	}

	return self;
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
	unlink(_socketPath.c_str());
}

- (void)dispatch:(CLIProxy*)interface
{
	NSString* command = [interface numberOfArguments] <= 1 ? @"help" : [interface argumentAtIndex:1];

	if(id target = [TMDCommand objectForCommand:command])
			[target performSelector:@selector(handleCommand:) withObject:interface];
	else	[interface writeStringToError:@"unknown command, try help.\n"];
}
@end
/*
echo '{ menuItems = ({title = 'foo';});}' | "$DIALOG" menu
*/
