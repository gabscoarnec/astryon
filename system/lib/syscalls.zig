const kernel = @import("kernel.zig");
const target = @import("builtin").target;

fn syscall(num: kernel.SystemCall, arg0: u64, arg1: u64, arg2: u64) i64 {
    return switch (target.cpu.arch) {
        .x86_64 => asm volatile ("int $66"
            : [result] "={rax}" (-> i64),
            : [num] "{rax}" (@intFromEnum(num)),
              [arg0] "{rdi}" (arg0),
              [arg1] "{rsi}" (arg1),
              [arg2] "{rdx}" (arg2),
        ),
        else => @compileError("unsupported architecture"),
    };
}

pub fn print(arg: u64) void {
    _ = syscall(.Print, arg, 0, 0);
}

pub fn allocFrame() !usize {
    const retval = syscall(.AllocFrame, 0, 0, 0);
    if (retval < 0) return error.OutOfMemory;
    return @bitCast(retval);
}

pub fn lockFrame(address: u64) void {
    _ = syscall(.LockFrame, address, 0, 0);
}

pub fn freeFrame(address: u64) void {
    _ = syscall(.FreeFrame, address, 0, 0);
}

pub fn yield() void {
    _ = syscall(.Yield, 0, 0, 0);
}

pub fn setPriority(pid: u64, priority: u8) !void {
    const retval = syscall(.SetPriority, pid, priority, 0);
    if (retval < 0) return error.NoSuchThread;
}

pub fn getPriority(pid: u64) !u8 {
    const retval = syscall(.GetPriority, pid, 0, 0);
    if (retval < 0) return error.NoSuchThread;
    return @truncate(@as(u64, @bitCast(retval)));
}

pub fn sleep(ms: u64) void {
    _ = syscall(.Sleep, ms, 0, 0);
}

pub fn setEventQueue(pid: u64, address: u64) !void {
    const retval = syscall(.SetEventQueue, pid, address, 0);
    if (retval < 0) return error.NoSuchThread;
}

pub fn setTokens(pid: u64, tokens: u64) !void {
    const retval = syscall(.SetTokens, pid, tokens, 0);
    if (retval < 0) return error.NoSuchThread;
}

pub fn setAddressSpace(pid: u64, address: u64) !void {
    const retval = syscall(.SetAddressSpace, pid, address, 0);
    if (retval < 0) return error.NoSuchThread;
}

pub fn createThread() !u64 {
    const retval = syscall(.CreateThread, 0, 0, 0);
    if (retval < 0) return error.NoSuchThread;
    return @bitCast(retval);
}

pub fn setThreadEntry(pid: u64, entry: u64) !void {
    const retval = syscall(.SetThreadEntry, pid, entry, 0);
    if (retval < 0) return error.NoSuchThread;
}

pub fn setThreadArguments(pid: u64, arg0: u64, arg1: u64) !void {
    const retval = syscall(.SetThreadArguments, pid, arg0, arg1);
    if (retval < 0) return error.NoSuchThread;
}

pub fn setThreadStack(pid: u64, stack: u64) !void {
    const retval = syscall(.SetThreadStack, pid, stack, 0);
    if (retval < 0) return error.NoSuchThread;
}

pub fn startThread(pid: u64) !void {
    const retval = syscall(.StartThread, pid, 0, 0);
    if (retval < 0) return error.NoSuchThread;
}

pub fn getThreadId() u64 {
    return @bitCast(syscall(.GetThreadId, 0, 0, 0));
}

pub fn getAddressSpace(pid: u64) !u64 {
    const retval = syscall(.GetAddressSpace, pid, 0, 0);
    if (retval < 0) return error.NoSuchThread;
    return @bitCast(retval);
}

pub fn send(pid: u64) void {
    _ = syscall(.Send, pid, 0, 0);
}

pub fn asyncSend(pid: u64) void {
    _ = syscall(.AsyncSend, pid, 0, 0);
}

pub fn wait() void {
    _ = syscall(.Wait, 0, 0, 0);
}
