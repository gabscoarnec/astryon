const interrupts = @import("../arch/interrupts.zig").arch;
const sys = @import("syscall.zig");
const thread = @import("../thread.zig");
const cpu = @import("../arch/cpu.zig");

pub fn yield(regs: *interrupts.InterruptStackFrame, _: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    const new_thread = thread.fetchNewTask(core, false) orelse return;
    const current_thread = thread.scheduleNewTask(core, regs, new_thread);
    thread.addThreadToPriorityQueue(core, current_thread);
}

pub fn setPriority(_: *interrupts.InterruptStackFrame, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    core.current_thread.user_priority = @truncate(args.arg0);
}

pub fn getPriority(_: *interrupts.InterruptStackFrame, _: *sys.Arguments, retval: *isize) anyerror!void {
    const core = cpu.thisCore();
    retval.* = core.current_thread.user_priority;
}

pub fn sleep(regs: *interrupts.InterruptStackFrame, args: *sys.Arguments, _: *isize) anyerror!void {
    _ = thread.startSleep(regs, args.arg0);
}
