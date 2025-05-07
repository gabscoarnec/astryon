const std = @import("std");
const syscalls = @import("../syscalls.zig");
const ipc = @import("../ipc.zig");

pub const MessageType = enum(u8) {
    Bind = 0,
    Print = 1,
    Map = 2,
    Unmap = 3,
};

pub const BindMessage = struct {
    address: [64]u8,
};

pub const PrintMessage = struct {
    message: [128]u8,
};

pub const MapMessage = packed struct {
    length: usize,
    prot: i32,
    flags: i32,
};

pub const UnmapMessage = packed struct {
    address: u64,
    length: usize,
};

pub fn bind(connection: *ipc.Connection, address: []const u8) void {
    var bind_settings = BindMessage{ .address = std.mem.zeroes([64]u8) };
    @memcpy(bind_settings.address[0..address.len], address);

    connection.sendMessageAsync(@TypeOf(bind_settings), @intFromEnum(MessageType.Bind), &bind_settings);
}

pub fn print(connection: *ipc.Connection, message: []const u8) void {
    var print_data = PrintMessage{ .message = std.mem.zeroes([128]u8) };
    @memcpy(print_data.message[0..message.len], message);

    connection.sendMessageAsync(@TypeOf(print_data), @intFromEnum(MessageType.Print), &print_data);
}

pub fn map(connection: *ipc.Connection, length: usize, prot: i32, flags: i32) ?u64 {
    var map_data = MapMessage{ .length = length, .prot = prot, .flags = flags };

    connection.sendMessageSync(@TypeOf(map_data), @intFromEnum(MessageType.Map), &map_data);

    var result: ?i64 = connection.read(i64);
    while (result == null) {
        syscalls.yield();
        result = connection.read(i64);
    }

    if (result.? < 0) return null;
    return @bitCast(result.?);
}

pub fn unmap(connection: *ipc.Connection, address: u64, length: usize) void {
    var unmap_data = UnmapMessage{ .address = address, .length = length };

    connection.sendMessageAsync(@TypeOf(unmap_data), @intFromEnum(MessageType.Unmap), &unmap_data);
}

pub const MapProt = enum(i32) {
    PROT_NONE = 0,
    PROT_READ = 1,
    PROT_WRITE = 2,
    PROT_EXEC = 4,
};

pub const MapFlags = enum(i32) {
    MAP_PRIVATE = 0,
    MAP_SHARED = 1,
    MAP_ANONYMOUS = 2,
};
