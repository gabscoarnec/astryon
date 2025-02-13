const std = @import("std");
const target = @import("builtin").target;

const arch = switch (target.cpu.arch) {
    .x86_64 => @import("x86_64/debug.zig"),
    else => {
        @compileError("unsupported architecture");
    },
};

const DebugWriter = struct {
    const Writer = std.io.Writer(
        *DebugWriter,
        error{},
        write,
    );

    fn write(
        _: *DebugWriter,
        data: []const u8,
    ) error{}!usize {
        return arch.write(data);
    }

    fn writer(self: *DebugWriter) Writer {
        return .{ .context = self };
    }
};

/// Print a formatted string to the platform's debug output.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var debug_writer = DebugWriter{};
    var writer = debug_writer.writer();
    writer.print(fmt, args) catch return;
}
