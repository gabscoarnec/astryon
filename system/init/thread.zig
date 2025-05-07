const std = @import("std");
const system = @import("system");
const memory = @import("memory.zig");

const vm = system.vm;
const syscalls = system.syscalls;
const buffer = system.ring_buffer;

pub const Thread = struct {
    address: ?[]u8,
    connection: system.ipc.Connection,
    mapper: vm.MemoryMapper,
    memory_map: memory.ThreadMemoryMap,
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

const Context = struct {
    allocator: std.mem.Allocator,
    map: *memory.ThreadMemoryMap,
};

fn registerMemoryCallback(page: u64, size: u64, context: *Context) anyerror!void {
    _ = try memory.tryToAllocRegionAtAddress(context.allocator, context.map, page, @divTrunc(size, vm.PAGE_SIZE), .{
        .used = true,
    });
}

pub fn registerExistingThreadMemoryInMemoryMap(allocator: std.mem.Allocator, mapper: *const vm.MemoryMapper, map: *memory.ThreadMemoryMap) !void {
    var ctx = Context{
        .allocator = allocator,
        .map = map,
    };

    try vm.iterateOverPages(mapper, @ptrCast(&registerMemoryCallback), @ptrCast(&ctx));

    var iter = map.first;
    while (iter) |node| {
        iter = node.next;
    }
}

pub fn setupThread(allocator: std.mem.Allocator, pid: u64, base: u64) !Thread {
    const space = try syscalls.getAddressSpace(pid);
    const mapper = vm.MemoryMapper.create(.{ .address = space }, base);

    var map = try memory.createThreadMemoryMap(allocator);
    try registerExistingThreadMemoryInMemoryMap(allocator, &mapper, &map);

    const IPC_PAGES = 3;

    const ipc_base = memory.allocRegion(allocator, &map, IPC_PAGES, .{
        .used = true,
        .persistent = true,
        .prot = @intFromEnum(system.services.init.MapProt.PROT_READ) | @intFromEnum(system.services.init.MapProt.PROT_WRITE),
        .flags = @intFromEnum(system.services.init.MapFlags.MAP_SHARED) | @intFromEnum(system.services.init.MapFlags.MAP_ANONYMOUS),
    }) orelse {
        system.io.print("No suitable memory range found to place IPC memory!", .{});
        return error.OutOfMemory;
    };

    try setupKernelRingBufferForThread(&mapper, pid, ipc_base + system.ipc.KERNEL_BUFFER_ADDRESS_OFFSET);
    // INIT_WRITE and INIT_READ are inverted here because when the process writes, init reads.
    const read_buffer = try setupRingBufferForThread(&mapper, base, ipc_base + system.ipc.INIT_WRITE_BUFFER_ADDRESS_OFFSET);
    var write_buffer = try setupRingBufferForThread(&mapper, base, ipc_base + system.ipc.INIT_READ_BUFFER_ADDRESS_OFFSET);

    const connection: system.ipc.Connection = .{ .port = .{ .pid = pid, .channel = 0 }, .read_buffer = read_buffer, .write_buffer = write_buffer };

    const init_pid = syscalls.getThreadId();
    _ = write_buffer.writeType(u64, &init_pid);

    try syscalls.setThreadArguments(pid, base, ipc_base);

    try syscalls.startThread(pid);

    return .{ .address = null, .connection = connection, .mapper = mapper, .memory_map = map };
}
