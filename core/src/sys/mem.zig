const system = @import("system");
const platform = @import("../arch/platform.zig");
const sys = @import("syscall.zig");
const pmm = @import("../pmm.zig");
const cpu = @import("../arch/cpu.zig");
const thread = @import("../thread.zig");
const vmm = @import("../arch/vmm.zig");

pub fn allocFrame(_: *platform.Registers, _: *sys.Arguments, retval: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.PhysicalMemory)) return error.NotAuthorized;

    const allocator = pmm.lockGlobalAllocator();
    defer pmm.unlockGlobalAllocator();

    const frame = try pmm.allocFrame(allocator);

    retval.* = @bitCast(frame.address);
}

pub fn freeFrame(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.PhysicalMemory)) return error.NotAuthorized;

    const allocator = pmm.lockGlobalAllocator();
    defer pmm.unlockGlobalAllocator();

    try pmm.freeFrame(allocator, args.arg0);
}

pub fn lockFrame(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.PhysicalMemory)) return error.NotAuthorized;

    const allocator = pmm.lockGlobalAllocator();
    defer pmm.unlockGlobalAllocator();

    try pmm.lockFrame(allocator, args.arg0);
}

pub fn setAddressSpace(_: *platform.Registers, args: *sys.Arguments, _: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.CreateProcess)) return error.NotAuthorized;

    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    target.address_space = vmm.AddressSpace.create(.{ .address = args.arg1 }, vmm.PHYSICAL_MAPPING_BASE);
}

pub fn getAddressSpace(_: *platform.Registers, args: *sys.Arguments, result: *isize) anyerror!void {
    const core = cpu.thisCore();
    if (!sys.checkToken(core, system.kernel.Token.CreateProcess)) return error.NotAuthorized;

    const target = thread.lookupThreadById(args.arg0) orelse return error.NoSuchThread;

    const space = target.address_space orelse return error.NoAddressSpace;

    result.* = @bitCast(space.phys.address);
}
