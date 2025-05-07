const std = @import("std");
const system = @import("system");
const platform = @import("../arch/platform.zig");
const sys = @import("syscall.zig");
const thread = @import("../thread.zig");
const cpu = @import("../arch/cpu.zig");
const pmm = @import("../pmm.zig");
const vmm = @import("../arch/vmm.zig");

pub fn send(regs: *platform.Registers, args: *sys.Arguments, retval: *isize) anyerror!void {
    try asyncSend(regs, args, retval);

    _ = thread.block(regs);
}

pub fn asyncSend(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    var queue = target.event_queue orelse return error.ThreadMessagingNotAvailable;

    var data: [3]u64 = std.mem.zeroes([3]u64);
    data[0] = @intFromEnum(system.kernel.KernelMessage.MessageReceived);
    data[1] = core.current_thread.id;
    data[2] = args.arg1; // channel
    _ = queue.writeType([3]u64, &data);

    thread.reviveThread(core, target, .Blocked);
}

pub fn reply(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    thread.reviveThread(core, target, .Blocked);
}

pub fn wait(regs: *platform.Registers, _: *sys.Arguments, _: *isize) anyerror!void {
    _ = thread.block(regs);
}
