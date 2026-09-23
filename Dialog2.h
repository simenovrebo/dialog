// The plug-in listens on a Unix domain socket (see oak/ipc.h), whose path is passed to commands as DIALOG_SOCKET.
// tm_dialog2 sends { arguments, environment, cwd } with its stdin, stdout, and stderr, and waits for the plug-in
// to close the connection when the command is done.
static char const* const kDialogServerSocketName = "tm-dialog2";
