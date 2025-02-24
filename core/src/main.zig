const std = @import("std");
const system = @import("system");
const easyboot = @cImport(@cInclude("easyboot.h"));
const debug = @import("arch/debug.zig");
const cpu = @import("arch/cpu.zig");
const platform = @import("arch/platform.zig");
const interrupts = @import("arch/interrupts.zig");
const vmm = @import("arch/vmm.zig");
const multiboot = @import("multiboot.zig");
const pmm = @import("pmm.zig");
const thread = @import("thread.zig");
const elf = @import("elf.zig");

const MultibootInfo = [*c]u8;

export fn _start(_: u32, _: MultibootInfo) callconv(.C) noreturn {
    platform._start();
}

export fn main(magic: u32, info: MultibootInfo) callconv(.C) noreturn {
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

    pmm.reserveMultibootMemory(&allocator, info) catch |err| {
        debug.print("Error while reserving multiboot memory: {}\n", .{err});
        while (true) {}
    };

    vmm.createInitialMapping(&allocator, tag) catch |err| {
        debug.print("Error while creating initial mappings: {}\n", .{err});
        while (true) {}
    };

    cpu.setupCore(&allocator) catch |err| {
        debug.print("Error while setting up core-specific scheduler structures: {}\n", .{err});
        while (true) {}
    };

    const Context = struct {
        allocator: *pmm.FrameAllocator,
        mmap: *easyboot.multiboot_tag_mmap_t,
        init: ?*thread.ThreadControlBlock,
    };

    var ctx = Context{ .allocator = &allocator, .mmap = tag, .init = null };

    multiboot.findMultibootTags(easyboot.multiboot_tag_module_t, @ptrCast(info), struct {
        fn loadModule(mod: *easyboot.multiboot_tag_module_t, context: *Context) !void {
            const frame = try pmm.allocFrame(context.allocator);
            const space = vmm.AddressSpace.create(frame, vmm.PHYSICAL_MAPPING_BASE);

            const base = try vmm.setUpInitialUserPageDirectory(context.allocator, context.mmap, space);

            const module = try thread.createThreadControlBlock(context.allocator);

            module.address_space = space;
            module.user_priority = 255;
            module.tokens = @intFromEnum(system.kernel.Token.Root);
            thread.arch.initUserRegisters(&module.regs);
            thread.arch.setArguments(&module.regs, base, space.phys.address);

            const mod_start = pmm.PhysFrame{ .address = mod.mod_start };

            debug.print("Loading module {s} at address {x}, virtual {x}\n", .{ mod.string(), mod.mod_start, mod_start.virtualAddress(vmm.PHYSICAL_MAPPING_BASE) });
            const entry = try elf.loadElf(context.allocator, space, mod_start);
            thread.arch.setAddress(&module.regs, entry);

            const default_stack_size = 0x40000; // 256 KiB.
            const stack = try elf.allocateStack(context.allocator, space, base - platform.PAGE_SIZE, default_stack_size);
            thread.arch.setStack(&module.regs, stack);

            const init_name = "init";
            if (std.mem.eql(u8, init_name[0..init_name.len], mod.string()[0..init_name.len])) context.init = module;
        }

        fn handler(mod: *easyboot.multiboot_tag_module_t, context: *anyopaque) void {
            loadModule(mod, @alignCast(@ptrCast(context))) catch |err| {
                debug.print("Error while loading module file {s}: {}\n", .{ mod.string(), err });
                while (true) {}
            };
        }
    }.handler, &ctx);

    pmm.setGlobalAllocator(&allocator) catch |err| {
        debug.print("Error while setting up global frame allocator: {}\n", .{err});
        while (true) {}
    };

    platform.platformEndInit();

    if (ctx.init) |init| {
        thread.enterThread(init);
    } else {
        debug.print("Error: no init module loaded!\n", .{});
        while (true) {}
    }
}

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    debug.print("--- KERNEL PANIC! ---\n", .{});
    debug.print("{s}\n", .{message});
    debug.print("return address: {x}\n", .{@returnAddress()});
    while (true) {}
}
