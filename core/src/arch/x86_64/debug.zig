const io = @import("ioports.zig");

const COM1: u16 = 0x3f8;

fn serialWait() void {
    while ((io.inb(COM1 + 5) & 0x20) == 0) {
        asm volatile ("pause");
    }
}

fn serialPutchar(c: u8) void {
    serialWait();
    io.outb(COM1, c);
}

/// Write data to the platform's debug output.
pub fn write(s: []const u8) usize {
    for (s) |character| {
        serialPutchar(character);
    }

    return s.len;
}
