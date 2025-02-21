const io = @import("ioports.zig");
const platform = @import("platform.zig");
const interrupts = @import("interrupts.zig");
const pic = @import("pic.zig");
const thread = @import("../../thread.zig");

// Every timer tick is equivalent to 1 millisecond.
const TIMER_RESOLUTION = 1;

const PIT_CHANNEL_0 = 0x40;

const base_frequency: u64 = 1193182;

pub fn initializePIT() void {
    const divisor: u16 = @intCast(base_frequency / (TIMER_RESOLUTION * 1000));
    if (divisor < 100) {
        @compileError("Timer resolution is too low");
    }

    io.outb(PIT_CHANNEL_0, @as(u8, @intCast(divisor & 0xFF)));
    io.outb(0x80, 0); // short delay
    io.outb(PIT_CHANNEL_0, @as(u8, @intCast((divisor & 0xFF00) >> 8)));

    _ = interrupts.registerIRQ(0, &pitTimerHandler);
}

pub fn pitTimerHandler(_: u32, regs: *platform.Registers) void {
    thread.preempt(regs);
}
