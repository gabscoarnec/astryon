const io = @import("ioports.zig");

const PIC1_COMMAND = 0x20;
const PIC1_DATA = 0x21;
const PIC2_COMMAND = 0xA0;
const PIC2_DATA = 0xA1;
const PIC_EOI = 0x20;

const ICW1_INIT = 0x10;
const ICW1_ICW4 = 0x01;
const ICW4_8086 = 0x01;

inline fn ioDelay() void {
    io.outb(0x80, 0);
}

/// Remap the PIC so that all IRQs are remapped to 0x20-0x2f.
pub fn remapPIC() void {
    io.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);
    ioDelay();
    io.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    ioDelay();

    io.outb(PIC1_DATA, 0x20);
    ioDelay();

    io.outb(PIC2_DATA, 0x28);
    ioDelay();

    io.outb(PIC1_DATA, 4);
    ioDelay();
    io.outb(PIC2_DATA, 2);
    ioDelay();

    io.outb(PIC1_DATA, ICW4_8086);
    ioDelay();
    io.outb(PIC2_DATA, ICW4_8086);
    ioDelay();

    changePICMasks(0b11111111, 0b11111111);
}

/// Update the PIC masks.
pub fn changePICMasks(pic1_mask: u8, pic2_mask: u8) void {
    io.outb(PIC1_DATA, pic1_mask);
    ioDelay();
    io.outb(PIC2_DATA, pic2_mask);
    ioDelay();
}

/// Send an end-of-interrupt signal to the PIC.
pub fn picEOI(irq: u8) void {
    if (irq >= 8) io.outb(PIC2_COMMAND, PIC_EOI);
    io.outb(PIC1_COMMAND, PIC_EOI);
}
