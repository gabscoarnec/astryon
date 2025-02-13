const std = @import("std");
const pic = @import("pic.zig");
const debug = @import("../debug.zig");
const sys = @import("../../sys/syscall.zig");

pub const InterruptStackFrame = packed struct {
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rbp: u64,
    rdi: u64,
    rsi: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
    isr: u64,
    error_or_irq: u64,
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,
};

const IRQHandler = *const fn (u32, *InterruptStackFrame) void;

var irq_handlers: [16]?IRQHandler = std.mem.zeroes([16]?IRQHandler);

export fn asmInterruptEntry() callconv(.Naked) void {
    asm volatile (
        \\ push %rax
        \\ push %rbx
        \\ push %rcx
        \\ push %rdx
        \\ push %rsi
        \\ push %rdi
        \\ push %rbp
        \\ push %r8
        \\ push %r9
        \\ push %r10
        \\ push %r11
        \\ push %r12
        \\ push %r13
        \\ push %r14
        \\ push %r15
        \\ cld
        \\ mov %rsp, %rdi
        \\ call interruptEntry
        \\asmInterruptExit:
        \\ pop %r15
        \\ pop %r14
        \\ pop %r13
        \\ pop %r12
        \\ pop %r11
        \\ pop %r10
        \\ pop %r9
        \\ pop %r8
        \\ pop %rbp
        \\ pop %rdi
        \\ pop %rsi
        \\ pop %rdx
        \\ pop %rcx
        \\ pop %rbx
        \\ pop %rax
        \\ add $16, %rsp
        \\ iretq
    );
}

const SYSCALL_INTERRUPT = 66;

export fn interruptEntry(frame: *InterruptStackFrame) callconv(.C) void {
    debug.print("Caught interrupt {d}\n", .{frame.isr});
    switch (frame.isr) {
        SYSCALL_INTERRUPT => {
            var args = sys.Arguments{ .arg0 = frame.rdi, .arg1 = frame.rsi, .arg2 = frame.rdx, .arg3 = frame.r10, .arg4 = frame.r8, .arg5 = frame.r9 };
            sys.invokeSyscall(frame.rax, frame, &args, @ptrFromInt(@as(usize, @intFromPtr(&frame.rax))));
        },
        else => {},
    }
}

/// Disable interrupts (except for NMIs).
pub fn disableInterrupts() void {
    asm volatile ("cli");
}

/// Enable interrupts.
pub fn enableInterrupts() void {
    asm volatile ("sti");
}

/// Check whether interrupts are enabled.
pub fn saveInterrupts() bool {
    var flags: u64 = 0;
    asm volatile ("pushfq; pop %[flags]"
        : [flags] "=r" (flags),
    );
    return (flags & 0x200) != 0;
}

/// Enable or disable interrupts depending on the boolean value passed.
pub fn restoreInterrupts(saved: bool) void {
    switch (saved) {
        true => {
            enableInterrupts();
        },
        false => {
            disableInterrupts();
        },
    }
}

/// Update the PIC masks according to which IRQ handlers are registered.
pub fn syncInterrupts() void {
    var pic1_mask: u8 = 0b11111111;
    var pic2_mask: u8 = 0b11111111;
    var i: u8 = 0;
    while (i < 8) : (i += 1) {
        if (irq_handlers[i] != null) pic1_mask &= (~(@as(u8, 1) << @as(u3, @intCast(i))));
        if (irq_handlers[i + 8] != null) pic2_mask &= (~(@as(u8, 1) << @as(u3, @intCast(i))));
    }

    if (pic2_mask != 0b11111111) pic1_mask &= 0b11111011;

    const saved: bool = saveInterrupts();
    disableInterrupts();
    pic.changePICMasks(pic1_mask, pic2_mask);
    restoreInterrupts(saved);
}

/// Register an IRQ handler.
pub fn registerIRQ(num: u32, handler: IRQHandler) bool {
    if (irq_handlers[num] != null) return false;

    irq_handlers[num] = handler;

    syncInterrupts();

    return true;
}
