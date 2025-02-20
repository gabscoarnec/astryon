const kernel = @import("kernel.zig");
const vm = @import("arch/vm.zig").arch;

export fn _start(base: u64, address: u64) callconv(.C) noreturn {
    const mapper = vm.MemoryMapper.create(.{ .address = address }, base);

    kernel.print(base);
    kernel.print(address);
    kernel.print(@intFromPtr(mapper.directory));

    const phys = kernel.allocFrame() catch {
        while (true) {}
    };

    vm.map(&mapper, 0x6000000, .{ .address = phys }, @intFromEnum(vm.Flags.ReadWrite) | @intFromEnum(vm.Flags.User)) catch {
        while (true) {}
    };

    var counter: u64 = 0;

    while (true) : (counter += 4) {
        kernel.sleep(1000);
        kernel.print(counter);
    }
}
