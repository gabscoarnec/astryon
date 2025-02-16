const interrupts = @import("../arch/interrupts.zig").arch;
const sys = @import("syscall.zig");
const pmm = @import("../pmm.zig");

pub fn allocFrame(_: *interrupts.InterruptStackFrame, _: *sys.Arguments, retval: *isize) anyerror!void {
    const allocator = pmm.lockGlobalAllocator();
    defer pmm.unlockGlobalAllocator();

    const frame = try pmm.allocFrame(allocator);

    retval.* = @bitCast(frame.address);
}

pub fn freeFrame(_: *interrupts.InterruptStackFrame, args: *sys.Arguments, _: *isize) anyerror!void {
    const allocator = pmm.lockGlobalAllocator();
    defer pmm.unlockGlobalAllocator();

    try pmm.freeFrame(allocator, args.arg0);
}

pub fn lockFrame(_: *interrupts.InterruptStackFrame, args: *sys.Arguments, _: *isize) anyerror!void {
    const allocator = pmm.lockGlobalAllocator();
    defer pmm.unlockGlobalAllocator();

    try pmm.lockFrame(allocator, args.arg0);
}
