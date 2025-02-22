pub const SystemCall = enum(u64) {
    Print,
    AllocFrame, // requires Token.PhysicalMemory
    LockFrame, // requires Token.PhysicalMemory
    FreeFrame, // requires Token.PhysicalMemory
    Yield,
    SetPriority, // requires Token.ThreadPriority
    GetPriority,
    Sleep,
    SetEventQueue, // requires Token.EventQueue
    SetTokens, // requires Token.Root
    SetAddressSpace, // requires Token.VirtualMemory
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
