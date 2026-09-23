//
//  CLIProxy.h
//  Dialog2
//
//  Created by Ciaran Walsh on 16/02/2008.
//

@interface CLIProxy : NSObject
@property (nonatomic, readonly) NSFileHandle* inputHandle;
@property (nonatomic, readonly) NSFileHandle* outputHandle;
@property (nonatomic, readonly) NSFileHandle* errorHandle;
@property (nonatomic, readonly) NSDictionary* parameters;
@property (nonatomic, readonly) NSDictionary* environment;
@property (nonatomic, readonly) NSString* workingDirectory;

// The file descriptors (stdin, stdout, stderr) and the connection to the client are owned by the proxy. They are
// closed when the proxy is released, which lets the client (tm_dialog2) exit.
- (instancetype)initWithOptions:(NSDictionary*)options fileDescriptors:(std::vector<int> const&)fds connection:(int)connection;

- (void)writeStringToOutput:(NSString*)aString;
- (void)writeStringToError:(NSString*)aString;
- (id)readPropertyListFromInput;

- (NSString*)argumentAtIndex:(NSUInteger)index;
- (NSUInteger)numberOfArguments;
@end
