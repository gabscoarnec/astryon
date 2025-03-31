const std = @import("std");
const platform = @import("../arch/platform.zig");
const sys = @import("syscall.zig");
const debug = @import("../arch/debug.zig");
const vmm = @import("../arch/vmm.zig");
const cpu = @import("../arch/cpu.zig");

pub fn print(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();

    const ptr = args.arg0;
    const len = @min(@as(usize, 511), args.arg1);

    var buffer: [512]u8 = std.mem.zeroes([512]u8);

    try vmm.copyFromUser(core.current_thread.address_space.?, vmm.PHYSICAL_MAPPING_BASE, ptr, &buffer, len);

    debug.print("{s}", .{std.mem.sliceTo(&buffer, 0)});
}
