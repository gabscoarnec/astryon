const std = @import("std");
const buffer = @import("ring_buffer.zig");
const vm = @import("arch/vm.zig");
const syscalls = @import("syscalls.zig");

pub const ConnectionPort = struct {
    pid: u64,
    channel: u64,
};

pub const Connection = struct {
    port: ConnectionPort,
    read_buffer: buffer.RingBuffer,
    write_buffer: buffer.RingBuffer,

    pub fn read(self: *Connection, comptime T: type) ?T {
        var out: T = undefined;
        if (!self.read_buffer.readType(T, &out)) return null;
        return out;
    }

    pub fn write(self: *Connection, comptime T: type, in: *const T) bool {
        return self.write_buffer.writeType(T, in);
    }

    pub fn readBytes(self: *Connection, bytes: [*]u8, length: usize) bool {
        return self.read_buffer.read(bytes, length);
    }

    pub fn writeBytes(self: *Connection, bytes: []u8) bool {
        return self.write_buffer.writeSlice(bytes);
    }

    pub fn writeMessage(self: *Connection, comptime T: type, id: u8, in: *const T) bool {
        var success = true;
        if (self.write_buffer.bytesAvailableToWrite() < (@sizeOf(u8) + @sizeOf(T))) return false;
        if (!self.write(u8, &id)) success = false;
        if (!self.write(T, in)) success = false;
        return success;
    }

    pub fn sendMessageAsync(self: *Connection, comptime T: type, id: u8, in: *const T) void {
        while (!self.writeMessage(T, id, in)) syscalls.yield();

        syscalls.asyncSend(self.port.pid, self.port.channel);
    }

    pub fn sendMessageSync(self: *Connection, comptime T: type, id: u8, in: *const T) void {
        while (!self.writeMessage(T, id, in)) syscalls.yield();

        syscalls.send(self.port.pid, self.port.channel);
    }

    pub fn reply(self: *Connection, comptime T: type, in: *const T) void {
        while (!self.write(T, in)) syscalls.yield();
        syscalls.reply(self.port.pid);
    }
};

pub const KERNEL_BUFFER_ADDRESS_OFFSET = 0x0000;
pub const INIT_WRITE_BUFFER_ADDRESS_OFFSET = 0x1000;
pub const INIT_READ_BUFFER_ADDRESS_OFFSET = 0x2000;

var kernel_buffer: ?buffer.RingBuffer = null;

pub fn setKernelBuffer(buf: buffer.RingBuffer) void {
    kernel_buffer = buf;
}

pub fn getKernelBuffer() ?buffer.RingBuffer {
    return kernel_buffer;
}

const PAGE_SIZE = vm.PAGE_SIZE;

fn createPageBufferFromAddress(address: u64) buffer.RingBuffer {
    const data: [*]u8 = @ptrFromInt(address);

    return buffer.RingBuffer.init(data, PAGE_SIZE, false);
}

var init_connection: ?Connection = null;

pub fn readInitBuffers(base_address: u64) Connection {
    kernel_buffer = createPageBufferFromAddress(base_address + KERNEL_BUFFER_ADDRESS_OFFSET);
    var read_buffer = createPageBufferFromAddress(base_address + INIT_READ_BUFFER_ADDRESS_OFFSET);
    const write_buffer = createPageBufferFromAddress(base_address + INIT_WRITE_BUFFER_ADDRESS_OFFSET);

    var pid: u64 = undefined;
    _ = read_buffer.readType(u64, &pid);

    init_connection = .{ .port = .{ .pid = pid, .channel = 0 }, .read_buffer = read_buffer, .write_buffer = write_buffer };
    return init_connection.?;
}

pub fn getInitConnection() ?Connection {
    return init_connection;
}

pub const MessageHandler = *const fn (connection: *Connection, context: *anyopaque) anyerror!void;
pub const MessageHandlerTable = std.AutoHashMap(u8, MessageHandler);

pub fn handleMessage(connection: *Connection, map: *MessageHandlerTable, context: *anyopaque) bool {
    if (connection.read(u8)) |message_type| {
        const function = (map.getPtr(message_type) orelse return true).*;
        function(connection, context) catch {};
        return true;
    } else return false;
}

pub const ConnectionTable = struct {
    by_name: std.StringHashMap(Connection),
    by_port: std.AutoHashMap(ConnectionPort, Connection),
};

pub fn createConnectionTable(allocator: std.mem.Allocator) ConnectionTable {
    return .{
        .by_name = std.StringHashMap(Connection).init(allocator),
        .by_port = std.AutoHashMap(ConnectionPort, Connection).init(allocator),
    };
}

pub fn queryConnection(table: ?*ConnectionTable, name: []u8) ?Connection {
    if (std.mem.eql(u8, name, "astryon.init")) return init_connection;

    return table.?.by_name.get(name);
}
