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
}

inline fn main(base: u64, address: u64) !void {
    setTokens();

    const mapper = vm.MemoryMapper.create(.{ .address = address }, base);
    var sys_alloc = heap.SystemAllocator.init(mapper, 0x200000, base - 0x200000); // FIXME: Let's not hardcode these.
    const allocator = sys_alloc.allocator();

    var thread_list = std.AutoHashMap(u64, thread.Thread).init(allocator);
    errdefer thread_list.deinit();

    try boot.setupInitialThreads(&thread_list, base);
    try boot.setupKernelRingBuffer(base);

    const kernel_queue = system.ipc.getKernelBuffer().?;

    try runLoop(kernel_queue, &thread_list);
}

fn runLoop(kernel_queue: buffer.RingBuffer, thread_list: *std.AutoHashMap(u64, thread.Thread)) !void {
    outer: while (true) {
        var msg_type: u64 = undefined;
        while (kernel_queue.readType(u64, &msg_type)) {
            switch (msg_type) {
                @intFromEnum(system.kernel.KernelMessage.MessageReceived) => {
                    var id: u64 = undefined;
                    if (!kernel_queue.readType(u64, &id)) continue :outer;

                    const sender = thread_list.getPtr(id).?;

                    try ipc.handleMessageFromThread(sender);
                },
                else => {},
            }
        }

        syscalls.wait();
    }
}
