pub const MessageType = enum(u8) {
    Hello = 0,
    Print = 1,
};

pub const HelloMessage = struct {
    address: [64]u8,
};

pub const PrintMessage = struct {
    number: u64,
};
