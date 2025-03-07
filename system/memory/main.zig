const system = @import("system");

const vm = system.vm;
const syscalls = system.syscalls;

fn setTokens() void {
    var tokens: u64 = 0;
    tokens |= @intFromEnum(system.kernel.Token.PhysicalMemory);
    syscalls.setTokens(syscalls.getThreadId(), tokens) catch {};
}

export fn _start(_: u64, ipc_base: u64) callconv(.C) noreturn {
    setTokens();

    var connection = system.ipc.readInitBuffers(ipc_base);

    const byte: u8 = 127;

    _ = connection.write_buffer.write(@ptrCast(&byte), 1);
    syscalls.yield();

    while (true) {}
}
