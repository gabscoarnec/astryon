const std = @import("std");
const platform = @import("platform.zig");

const GDTR align(4096) = packed struct {
    size: u16,
    offset: u64,
};

const GDTEntry = packed struct {
    limit0: u16,
    base0: u16,
    base1: u8,
    access: u8,
    limit1_flags: u8,
    base2: u8,
};

fn createGDTEntry(limit0: u16, base0: u16, base1: u8, access: u8, limit1_flags: u8, base2: u8) GDTEntry {
    return GDTEntry{
        .limit0 = limit0,
        .base0 = base0,
        .base1 = base1,
        .access = access,
        .limit1_flags = limit1_flags,
        .base2 = base2,
    };
}

const HighGDTEntry = packed struct {
    base_high: u32,
    reserved: u32,
};

const GlobalDescriptorTable = packed struct {
    null: GDTEntry,
    kernel_code: GDTEntry,
    kernel_data: GDTEntry,
    user_code: GDTEntry,
    user_data: GDTEntry,
    tss: GDTEntry,
    tss2: HighGDTEntry,
};

fn setBase(entry: *GDTEntry, base: u32) void {
    entry.base0 = @intCast(base & 0xFFFF);
    entry.base1 = @intCast((base >> 16) & 0xFF);
    entry.base2 = @intCast((base >> 24) & 0xFF);
}

fn setLimit(entry: *GDTEntry, limit: u20) void {
    entry.limit0 = @intCast(limit & 0xFFFF);
    entry.limit1_flags = (entry.limit1_flags & 0xF0) | (@as(u8, @intCast(limit >> 16)) & 0xF);
}

fn setTSSBase(tss1: *GDTEntry, tss2: *HighGDTEntry, addr: u64) void {
    setBase(tss1, @intCast(addr & 0xffffffff));
    tss2.base_high = @intCast(addr >> 32);
}

const TSS = packed struct {
    reserved0: u32,
    rsp0: u64,
    rsp1: u64,
    rsp2: u64,
    reserved1: u64,
    ist0: u64,
    ist1: u64,
    ist2: u64,
    ist3: u64,
    ist4: u64,
    ist5: u64,
    ist6: u64,
    reserved2: u64,
    reserved3: u16,
    iomap_base: u16,
};

fn stackTop(begin: usize, size: usize) usize {
    return (begin + size) - 16;
}

fn setupTSS(gdt: *GlobalDescriptorTable, tss: *TSS, stack: [*]u8, stack_length: usize) void {
    tss.iomap_base = @sizeOf(TSS);
    tss.ist0 = stackTop(@intFromPtr(stack), stack_length);
    setTSSBase(&gdt.tss, &gdt.tss2, @intFromPtr(tss));
    setLimit(&gdt.tss, @sizeOf(TSS) - 1);
}

fn loadGDT() callconv(.Naked) void {
    asm volatile (
        \\ cli
        \\ lgdt (%rdi)
        \\ mov   $0x10, %ax
        \\ mov   %ax, %ds
        \\ mov   %ax, %es
        \\ mov   %ax, %fs
        \\ mov   %ax, %gs
        \\ mov   %ax, %ss
        \\ push $8
        \\ lea .reload_CS(%rip), %rax
        \\ push %rax
        \\ lretq
        \\.reload_CS:
        \\ ret
    );
}

fn loadTR() callconv(.Naked) void {
    asm volatile (
        \\ mov %rdi, %rax
        \\ ltr %ax
        \\ ret
    );
}

/// Setup the Global Descriptor Table.
pub fn setupGDT() void {
    // Store all these as static variables, as they won't be needed outside this function but need to stay alive.
    const state = struct {
        var gdt = GlobalDescriptorTable{ .null = std.mem.zeroes(GDTEntry), .kernel_code = createGDTEntry(0xffff, 0x0000, 0x00, 0x9a, 0xaf, 0x00), .kernel_data = createGDTEntry(0xffff, 0x0000, 0x00, 0x92, 0xcf, 0x00), .user_code = createGDTEntry(0xffff, 0x0000, 0x00, 0xfa, 0xaf, 0x00), .user_data = createGDTEntry(0xffff, 0x0000, 0x00, 0xf2, 0xcf, 0x00), .tss = createGDTEntry(0x0000, 0x0000, 0x00, 0xe9, 0x0f, 0x00), .tss2 = HighGDTEntry{ .base_high = 0x00000000, .reserved = 0x00000000 } };
        var gdtr = std.mem.zeroes(GDTR);
        var tss = std.mem.zeroes(TSS);
        var alternate_stack: [platform.PAGE_SIZE * 4]u8 = std.mem.zeroes([platform.PAGE_SIZE * 4]u8);
    };

    state.gdtr.offset = @intFromPtr(&state.gdt);
    state.gdtr.size = @sizeOf(GlobalDescriptorTable);
    setupTSS(&state.gdt, &state.tss, @ptrCast(&state.alternate_stack[0]), @sizeOf(@TypeOf(state.alternate_stack)));

    // Hackish way to call naked functions which we know conform to SysV ABI.
    const lgdt: *const fn (g: *GDTR) callconv(.C) void = @ptrCast(&loadGDT);
    lgdt(&state.gdtr);
    const ltr: *const fn (t: u16) callconv(.C) void = @ptrCast(&loadTR);
    ltr(0x2b);
}
