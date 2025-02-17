const SystemCall = enum(u64) {
    Print,
    AllocFrame,
    LockFrame,
    FreeFrame,
    Yield,
    SetPriority,
    GetPriority,
};

const SystemError = error{
    OutOfMemory,
};

fn syscall(num: SystemCall, arg: u64) i64 {
    return asm volatile ("int $66"
        : [result] "=r" (-> i64),
        : [num] "{rax}" (@intFromEnum(num)),
          [arg] "{rdi}" (arg),
    );
}

pub fn print(arg: u64) void {
    _ = syscall(.Print, arg);
}

pub fn allocFrame() !usize {
    const retval = syscall(.AllocFrame, 0);
    if (retval < 0) return error.OutOfMemory;
    return @bitCast(retval);
}

pub fn lockFrame(address: u64) void {
    _ = syscall(.LockFrame, address);
}

pub fn freeFrame(address: u64) void {
    _ = syscall(.FreeFrame, address);
}

pub fn yield() void {
    _ = syscall(.Yield, 0);
}

pub fn setPriority(priority: u8) void {
    _ = syscall(.SetPriority, priority);
}

pub fn getPriority() u8 {
    return @truncate(@as(u64, @bitCast(syscall(.GetPriority, 0))));
}
