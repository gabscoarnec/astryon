const std = @import("std");
const easyboot = @cImport(@cInclude("easyboot.h"));
const debug = @import("arch/debug.zig");
const cpu = @import("arch/cpu.zig");
const platform = @import("arch/platform.zig").arch;
const interrupts = @import("arch/interrupts.zig").arch;
const vmm = @import("arch/vmm.zig").arch;
const multiboot = @import("multiboot.zig");
const pmm = @import("pmm.zig");
const thread = @import("thread.zig");
const elf = @import("elf.zig");

const MultibootInfo = [*c]u8;

const Context = struct {
    allocator: *pmm.FrameAllocator,
    directory: *vmm.PageDirectory,
    regs: *interrupts.InterruptStackFrame,
};

export fn _start(magic: u32, info: MultibootInfo) callconv(.C) noreturn {
    interrupts.disableInterrupts();

    if (magic != easyboot.MULTIBOOT2_BOOTLOADER_MAGIC) {
        debug.print("Invalid magic number: {x}\n", .{magic});
        while (true) {}
    }

    multiboot.parseMultibootTags(@ptrCast(info));

    platform.platformInit();

    const tag = multiboot.findMultibootTag(easyboot.multiboot_tag_mmap_t, @ptrCast(info)) orelse {
        debug.print("error: No memory map multiboot tag found!\n", .{});
        while (true) {}
        unreachable;
    };

    var allocator = pmm.initializeFrameAllocator(tag) catch |err| {
        debug.print("Error while initializing frame allocator: {}\n", .{err});
        while (true) {}
    };

    var dir: vmm.PageDirectory = std.mem.zeroes(vmm.PageDirectory);
    const base: usize = vmm.createInitialMappings(&allocator, tag, &dir) catch |err| {
        debug.print("Error while creating initial mappings: {}\n", .{err});
        while (true) {}
    };

    debug.print("Physical memory base mapping for init: {x}\n", .{base});

    const frame = pmm.allocFrame(&allocator) catch |err| {
        debug.print("Error while creating frame for user page directory: {}\n", .{err});
        while (true) {}
    };

    // At this point the physical address space is already mapped into kernel virtual memory.
    const init_directory: *vmm.PageDirectory = @ptrFromInt(frame.virtualAddress(vmm.PHYSICAL_MAPPING_BASE));
    init_directory.* = dir;

    cpu.setupCore(&allocator) catch |err| {
        debug.print("Error while setting up core-specific scheduler structures: {}\n", .{err});
        while (true) {}
    };

    const init = thread.createThreadControlBlock(&allocator) catch |err| {
        debug.print("Error while creating thread control block for init: {}\n", .{err});
        while (true) {}
    };

    init.directory = init_directory;
    thread.arch.initUserRegisters(&init.regs);
    thread.arch.setArgument(&init.regs, base);

    thread.addThreadToScheduler(cpu.thisCore(), init);

    const ctx = Context{ .allocator = &allocator, .directory = init_directory, .regs = &init.regs };

    multiboot.findMultibootTags(easyboot.multiboot_tag_module_t, @ptrCast(info), struct {
        fn handler(mod: *easyboot.multiboot_tag_module_t, c: *const anyopaque) void {
            const context: *const Context = @alignCast(@ptrCast(c));
            const name = "init";
            if (std.mem.eql(u8, mod.string()[0..name.len], name[0..name.len])) {
                const phys_frame = pmm.PhysFrame{ .address = mod.mod_start };
                debug.print("Loading init from module at address {x}, virtual {x}\n", .{ mod.mod_start, phys_frame.virtualAddress(vmm.PHYSICAL_MAPPING_BASE) });
                const entry = elf.loadElf(context.allocator, context.directory, pmm.PhysFrame{ .address = mod.mod_start }) catch |err| {
                    debug.print("Error while loading ELF file for init: {}\n", .{err});
                    while (true) {}
                };
                thread.arch.setAddress(context.regs, entry);
            }
        }
    }.handler, &ctx);

    const default_stack_size = 0x80000; // 512 KiB.
    const stack = elf.allocateStack(&allocator, init_directory, base - platform.PAGE_SIZE, default_stack_size) catch |err| {
        debug.print("Error while creating stack for init: {}\n", .{err});
        while (true) {}
    };
    thread.arch.setStack(&init.regs, stack);

    platform.platformEndInit();

    thread.enterTask(init);
}

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    debug.print("--- KERNEL PANIC! ---\n", .{});
    debug.print("{s}\n", .{message});
    debug.print("return address: {x}\n", .{@returnAddress()});
    while (true) {}
}
