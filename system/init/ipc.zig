const std = @import("std");
const system = @import("system");
const thread = @import("thread.zig");

const syscalls = system.syscalls;
const init = system.services.init;

pub const Context = struct {
    sender: *thread.Thread,
    allocator: std.mem.Allocator,
    thread_list: *std.AutoHashMap(u64, thread.Thread),
    name_map: *std.StringHashMap(u64),
};

fn handleBindMessage(connection: *system.ipc.Connection, context: *Context) anyerror!void {
    if (connection.read(init.BindMessage)) |message| {
        const string = std.mem.sliceTo(message.address[0..], 0);
        const address = try context.allocator.dupeZ(u8, string);
        errdefer context.allocator.free(address);

        if (!context.name_map.contains(address)) {
            try context.name_map.put(address, connection.pid);
            context.sender.address = address;

            system.io.print("init: PID {d} successfully bound to address {s}\n", .{ connection.pid, address });
        } else {
            context.allocator.free(address);
        }
    }
}

fn handlePrintMessage(connection: *system.ipc.Connection, context: *Context) anyerror!void {
    if (connection.read(init.PrintMessage)) |message| {
        system.io.print("init: Message from {s} (PID {d}): {s}\n", .{ context.sender.address orelse "system.unregistered", connection.pid, std.mem.sliceTo(&message.message, 0) });
    }
}

pub fn setupMessageTable(allocator: std.mem.Allocator) !system.ipc.MessageHandlerTable {
    var table = system.ipc.MessageHandlerTable.init(allocator);
    errdefer table.deinit();

    try table.put(@intFromEnum(init.MessageType.Bind), @ptrCast(&handleBindMessage));
    try table.put(@intFromEnum(init.MessageType.Print), @ptrCast(&handlePrintMessage));

    return table;
}
