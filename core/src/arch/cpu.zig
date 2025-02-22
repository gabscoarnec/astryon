const std = @import("std");
const target = @import("builtin").target;
const thread = @import("../thread.zig");
const pmm = @import("../pmm.zig");
const vmm = @import("vmm.zig");
const platform = @import("platform.zig");

pub const arch = switch (target.cpu.arch) {
    .x86_64 => @import("x86_64/cpu.zig"),
    else => {
        @compileError("unsupported architecture");
    },
};

// FIXME: single-core hack, we need a proper way to figure which core this is when SMP support is added.
var this_core: *arch.Core = undefined;

pub fn setupCore(allocator: *pmm.FrameAllocator) !void {
    const frame = try pmm.allocFrame(allocator);

    const core: *arch.Core = @ptrFromInt(frame.virtualAddress(vmm.PHYSICAL_MAPPING_BASE));
    core.id = 0; // FIXME: Actually check core id
    core.active_thread_list = .{};
    core.sleeping_thread_list = .{};

    const idle_thread = &core.idle_thread.data;

    idle_thread.id = 0;
    idle_thread.address_space = null;
    idle_thread.regs = std.mem.zeroes(@TypeOf(idle_thread.regs));
    idle_thread.state = .Running;
    idle_thread.user_priority = 0;
    idle_thread.event_queue = null;
    thread.arch.initKernelRegisters(&idle_thread.regs);
    thread.arch.setAddress(&idle_thread.regs, @intFromPtr(&thread.arch.idleLoop));

    const stack = try pmm.allocFrame(allocator);
    thread.arch.setStack(&idle_thread.regs, stack.virtualAddress(vmm.PHYSICAL_MAPPING_BASE) + (platform.PAGE_SIZE - 16));

    this_core = core;
}

pub fn thisCore() *arch.Core {
    return this_core;
}
