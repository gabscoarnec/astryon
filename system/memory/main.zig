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

    var byte: u8 = 127;

    while (byte > 0) : (byte -= 1) {
        _ = connection.write(u8, &byte);
        syscalls.asyncSend(1);
    }

    while (true) {}
}
