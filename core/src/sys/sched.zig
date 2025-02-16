const interrupts = @import("../arch/interrupts.zig").arch;
const sys = @import("syscall.zig");
const thread = @import("../thread.zig");

pub fn yield(regs: *interrupts.InterruptStackFrame, _: *sys.Arguments, _: *isize) anyerror!void {
    thread.scheduleNewTask(regs);
}
