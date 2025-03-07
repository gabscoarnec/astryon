const system = @import("system");

const vm = system.vm;
const syscalls = system.syscalls;
const buffer = system.ring_buffer;
const heap = system.heap;

const PAGE_SIZE = vm.PAGE_SIZE;

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

fn setupKernelRingBufferForThread(mapper: *const vm.MemoryMapper, pid: u64, virt: u64) !void {
    const phys = vm.PhysFrame{ .address = try syscalls.allocFrame() };

    try vm.map(mapper, virt, phys, @intFromEnum(vm.Flags.User) | @intFromEnum(vm.Flags.ReadWrite) | @intFromEnum(vm.Flags.NoExecute));

    try syscalls.setEventQueue(pid, phys.address);
}

fn setupRingBufferForThread(mapper: *const vm.MemoryMapper, base: u64, virt: u64) !buffer.RingBuffer {
    const phys = vm.PhysFrame{ .address = try syscalls.allocFrame() };

    try vm.map(mapper, virt, phys, @intFromEnum(vm.Flags.User) | @intFromEnum(vm.Flags.ReadWrite) | @intFromEnum(vm.Flags.NoExecute));

    const data: [*]u8 = @ptrCast(phys.virtualPointer(u8, base));

    return buffer.RingBuffer.init(data, PAGE_SIZE, true);
}

fn setupThread(pid: u64, base: u64) !system.ipc.Connection {
    const space = try syscalls.getAddressSpace(pid);
    const mapper = vm.MemoryMapper.create(.{ .address = space }, base);

    const ipc_base = 0x1000; // FIXME: Find a good place in the address space and guarantee this is free.

    try setupKernelRingBufferForThread(&mapper, pid, ipc_base + system.ipc.KERNEL_BUFFER_ADDRESS_OFFSET);
    // INIT_WRITE and INIT_READ are inverted here because when the process writes, init reads.
    const read_buffer = try setupRingBufferForThread(&mapper, base, ipc_base + system.ipc.INIT_WRITE_BUFFER_ADDRESS_OFFSET);
    const write_buffer = try setupRingBufferForThread(&mapper, base, ipc_base + system.ipc.INIT_READ_BUFFER_ADDRESS_OFFSET);

    const connection: system.ipc.Connection = .{ .pid = pid, .read_buffer = read_buffer, .write_buffer = write_buffer };

    try syscalls.setThreadArguments(pid, base, ipc_base);

    try syscalls.startThread(pid);

    return connection;
}

export fn _start(base: u64, address: u64) callconv(.C) noreturn {
    setTokens();

    const mapper = vm.MemoryMapper.create(.{ .address = address }, base);
    _ = mapper;

    const threads = discoverThreadLimit();
    syscalls.print(threads);

    const pid: u64 = 2;
    var connection = setupThread(pid, base) catch {
        while (true) {}
    };

    const event_queue = setupKernelRingBuffer(base) catch {
        while (true) {}
    };

    system.ipc.setKernelBuffer(event_queue);

    var counter: u64 = 0;

    while (true) : (counter += 4) {
        var data: u8 = undefined;
        if (connection.read_buffer.read(@ptrCast(&data), 1)) {
            syscalls.print(data);
        }

        syscalls.sleep(1000);
        syscalls.print(counter);
    }
}
