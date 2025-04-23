const std = @import("std");
const system = @import("system");
const thread = @import("thread.zig");
const boot = @import("boot.zig");
const ipc = @import("ipc.zig");

const vm = system.vm;
const syscalls = system.syscalls;
const buffer = system.ring_buffer;
const heap = system.heap;

const PAGE_SIZE = vm.PAGE_SIZE;

fn setTokens() void {
    var tokens: u64 = 0;
    tokens |= @intFromEnum(system.kernel.Token.Root);
    tokens |= @intFromEnum(system.kernel.Token.PhysicalMemory);
    tokens |= @intFromEnum(system.kernel.Token.CreateProcess);
    syscalls.setTokens(syscalls.getThreadId(), tokens) catch {};
}

export fn _start(base: u64, address: u64) callconv(.C) noreturn {
    main(base, address) catch {
        while (true) {}
    };

    unreachable;
}

inline fn main(base: u64, address: u64) !void {
    setTokens();

    const mapper = vm.MemoryMapper.create(.{ .address = address }, base);
    var sys_alloc = heap.SystemAllocator.init(mapper, 0x200000, base - 0x200000); // FIXME: Let's not hardcode these.
    const allocator = sys_alloc.allocator();

    var thread_list = std.AutoHashMap(u64, thread.Thread).init(allocator);
    errdefer thread_list.deinit();

    var name_map = std.StringHashMap(u64).init(allocator);
    errdefer name_map.deinit();

    var message_table = try ipc.setupMessageTable(allocator);
    errdefer message_table.deinit();

    try boot.setupKernelRingBuffer(base);
    const kernel_queue = system.ipc.getKernelBuffer().?;

    try boot.setupInitialThreads(allocator, &thread_list, base);

    try runLoop(kernel_queue, &message_table, allocator, &thread_list, &name_map);
}

fn runLoop(
    kernel_queue: buffer.RingBuffer,
    message_table: *system.ipc.MessageHandlerTable,
    allocator: std.mem.Allocator,
    thread_list: *std.AutoHashMap(u64, thread.Thread),
    name_map: *std.StringHashMap(u64),
) !void {
    while (true) {
        try emptyKernelQueue(kernel_queue, message_table, allocator, thread_list, name_map);
        syscalls.wait();
    }
}

fn emptyKernelQueue(
    kernel_queue: buffer.RingBuffer,
    message_table: *system.ipc.MessageHandlerTable,
    allocator: std.mem.Allocator,
    thread_list: *std.AutoHashMap(u64, thread.Thread),
    name_map: *std.StringHashMap(u64),
) !void {
    var msg_type: u64 = undefined;
    var queue = kernel_queue;

    while (queue.readType(u64, &msg_type)) {
        switch (msg_type) {
            @intFromEnum(system.kernel.KernelMessage.MessageReceived) => {
                var id: u64 = undefined;
                if (!queue.readType(u64, &id)) return;

                const sender = thread_list.getPtr(id).?;

                var context = ipc.Context{
                    .sender = sender,
                    .allocator = allocator,
                    .thread_list = thread_list,
                    .name_map = name_map,
                };

                while (system.ipc.handleMessage(&sender.connection, message_table, &context)) {}
            },
            else => {},
        }
    }
}
