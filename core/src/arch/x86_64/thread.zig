const std = @import("std");
const platform = @import("platform.zig");

pub inline fn enterThread(regs: *platform.Registers, base: u64, directory: u64) noreturn {
    asm volatile (
        \\ addq %[base], %rsp
        \\ push %[ss]
        \\ push %[rsp]
        \\ push %[rflags]
        \\ push %[cs]
        \\ push %[rip]
        \\ mov %[directory], %cr3
        \\ mov $0, %rax
        \\ mov $0, %rbx
        \\ mov $0, %rcx
        \\ mov $0, %rdx
        \\ mov $0, %rbp
        \\ mov $0, %r8
        \\ mov $0, %r9
        \\ mov $0, %r10
        \\ mov $0, %r11
        \\ mov $0, %r12
        \\ mov $0, %r13
        \\ mov $0, %r14
        \\ mov $0, %r15
        \\ iretq
        :
        : [ss] "r" (regs.ss),
          [rsp] "r" (regs.rsp),
          [rflags] "r" (regs.rflags),
          [cs] "r" (regs.cs),
          [rip] "r" (regs.rip),
          [arg0] "{rdi}" (regs.rdi),
          [arg1] "{rsi}" (regs.rsi),
          [base] "r" (base),
          [directory] "r" (directory),
    );
    unreachable;
}

pub fn idleLoop() callconv(.Naked) noreturn {
    asm volatile (
        \\.loop:
        \\ sti
        \\ hlt
        \\ jmp .loop 
    );
}

pub inline fn readStackPointer() usize {
    return asm volatile (
        \\ mov %rsp, %[result]
        : [result] "=r" (-> usize),
    );
}

pub fn setAddress(regs: *platform.Registers, address: u64) void {
    regs.rip = address;
}

pub fn setArguments(regs: *platform.Registers, arg0: u64, arg1: u64) void {
    regs.rdi = arg0;
    regs.rsi = arg1;
}

pub fn setStack(regs: *platform.Registers, stack: u64) void {
    regs.rsp = stack;
}

pub fn initKernelRegisters(regs: *platform.Registers) void {
    regs.* = std.mem.zeroes(platform.Registers);
    regs.cs = 0x08;
    regs.ss = 0x10;
    regs.rflags = 1 << 9; // IF (Interrupt enable flag)
}

pub fn initUserRegisters(regs: *platform.Registers) void {
    regs.* = std.mem.zeroes(platform.Registers);
    regs.cs = 0x18 | 3;
    regs.ss = 0x20 | 3;
    regs.rflags = 1 << 9; // IF (Interrupt enable flag)
}
