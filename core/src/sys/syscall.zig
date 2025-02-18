const std = @import("std");
const interrupts = @import("../arch/interrupts.zig").arch;
const print = @import("print.zig").print;
const mem = @import("mem.zig");
const sched = @import("sched.zig");

pub const Arguments = struct {
    arg0: usize,
    arg1: usize,
    arg2: usize,
    arg3: usize,
    arg4: usize,
    arg5: usize,
};

const SystemCall = *const fn (frame: *interrupts.InterruptStackFrame, args: *Arguments, retval: *isize) anyerror!void;

const syscalls = [_]SystemCall{ print, mem.allocFrame, mem.lockFrame, mem.freeFrame, sched.yield, sched.setPriority, sched.getPriority, sched.sleep };

pub fn invokeSyscall(number: usize, frame: *interrupts.InterruptStackFrame, args: *Arguments, retval: *isize) void {
    if (number >= syscalls.len) {
        retval.* = -1;
        return;
    }

    syscalls[number](frame, args, retval) catch {
        retval.* = -1;
        return;
    };
}
