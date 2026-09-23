//
//  CLIProxy.mm
//  Dialog2
//
//  Created by Ciaran Walsh on 16/02/2008.
//

#import "CLIProxy.h"
#import "TMDCommand.h"

@interface CLIProxy ()
{
	NSArray* _arguments;
	NSDictionary* _parameters;
	int _connection;
}
@end

@implementation CLIProxy
- (instancetype)initWithOptions:(NSDictionary*)options fileDescriptors:(std::vector<int> const&)fds connection:(int)connection
{
	if(self = [super init])
	{
		_connection       = connection;
		_inputHandle      = [[NSFileHandle alloc] initWithFileDescriptor:fds[0] closeOnDealloc:YES];
		_outputHandle     = [[NSFileHandle alloc] initWithFileDescriptor:fds[1] closeOnDealloc:YES];
		_errorHandle      = [[NSFileHandle alloc] initWithFileDescriptor:fds[2] closeOnDealloc:YES];
		_arguments        = [options objectForKey:@"arguments"];
		_environment      = [options objectForKey:@"environment"];
		_workingDirectory = [options objectForKey:@"cwd"];
	}
	return self;
}

- (void)dealloc
{
	[_inputHandle closeFile];
	[_outputHandle closeFile];
	[_errorHandle closeFile];
	if(_connection != -1)
		close(_connection);
}

- (NSDictionary*)parameters
{
	if(!_parameters)
	{
		NSMutableDictionary* res = [NSMutableDictionary dictionary];
		if(id plist = [TMDCommand readPropertyList:self.inputHandle error:NULL])
		{
			if([plist isKindOfClass:[NSDictionary class]])
				res = plist;
		}

		for(NSUInteger i = 2; i < [_arguments count]; )
		{
			NSString* key = _arguments[i++];
			if(![key hasPrefix:@"--"])
				continue; // TODO Report unexpected argument to user

			key = [key substringFromIndex:2];
			NSString* value = i < _arguments.count ? _arguments[i] : @"";

			if([value hasPrefix:@"--"] && ![value isEqualToString:@"--"])
			{
				value = @""; // We use NSString instead of NSNull because we may send mutableCopy to parameters
			}
			else
			{
				++i;
				if([value isEqualToString:@"--"])
					value = i < _arguments.count ? _arguments[i++] : @"";
			}
			res[key] = value;
		}

		_parameters = res;
	}
	return _parameters;
}

- (NSUInteger)numberOfArguments;
{
	return [_arguments count];
}

- (NSString*)argumentAtIndex:(NSUInteger)index;
{
	return index < [_arguments count] ? _arguments[index] : nil;
}

// ===================
// = Reading/Writing =
// ===================
- (void)writeStringToOutput:(NSString*)aString;
{
	[self.outputHandle writeData:[aString dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)writeStringToError:(NSString*)aString;
{
	[self.errorHandle writeData:[aString dataUsingEncoding:NSUTF8StringEncoding]];
}

- (id)readPropertyListFromInput;
{
	NSError* error = nil;
	id plist       = [TMDCommand readPropertyList:self.inputHandle error:&error];

	if(!plist)
		[self writeStringToError:[error localizedDescription] ?: @"unknown error parsing property list\n"];

	return plist;
}
@end
