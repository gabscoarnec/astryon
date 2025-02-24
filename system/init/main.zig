const system = @import("system");

const vm = system.vm;
const syscalls = system.syscalls;
const buffer = system.ring_buffer;

// FIXME: Make arch-specific.
const PAGE_SIZE = 4096;

fn setupKernelRingBuffer(base: u64) !buffer.RingBuffer {
    const phys = vm.PhysFrame{ .address = try syscalls.allocFrame() };

    const data: [*]u8 = @ptrCast(phys.virtualPointer(u8, base));

    try syscalls.setEventQueue(syscalls.getThreadId(), phys.address);

    return buffer.RingBuffer.init(data, PAGE_SIZE, true);
}

fn setTokens() void {
    var tokens: u64 = 0;
    tokens |= @intFromEnum(system.kernel.Token.Root);
    tokens |= @intFromEnum(system.kernel.Token.PhysicalMemory);
    tokens |= @intFromEnum(system.kernel.Token.CreateProcess);
    syscalls.setTokens(syscalls.getThreadId(), tokens) catch {};
}

fn discoverThreadLimit() u64 {
    var pid: u64 = 1;
    while (true) {
        _ = syscalls.getPriority(pid) catch return (pid - 1);
        pid += 1;
    }
}

export fn _start(base: u64, address: u64) callconv(.C) noreturn {
    setTokens();

    const mapper = vm.MemoryMapper.create(.{ .address = address }, base);
    _ = mapper;

    const threads = discoverThreadLimit();
    syscalls.print(threads);

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
