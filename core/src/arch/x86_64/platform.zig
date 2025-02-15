const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const pic = @import("pic.zig");
const interrupts = @import("interrupts.zig");

pub const PAGE_SIZE = 4096;

// FIXME: Check if it's supported first.
fn enableNX() void {
    asm volatile (
        \\ mov $0xC0000080, %rcx
        \\ rdmsr
        \\ or $0x800, %eax
        \\ wrmsr
    );
}

// Initialize platform-specific components.
pub fn platformInit() void {
    gdt.setupGDT();
    idt.setupIDT();
    enableNX();
}

// Initialize platform-specific components just before beginning multitasking.
pub fn platformEndInit() void {
    pic.remapPIC();
    interrupts.syncInterrupts();
    interrupts.enableInterrupts();
}
