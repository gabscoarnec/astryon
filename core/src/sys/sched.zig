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
    NotAuthorized,
};

pub fn yield(regs: *platform.Registers, _: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    const new_thread = thread.fetchNewThread(core, false) orelse return;
    const current_thread = thread.scheduleNewThread(core, regs, new_thread);
    thread.addThreadToPriorityQueue(core, current_thread);
}

pub fn setPriority(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();

    if (!sys.checkToken(core, system.kernel.Token.ThreadPriority)) return error.NotAuthorized;

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
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.CreateProcess)) return error.NotAuthorized;
    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    if (target.event_queue) |_| return error.ThreadQueueAlreadySet;

    const phys = pmm.PhysFrame{ .address = args.arg1 };

    const virt = phys.virtualAddress(vmm.PHYSICAL_MAPPING_BASE);

    const data: [*]u8 = @ptrFromInt(virt);

    target.event_queue = RingBuffer.init(data, platform.PAGE_SIZE, true);
}

pub fn createThread(_: *platform.Registers, _: *sys.Arguments, result: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.CreateProcess)) return error.NotAuthorized;

    const allocator = pmm.lockGlobalAllocator();
    defer pmm.unlockGlobalAllocator();

    const child = try thread.createThreadControlBlock(allocator);
    thread.arch.initUserRegisters(&child.regs);

    result.* = @bitCast(child.id);
}

pub fn setThreadEntry(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.CreateProcess)) return error.NotAuthorized;
    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    thread.arch.setAddress(&target.regs, args.arg1);
}

pub fn setThreadArguments(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.CreateProcess)) return error.NotAuthorized;
    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    thread.arch.setArguments(&target.regs, args.arg1, args.arg2);
}

pub fn setThreadStack(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.CreateProcess)) return error.NotAuthorized;
    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    thread.arch.setStack(&target.regs, args.arg1);
}

pub fn startThread(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.CreateProcess)) return error.NotAuthorized;
    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    if (target.state != .Inactive) return;

    thread.reviveThread(core, target);
}

pub fn getThreadId(_: *platform.Registers, _: *sys.Arguments, result: *isize) anyerror!void {
    const core = cpu.thisCore();
    result.* = @bitCast(core.current_thread.id);
}
