const system = @import("system");

const vm = system.vm;
const syscalls = system.syscalls;

fn setTokens() void {
    var tokens: u64 = 0;
    tokens |= @intFromEnum(system.kernel.Token.PhysicalMemory);
    syscalls.setTokens(syscalls.getThreadId(), tokens) catch {};
}

export fn _start(_: u64, _: u64) callconv(.C) noreturn {
    setTokens();

    while (true) {}
}
