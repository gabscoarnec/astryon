pub const SystemCall = enum(u64) {
    Print,
    AllocFrame,
    LockFrame,
    FreeFrame,
    Yield,
    SetPriority,
    GetPriority,
    Sleep,
    SetEventQueue,
};

pub const SystemError = error{
    OutOfMemory,
    NoSuchThread,
};
