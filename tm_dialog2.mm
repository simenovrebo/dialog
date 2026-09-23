//
//  client.mm
//  Created by Allan Odgaard on 2007-09-22.
//

#import "Dialog2.h"
#import <oak/ipc.h>

static double const AppVersion = 2.0;

static std::string socket_path ()
{
	if(char const* path = getenv("DIALOG_SOCKET"))
		return path;
	if(char const* pid = getenv("TM_PID"))
		return oak::ipc::socket_path(kDialogServerSocketName, atoi(pid));
	return "";
}

int main (int argc, char const* argv[])
{
	if(argc == 2 && strcmp(argv[1], "--version") == 0)
	{
		fprintf(stderr, "%1$s %2$.1f (" __DATE__ ")\n", getprogname(), AppVersion);
		return EX_OK;
	}

	// If the argument list starts with a switch then assume it’s meant for trunk dialog
	// and pass it off
	if(argc > 1 && *argv[1] == '-')
		execv(getenv("DIALOG_1"), (char* const*)argv);

	@autoreleasepool {
		std::string const path = socket_path();
		int fd = path.empty() ? -1 : oak::ipc::connect(path);
		if(fd == -1)
		{
			fprintf(stderr, "error reaching server\n");
			exit(EX_UNAVAILABLE);
		}

		NSMutableArray* args = [NSMutableArray array];
		for(size_t i = 0; i < argc; ++i)
			[args addObject:@(argv[i])];

		char* cwd = getcwd(NULL, 0);
		NSDictionary* dict = @{
			@"cwd":         @(cwd ?: "/"),
			@"environment": [[NSProcessInfo processInfo] environment],
			@"arguments":   args,
		};
		free(cwd);

		// The server reads and writes our stdin, stdout, and stderr directly. Input from a terminal is not read.
		int input = isatty(STDIN_FILENO) ? open("/dev/null", O_RDONLY|O_CLOEXEC) : STDIN_FILENO;

		NSData* data = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListBinaryFormat_v1_0 options:0 error:nullptr];
		if(!data || !oak::ipc::send_message(fd, std::string((char const*)data.bytes, data.length), { input, STDOUT_FILENO, STDERR_FILENO }))
		{
			fprintf(stderr, "error sending command to server\n");
			exit(EX_UNAVAILABLE);
		}

		if(input != STDIN_FILENO)
			close(input);

		// Wait for the server to close the connection when the command is done
		char buf[64];
		ssize_t len;
		while((len = read(fd, buf, sizeof(buf))) > 0 || (len == -1 && errno == EINTR))
			;
		close(fd);
	}

	return EX_OK;
}
