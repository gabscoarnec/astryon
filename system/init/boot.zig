const std = @import("std");
const system = @import("system");
const thread = @import("thread.zig");

const vm = system.vm;
const syscalls = system.syscalls;
const buffer = system.ring_buffer;

pub fn setupKernelRingBuffer(base: u64) !void {
    const phys = vm.PhysFrame{ .address = try syscalls.allocFrame() };

    const data: [*]u8 = @ptrCast(phys.virtualPointer(u8, base));

    try syscalls.setEventQueue(syscalls.getThreadId(), phys.address);

    const event_queue = buffer.RingBuffer.init(data, vm.PAGE_SIZE, true);

    system.ipc.setKernelBuffer(event_queue);
}

pub fn discoverThreadLimit() u64 {
    var pid: u64 = 1;
    while (true) {
        _ = syscalls.getPriority(pid) catch return (pid - 1);
        pid += 1;
    }
}

pub fn setupInitialThreads(allocator: std.mem.Allocator, thread_list: *std.AutoHashMap(u64, thread.Thread), base: u64) !void {
    const threads = discoverThreadLimit();

    var pid: u64 = 1;
    while (pid <= threads) : (pid += 1) {
        if (pid == syscalls.getThreadId()) continue;
        const t = try thread.setupThread(allocator, pid, base);
        try thread_list.put(pid, t);
    }
}
