const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const pic = @import("pic.zig");
const interrupts = @import("interrupts.zig");

pub const PAGE_SIZE = 4096;

// Initialize platform-specific components.
pub fn platformInit() void {
    gdt.setupGDT();
    idt.setupIDT();
}

// Initialize platform-specific components just before beginning multitasking.
pub fn platformEndInit() void {
    pic.remapPIC();
    interrupts.syncInterrupts();
}
