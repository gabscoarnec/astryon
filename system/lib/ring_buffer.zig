//! Single-producer single-consumer lockfree ring buffer, which supports reading and storing arbitrary amounts of bytes,
//! and which supports being stored in shared memory, for usage in IPC.

const std = @import("std");

pub const RingBuffer = struct {
    const Data = packed struct {
        read_index: u16,
        write_index: u16,
        data_start: u8,
    };

    capacity: u16,
    data: *Data,

    pub fn init(buffer: [*]u8, length: u16, initialize: bool) RingBuffer {
        const data: *Data = @alignCast(@ptrCast(buffer));

        if (initialize) {
            data.read_index = 0;
            data.write_index = 0;
        }

        const capacity = length - (@sizeOf(@TypeOf(data.read_index)) + @sizeOf(@TypeOf(data.write_index)));

        return .{ .capacity = capacity, .data = data };
    }

    pub fn write(self: *RingBuffer, data: [*]const u8, length: usize) bool {
        const available = self.bytesAvailableToWrite();
        var tail = @atomicLoad(u16, &self.data.write_index, .monotonic);

        const buffer = self.dataPointer();

        const bytes_to_write = length;
        if (bytes_to_write == 0) return false;
        if (bytes_to_write > available) return false;
        if (self.capacity <= tail) return false;

        var written: usize = 0;

        // Write first segment: from tail up to the end of the buffer.
        const first_chunk = @min(bytes_to_write, self.capacity - tail);
        @memcpy(buffer[tail .. tail + first_chunk], data[0..first_chunk]);
        written += first_chunk;
        tail = (tail + first_chunk) % self.capacity;

        // Write second segment if needed (wrap-around).
        if (written < bytes_to_write) {
            const second_chunk = bytes_to_write - written;
            @memcpy(buffer[0..second_chunk], data[first_chunk .. first_chunk + second_chunk]);
            tail = @intCast(second_chunk);
            written += second_chunk;
        }

        @atomicStore(u16, &self.data.write_index, tail, .release);
        return true;
    }

    fn read_impl(self: *RingBuffer, data: [*]u8, length: usize) ?u16 {
        const available = self.bytesAvailableToRead();
        var head = @atomicLoad(u16, &self.data.read_index, .monotonic);

        const buffer = self.dataPointer();

        const bytes_to_read = length;
        if (bytes_to_read == 0) return null;
        if (bytes_to_read > available) return null;
        if (self.capacity <= head) return null;

        var bytes_read: usize = 0;

        // Read first segment: from head up to the end of the buffer.
        const first_chunk = @min(bytes_to_read, self.capacity - head);
        @memcpy(data[0..first_chunk], buffer[head .. head + first_chunk]);
        bytes_read += first_chunk;
        head = (head + first_chunk) % self.capacity;

        // Read second segment if needed (wrap-around).
        if (bytes_read < bytes_to_read) {
            const second_chunk = bytes_to_read - bytes_read;
            @memcpy(data[first_chunk .. first_chunk + second_chunk], buffer[0..second_chunk]);
            head = @intCast(second_chunk);
            bytes_read += second_chunk;
        }

        return head;
    }

    pub fn peek(self: *RingBuffer, data: [*]u8, length: usize) bool {
        return switch (self.read_impl(data, length)) {
            null => false,
            else => true,
        };
    }

    pub fn read(self: *RingBuffer, data: [*]u8, length: usize) bool {
        const result = self.read_impl(data, length) orelse return false;

        @atomicStore(u16, &self.data.read_index, result, .release);

        return true;
    }

    pub fn readType(self: *RingBuffer, comptime T: type, out: *T) bool {
        return self.read(@ptrCast(out), @sizeOf(@TypeOf(out.*)));
    }

    pub fn peekType(self: *RingBuffer, comptime T: type, out: *T) bool {
        return self.peek(@ptrCast(out), @sizeOf(@TypeOf(out.*)));
    }

    pub fn writeType(self: *RingBuffer, comptime T: type, in: *const T) bool {
        return self.write(@ptrCast(in), @sizeOf(@TypeOf(in.*)));
    }

    pub fn writeSlice(self: *RingBuffer, bytes: []const u8) bool {
        return self.write(bytes.ptr, bytes.len);
    }

    fn dataPointer(self: *RingBuffer) [*]u8 {
        return @ptrCast(&self.data.data_start);
    }

    pub fn bytesAvailableToWrite(self: *RingBuffer) u16 {
        const head = @atomicLoad(u16, &self.data.read_index, .acquire);
        const tail = @atomicLoad(u16, &self.data.write_index, .monotonic);
        if (head >= self.capacity or tail >= self.capacity) return 0; // Who tampered with the indices??
        if (tail >= head) {
            return self.capacity - (tail - head) - 1;
        } else {
            return head - tail - 1;
        }
    }

    pub fn bytesAvailableToRead(self: *RingBuffer) u16 {
        const head = @atomicLoad(u16, &self.data.read_index, .monotonic);
        const tail = @atomicLoad(u16, &self.data.write_index, .acquire);
        if (head >= self.capacity or tail >= self.capacity) return 0; // Who tampered with the indices??
        if (tail >= head) {
            return tail - head;
        } else {
            return self.capacity - (head - tail);
        }
    }
};
