const std = @import("std");
const syscalls = @import("syscalls.zig");

const KernelWriter = struct {
    const Writer = std.io.Writer(
        *KernelWriter,
        error{},
        write,
    );

    fn write(
        _: *KernelWriter,
        data: []const u8,
    ) error{}!usize {
        syscalls.print(data);
        return data.len;
    }

    fn writer(self: *KernelWriter) Writer {
        return .{ .context = self };
    }
};

/// Print a formatted string to the kernel's log.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var kernel_writer = KernelWriter{};
    var writer = kernel_writer.writer();
    writer.print(fmt, args) catch return;
}
