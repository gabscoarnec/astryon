const std = @import("std");
const system = @import("system");
const platform = @import("../arch/platform.zig");
const sys = @import("syscall.zig");
const thread = @import("../thread.zig");
const cpu = @import("../arch/cpu.zig");
const pmm = @import("../pmm.zig");
const vmm = @import("../arch/vmm.zig");

const RingBuffer = system.ring_buffer.RingBuffer;

const SyscallError = error{
    NoSuchThread,
    ThreadQueueAlreadySet,
};

pub fn yield(regs: *platform.Registers, _: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    const new_thread = thread.fetchNewThread(core, false) orelse return;
    const current_thread = thread.scheduleNewThread(core, regs, new_thread);
    thread.addThreadToPriorityQueue(core, current_thread);
}

pub fn setPriority(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    core.current_thread.user_priority = @truncate(args.arg0);
}

pub fn getPriority(_: *platform.Registers, _: *sys.Arguments, retval: *isize) anyerror!void {
    const core = cpu.thisCore();
    retval.* = core.current_thread.user_priority;
}

pub fn sleep(regs: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    _ = thread.startSleep(regs, args.arg0);
}

pub fn setEventQueue(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    if (target.event_queue) |_| return error.ThreadQueueAlreadySet;

    const phys = pmm.PhysFrame{ .address = args.arg1 };

    const virt = phys.virtualAddress(vmm.PHYSICAL_MAPPING_BASE);

    const data: [*]u8 = @ptrFromInt(virt);

    target.event_queue = RingBuffer.init(data, platform.PAGE_SIZE, true);
}
