const std = @import("std");
const syscalls = @import("../syscalls.zig");
const ipc = @import("../ipc.zig");

pub const MessageType = enum(u8) {
    Bind = 0,
    Print = 1,
};

pub const BindMessage = struct {
    address: [64]u8,
};

pub const PrintMessage = struct {
    message: [128]u8,
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
