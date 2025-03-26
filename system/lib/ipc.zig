const std = @import("std");
const buffer = @import("ring_buffer.zig");
const vm = @import("arch/vm.zig");

pub const Connection = struct {
    pid: u64,
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
        if (!self.write(u8, &id)) success = false;
        if (!self.write(T, in)) success = false;
        return success;
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

pub fn readInitBuffers(base_address: u64) Connection {
    kernel_buffer = createPageBufferFromAddress(base_address + KERNEL_BUFFER_ADDRESS_OFFSET);
    var read_buffer = createPageBufferFromAddress(base_address + INIT_READ_BUFFER_ADDRESS_OFFSET);
    const write_buffer = createPageBufferFromAddress(base_address + INIT_WRITE_BUFFER_ADDRESS_OFFSET);

    var pid: u64 = undefined;
    _ = read_buffer.readType(u64, &pid);

    return .{ .pid = pid, .read_buffer = read_buffer, .write_buffer = write_buffer };
}

pub const MessageHandler = *const fn (connection: *Connection, context: *anyopaque) anyerror!void;
pub const MessageHandlerTable = std.AutoHashMap(u8, MessageHandler);

pub fn handleMessage(connection: *Connection, map: *MessageHandlerTable, context: *anyopaque) bool {
    if (connection.read(u8)) |message_type| {
        const function = (map.getPtr(message_type) orelse return true).*;
        function(connection, context) catch {};
    } else return false;
}
