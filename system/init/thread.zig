const std = @import("std");
const system = @import("system");

const vm = system.vm;
const syscalls = system.syscalls;
const buffer = system.ring_buffer;

pub const Thread = struct {
    address: ?[]u8,
    connection: system.ipc.Connection,
};

pub fn setupKernelRingBufferForThread(mapper: *const vm.MemoryMapper, pid: u64, virt: u64) !void {
    const phys = vm.PhysFrame{ .address = try syscalls.allocFrame() };

    try vm.map(mapper, virt, phys, @intFromEnum(vm.Flags.User) | @intFromEnum(vm.Flags.ReadWrite) | @intFromEnum(vm.Flags.NoExecute));

    try syscalls.setEventQueue(pid, phys.address);
}

pub fn setupRingBufferForThread(mapper: *const vm.MemoryMapper, base: u64, virt: u64) !buffer.RingBuffer {
    const phys = vm.PhysFrame{ .address = try syscalls.allocFrame() };

    try vm.map(mapper, virt, phys, @intFromEnum(vm.Flags.User) | @intFromEnum(vm.Flags.ReadWrite) | @intFromEnum(vm.Flags.NoExecute));

    const data: [*]u8 = @ptrCast(phys.virtualPointer(u8, base));

    return buffer.RingBuffer.init(data, vm.PAGE_SIZE, true);
}

pub fn setupThread(pid: u64, base: u64) !Thread {
    const space = try syscalls.getAddressSpace(pid);
    const mapper = vm.MemoryMapper.create(.{ .address = space }, base);

    const ipc_base = 0x1000; // FIXME: Find a good place in the address space and guarantee this is free.

    try setupKernelRingBufferForThread(&mapper, pid, ipc_base + system.ipc.KERNEL_BUFFER_ADDRESS_OFFSET);
    // INIT_WRITE and INIT_READ are inverted here because when the process writes, init reads.
    const read_buffer = try setupRingBufferForThread(&mapper, base, ipc_base + system.ipc.INIT_WRITE_BUFFER_ADDRESS_OFFSET);
    var write_buffer = try setupRingBufferForThread(&mapper, base, ipc_base + system.ipc.INIT_READ_BUFFER_ADDRESS_OFFSET);

    const connection: system.ipc.Connection = .{ .pid = pid, .read_buffer = read_buffer, .write_buffer = write_buffer };

    const init_pid = syscalls.getThreadId();
    _ = write_buffer.writeType(u64, &init_pid);

    try syscalls.setThreadArguments(pid, base, ipc_base);

    try syscalls.startThread(pid);

    return .{ .address = null, .connection = connection };
}
