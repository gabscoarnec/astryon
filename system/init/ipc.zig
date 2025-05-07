const std = @import("std");
const system = @import("system");
const thread = @import("thread.zig");
const memory = @import("memory.zig");

const syscalls = system.syscalls;
const init = system.services.init;
const vm = system.vm;

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
            try context.name_map.put(address, connection.port.pid);
            context.sender.address = address;

            system.io.print("init: PID {d}, channel {d} successfully bound to address {s}\n", .{ connection.port.pid, connection.port.channel, address });
        } else {
            context.allocator.free(address);
        }
    }
}

fn handlePrintMessage(connection: *system.ipc.Connection, context: *Context) anyerror!void {
    if (connection.read(init.PrintMessage)) |message| {
        system.io.print("init: Message from {s} (PID {d}, channel {d}): {s}\n", .{ context.sender.address orelse "system.unregistered", connection.port.pid, connection.port.channel, std.mem.sliceTo(&message.message, 0) });
    }
}

fn handleMapMessage(connection: *system.ipc.Connection, context: *Context) anyerror!void {
    if (connection.read(init.MapMessage)) |message| {
        const map = &context.sender.memory_map;
        const mapper = context.sender.mapper;

        const count = try std.math.divCeil(u64, message.length, vm.PAGE_SIZE);

        const address = memory.allocRegion(context.allocator, map, count, .{ .prot = message.prot, .flags = message.flags, .persistent = false, .used = true }) orelse return error.OutOfMemory;

        var flags: u32 = @intFromEnum(vm.Flags.User);
        if ((message.prot & @intFromEnum(init.MapProt.PROT_WRITE)) > 0) flags |= @intFromEnum(vm.Flags.ReadWrite);
        if ((message.prot & @intFromEnum(init.MapProt.PROT_EXEC)) == 0) flags |= @intFromEnum(vm.Flags.NoExecute);

        var i: u64 = 0;
        while (i < count) : (i += 1) {
            const frame = try syscalls.allocFrame();
            try vm.map(&mapper, address + (i * vm.PAGE_SIZE), .{ .address = frame }, flags);
        }

        connection.reply(usize, &address);
    }
}

fn handleUnmapMessage(connection: *system.ipc.Connection, context: *Context) anyerror!void {
    if (connection.read(init.UnmapMessage)) |message| {
        const map = &context.sender.memory_map;
        const mapper = context.sender.mapper;

        const count = try std.math.divCeil(u64, message.length, vm.PAGE_SIZE);

        const success = try memory.updateRegion(context.allocator, map, message.address, count, .{ .prot = 0, .flags = 0, .persistent = false, .used = false }, false);
        if (!success) {
            system.io.print("Failed to free memory region starting at {x} for {d} pages\n", .{ message.address, count });
            return;
        }

        var i: u64 = 0;
        while (i < count) : (i += 1) {
            const frame = try vm.unmap(&mapper, message.address + (i * vm.PAGE_SIZE));
            syscalls.freeFrame(frame.address);
        }
    }
}

pub fn setupMessageTable(allocator: std.mem.Allocator) !system.ipc.MessageHandlerTable {
    var table = system.ipc.MessageHandlerTable.init(allocator);
    errdefer table.deinit();

    try table.put(@intFromEnum(init.MessageType.Bind), @ptrCast(&handleBindMessage));
    try table.put(@intFromEnum(init.MessageType.Print), @ptrCast(&handlePrintMessage));
    try table.put(@intFromEnum(init.MessageType.Map), @ptrCast(&handleMapMessage));
    try table.put(@intFromEnum(init.MessageType.Unmap), @ptrCast(&handleUnmapMessage));

    return table;
}
