const std = @import("std");

const IDTEntry = packed struct {
    offset0: u16,
    selector: u16,
    ist: u8,
    type_attr: u8,
    offset1: u16,
    offset2: u32,
    ignore: u32,
};

fn setOffset(entry: *IDTEntry, offset: u64) void {
    entry.offset0 = @as(u16, @intCast(offset & 0x000000000000ffff));
    entry.offset1 = @as(u16, @intCast((offset & 0x00000000ffff0000) >> 16));
    entry.offset2 = @as(u32, @intCast((offset & 0xffffffff00000000) >> 32));
}

fn getOffset(entry: *IDTEntry) u64 {
    var offset: u64 = 0;
    offset |= @as(u64, entry.offset0);
    offset |= @as(u64, entry.offset1) << 16;
    offset |= @as(u64, entry.offset2) << 32;
    return offset;
}

const IDT_TA_InterruptGate = 0b10001110;
const IDT_TA_UserCallableInterruptGate = 0b11101110;
const IDT_TA_TrapGate = 0b10001111;

const IDTR = packed struct {
    limit: u16,
    offset: u64,
};

fn addIDTHandler(idt: *[256]IDTEntry, num: u32, handler: *const anyopaque, type_attr: u8, ist: u8) void {
    var entry_for_handler: *IDTEntry = &idt.*[num];
    entry_for_handler.selector = 0x08;
    entry_for_handler.type_attr = type_attr;
    entry_for_handler.ist = ist;
    setOffset(entry_for_handler, @intFromPtr(handler));
}

fn createISRHandler(comptime num: u32) *const fn () callconv(.Naked) void {
    return struct {
        fn handler() callconv(.Naked) void {
            asm volatile (
                \\ push $0
                \\ push %[num]
                \\ jmp asmInterruptEntry
                :
                : [num] "n" (num),
            );
        }
    }.handler;
}

fn createISRHandlerWithErrorCode(comptime num: u32) *const fn () callconv(.Naked) void {
    return struct {
        fn handler() callconv(.Naked) void {
            asm volatile (
                \\ push %[num]
                \\ jmp asmInterruptEntry
                :
                : [num] "n" (num),
            );
        }
    }.handler;
}

fn createIRQHandler(comptime num: u32, comptime irq: u32) *const fn () callconv(.Naked) void {
    return struct {
        fn handler() callconv(.Naked) void {
            asm volatile (
                \\ push %[irq]
                \\ push %[num]
                \\ jmp asmInterruptEntry
                :
                : [num] "n" (num),
                  [irq] "n" (irq),
            );
        }
    }.handler;
}

/// Setup the Interrupt Descriptor Table.
pub fn setupIDT() void {
    // Store these as static variables, as they won't be needed outside this function but need to stay alive.
    const state = struct {
        var idtr = std.mem.zeroes(IDTR);
        var idt: [256]IDTEntry = std.mem.zeroes([256]IDTEntry);
    };

    comptime var i: u32 = 0;

    // ISR 0-7 (no error code)
    inline while (i < 8) : (i += 1) {
        const handler: *const anyopaque = @ptrCast(createISRHandler(i));
        addIDTHandler(&state.idt, i, handler, IDT_TA_TrapGate, 1);
    }

    // ISR 8 #DF (error code)
    const handler_8: *const anyopaque = @ptrCast(createISRHandlerWithErrorCode(8));
    addIDTHandler(&state.idt, 8, handler_8, IDT_TA_TrapGate, 1);

    // ISR 9 obsolete

    i = 10;
    // ISR 10-14 (error code)
    inline while (i < 15) : (i += 1) {
        const handler: *const anyopaque = @ptrCast(createISRHandlerWithErrorCode(i));
        addIDTHandler(&state.idt, i, handler, IDT_TA_TrapGate, 1);
    }

    // ISR 15 reserved

    // ISR 16 #MF (no error code)
    const handler_16: *const anyopaque = @ptrCast(createISRHandler(16));
    addIDTHandler(&state.idt, 16, handler_16, IDT_TA_TrapGate, 1);

    // ISR 17 #AC (error code)
    const handler_17: *const anyopaque = @ptrCast(createISRHandlerWithErrorCode(17));
    addIDTHandler(&state.idt, 17, handler_17, IDT_TA_TrapGate, 1);

    i = 18;
    // ISR 18-20 (no error code)
    inline while (i < 21) : (i += 1) {
        const handler: *const anyopaque = @ptrCast(createISRHandler(i));
        addIDTHandler(&state.idt, i, handler, IDT_TA_TrapGate, 1);
    }

    // ISR 21 #CP (error code)
    const handler_21: *const anyopaque = @ptrCast(createISRHandlerWithErrorCode(21));
    addIDTHandler(&state.idt, 21, handler_21, IDT_TA_TrapGate, 1);

    // ISR 22-31 reserved

    i = 0;
    // ISR 32-47 (IRQs 0-16 after remapping the PIC)
    inline while (i < 16) : (i += 1) {
        const handler: *const anyopaque = @ptrCast(createIRQHandler(32 + i, i));
        addIDTHandler(&state.idt, 32 + i, handler, IDT_TA_InterruptGate, 0);
    }

    // ISR 66 (syscall)
    const sys_handler: *const anyopaque = @ptrCast(createISRHandler(66));
    addIDTHandler(&state.idt, 66, sys_handler, IDT_TA_UserCallableInterruptGate, 0);

    state.idtr.limit = 0x0FFF;
    state.idtr.offset = @intFromPtr(&state.idt[0]);

    asm volatile ("lidt (%[idtr])"
        :
        : [idtr] "{rax}" (&state.idtr),
    );
}
