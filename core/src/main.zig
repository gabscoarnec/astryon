const std = @import("std");
const easyboot = @cImport(@cInclude("easyboot.h"));
const debug = @import("arch/debug.zig");
const platform = @import("arch/platform.zig").arch;
const interrupts = @import("arch/interrupts.zig").arch;
const vmm = @import("arch/vmm.zig").arch;
const multiboot = @import("multiboot.zig");
const pmm = @import("pmm.zig");

const MultibootInfo = [*c]u8;

export fn _start(magic: u32, info: MultibootInfo) callconv(.C) noreturn {
    if (magic != easyboot.MULTIBOOT2_BOOTLOADER_MAGIC) {
        debug.print("Invalid magic number: {x}\n", .{magic});
        while (true) {}
    }

    debug.print("Hello world from the kernel!\n", .{});

    multiboot.parseMultibootTags(@ptrCast(info));

    interrupts.disableInterrupts();
    platform.platformInit();

    debug.print("GDT initialized\n", .{});

    platform.platformEndInit();
    interrupts.enableInterrupts();

    if (multiboot.findMultibootTag(easyboot.multiboot_tag_mmap_t, @ptrCast(info))) |tag| {
        var allocator = pmm.initializeFrameAllocator(tag) catch |err| {
            debug.print("Error while initializing frame allocator: {}\n", .{err});
            while (true) {}
        };

        var init_directory = std.mem.zeroes(vmm.PageDirectory);
        const base: usize = vmm.createInitialMappings(&allocator, tag, &init_directory) catch |err| {
            debug.print("Error while creating initial mappings: {}\n", .{err});
            while (true) {}
        };

        debug.print("Physical memory base mapping for init: {x}\n", .{base});
    } else {
        debug.print("No memory map multiboot tag found!\n", .{});
    }

    asm volatile ("int3");

    while (true) {}
}

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    debug.print("--- KERNEL PANIC! ---\n", .{});
    debug.print("{s}\n", .{message});
    while (true) {}
}
