const std = @import("std");
const target = @import("builtin").target;
const thread = @import("../thread.zig");
const pmm = @import("../pmm.zig");
const vmm = @import("vmm.zig").arch;

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
    core.thread_list = .{};

    const idle_thread = &core.idle_thread.data;

    idle_thread.id = 0;
    idle_thread.directory = null;
    idle_thread.regs = std.mem.zeroes(@TypeOf(idle_thread.regs));
    thread.arch.initKernelRegisters(&idle_thread.regs);
    thread.arch.setAddress(&idle_thread.regs, @intFromPtr(&thread.arch.idleLoop));

    core.thread_list.append(&core.idle_thread);

    this_core = core;
}

pub fn thisCore() *arch.Core {
    return this_core;
}
