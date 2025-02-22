const system = @import("system");
const vm = @import("arch/vm.zig");

const syscalls = system.syscalls;
const buffer = system.ring_buffer;

// FIXME: Make arch-specific.
const PAGE_SIZE = 4096;

fn setupKernelRingBuffer(base: u64) !buffer.RingBuffer {
    const phys = vm.PhysFrame{ .address = try syscalls.allocFrame() };

    const data: [*]u8 = @ptrCast(phys.virtualPointer(u8, base));

    try syscalls.setEventQueue(1, phys.address);

    return buffer.RingBuffer.init(data, PAGE_SIZE, true);
}

export fn _start(base: u64, address: u64) callconv(.C) noreturn {
    const mapper = vm.MemoryMapper.create(.{ .address = address }, base);

    syscalls.print(base);
    syscalls.print(address);
    syscalls.print(@intFromPtr(mapper.directory));

    const phys = syscalls.allocFrame() catch {
        while (true) {}
    };

    vm.map(&mapper, 0x6000000, .{ .address = phys }, @intFromEnum(vm.Flags.ReadWrite) | @intFromEnum(vm.Flags.User)) catch {
        while (true) {}
    };

    const event_queue = setupKernelRingBuffer(base) catch {
        while (true) {}
    };

    _ = event_queue;

    var counter: u64 = 0;

    while (true) : (counter += 4) {
        syscalls.sleep(1000);
        syscalls.print(counter);
    }
}
