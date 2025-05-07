const std = @import("std");
const system = @import("system");

const vm = system.vm;
const syscalls = system.syscalls;
const init = system.services.init;

fn setTokens() void {
    var tokens: u64 = 0;
    tokens |= @intFromEnum(system.kernel.Token.PhysicalMemory);
    syscalls.setTokens(syscalls.getThreadId(), tokens) catch {};
}

fn main() !void {
    setTokens();

    var connection = system.ipc.getInitConnection().?;
    init.bind(&connection, "os.astryon.memory");

    var allocator = system.system_allocator.allocator();

    const byte: *u64 = try allocator.create(u64);

    byte.* = 127;

    while (byte.* > 0) : (byte.* -= 1) {
        var buffer = std.mem.zeroes([128]u8);
        const message = try std.fmt.bufPrint(&buffer, "countdown {d}", .{byte.*});

        init.print(&connection, message);
    }

    allocator.destroy(byte);
}

export fn _start(_: u64, ipc_base: u64) callconv(.C) noreturn {
    system.runHosted(ipc_base, main);
}
