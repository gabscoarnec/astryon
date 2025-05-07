pub const SystemCall = enum(u64) {
    Print,
    AllocFrame, // requires Token.PhysicalMemory
    LockFrame, // requires Token.PhysicalMemory
    FreeFrame, // requires Token.PhysicalMemory
    Yield,
    SetPriority, // requires Token.ThreadPriority
    GetPriority,
    Sleep,
    SetEventQueue, // requires Token.CreateProcess
    SetTokens, // requires Token.Root
    SetAddressSpace, // requires Token.CreateProcess
    CreateThread, // requires Token.CreateProcess
    SetThreadEntry, // requires Token.CreateProcess
    SetThreadArguments, // requires Token.CreateProcess
    SetThreadStack, // requires Token.CreateProcess
    StartThread, // requires Token.CreateProcess
    GetThreadId,
    GetAddressSpace, // requires Token.CreateProcess
    Send,
    AsyncSend,
    Wait,
    Reply,
};

pub const Token = enum(u64) {
    Root = 1 << 0,
    PhysicalMemory = 1 << 1,
    ThreadPriority = 1 << 2,
    CreateProcess = 1 << 3,
};

pub const SystemError = error{
    OutOfMemory,
    NoSuchThread,
    NotAuthorized,
};

pub const KernelMessage = enum(u8) {
    MessageReceived = 0,
};
