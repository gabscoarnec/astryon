const platform = @import("../arch/platform.zig").arch;
const sys = @import("syscall.zig");
const debug = @import("../arch/debug.zig");

pub fn print(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    debug.print("The userspace program gave us the number {x}\n", .{args.arg0});
}
