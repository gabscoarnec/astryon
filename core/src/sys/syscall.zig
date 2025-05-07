const std = @import("std");
const system = @import("system");
const platform = @import("../arch/platform.zig");
const print = @import("print.zig");
const mem = @import("mem.zig");
const sched = @import("sched.zig");
const tokens = @import("token.zig");
const ipc = @import("ipc.zig");
const cpu = @import("../arch/cpu.zig");

pub const Arguments = struct {
    arg0: usize,
    arg1: usize,
    arg2: usize,
    arg3: usize,
    arg4: usize,
    arg5: usize,
};

const SystemCall = *const fn (frame: *platform.Registers, args: *Arguments, retval: *isize) anyerror!void;

const syscalls = [_]SystemCall{
    print.print,
    mem.allocFrame,
    mem.lockFrame,
    mem.freeFrame,
    sched.yield,
    sched.setPriority,
    sched.getPriority,
    sched.sleep,
    sched.setEventQueue,
    tokens.setTokens,
    mem.setAddressSpace,
    sched.createThread,
    sched.setThreadEntry,
    sched.setThreadArguments,
    sched.setThreadStack,
    sched.startThread,
    sched.getThreadId,
    mem.getAddressSpace,
    ipc.send,
    ipc.asyncSend,
    ipc.wait,
    ipc.reply,
};

pub fn invokeSyscall(number: usize, frame: *platform.Registers, args: *Arguments, retval: *isize) void {
    if (number >= syscalls.len) {
        retval.* = -1;
        return;
    }

    syscalls[number](frame, args, retval) catch {
        retval.* = -1;
        return;
    };
}

pub fn checkToken(core: *cpu.arch.Core, token: system.kernel.Token) bool {
    return (core.current_thread.tokens & @intFromEnum(token)) > 0;
}
