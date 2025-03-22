const thread = @import("thread.zig");
const system = @import("system");

const syscalls = system.syscalls;

fn handleMessageFromThread(sender: *thread.Thread) !void {
    var data: u8 = undefined;
    if (sender.connection.read(u8, &data)) {
        syscalls.print(sender.connection.pid);
        syscalls.print(data);
    }
}
