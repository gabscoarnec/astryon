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

export fn _start(_: u64, ipc_base: u64) callconv(.C) noreturn {
    setTokens();

    var connection = system.ipc.readInitBuffers(ipc_base);
    init.bind(&connection, "os.astryon.memory");

    var byte: u64 = 127;

    while (byte > 0) : (byte -= 1) {
        var buffer = std.mem.zeroes([128]u8);
        const message = std.fmt.bufPrint(&buffer, "countdown {d}", .{byte}) catch {
            unreachable;
        };

        init.print(&connection, message);
    }

    while (true) {}
}
