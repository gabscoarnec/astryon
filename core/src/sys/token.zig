const system = @import("system");
const platform = @import("../arch/platform.zig");
const sys = @import("syscall.zig");
const cpu = @import("../arch/cpu.zig");
const thread = @import("../thread.zig");

pub fn setTokens(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.Root)) return error.NotAuthorized;

    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    target.tokens = args.arg1;
}
