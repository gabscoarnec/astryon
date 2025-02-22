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
    SetTokens,
    SetAddressSpace,
};

pub const Token = enum(u64) {
    Root = 1 << 0,
    PhysicalMemory = 1 << 1,
    ThreadPriority = 1 << 2,
    EventQueue = 1 << 3,
    VirtualMemory = 1 << 4,
};

pub const SystemError = error{
    OutOfMemory,
    NoSuchThread,
    NotAuthorized,
};
