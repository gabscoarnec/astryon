const kernel = @import("kernel.zig");
const target = @import("builtin").target;

fn syscall(num: kernel.SystemCall, arg0: u64, arg1: u64) i64 {
    return switch (target.cpu.arch) {
        .x86_64 => asm volatile ("int $66"
            : [result] "={rax}" (-> i64),
            : [num] "{rax}" (@intFromEnum(num)),
              [arg0] "{rdi}" (arg0),
              [arg1] "{rsi}" (arg1),
        ),
        else => @compileError("unsupported architecture"),
    };
}

pub fn print(arg: u64) void {
    _ = syscall(.Print, arg, 0);
}

pub fn allocFrame() !usize {
    const retval = syscall(.AllocFrame, 0, 0);
    if (retval < 0) return error.OutOfMemory;
    return @bitCast(retval);
}

pub fn lockFrame(address: u64) void {
    _ = syscall(.LockFrame, address, 0);
}

pub fn freeFrame(address: u64) void {
    _ = syscall(.FreeFrame, address, 0);
}

pub fn yield() void {
    _ = syscall(.Yield, 0, 0);
}

pub fn setPriority(priority: u8) void {
    _ = syscall(.SetPriority, priority, 0);
}

pub fn getPriority() u8 {
    return @truncate(@as(u64, @bitCast(syscall(.GetPriority, 0, 0))));
}

pub fn sleep(ms: u64) void {
    _ = syscall(.Sleep, ms, 0);
}

pub fn setEventQueue(pid: u64, address: u64) !void {
    const retval = syscall(.SetEventQueue, pid, address);
    if (retval < 0) return error.NoSuchThread;
}

pub fn setTokens(pid: u64, tokens: u64) !void {
    const retval = syscall(.SetTokens, pid, tokens);
    if (retval < 0) return error.NoSuchThread;
}
