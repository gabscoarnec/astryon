const std = @import("std");
const system = @import("system");
const thread = @import("thread.zig");
const boot = @import("boot.zig");

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

    const threads = boot.discoverThreadLimit();

    var thread_list = std.AutoHashMap(u64, thread.Thread).init(allocator);
    try thread_list.ensureTotalCapacity(@intCast(threads));
    errdefer thread_list.deinit();

    var pid: u64 = 1;
    while (pid <= threads) : (pid += 1) {
        if (pid == syscalls.getThreadId()) continue;
        const t = try thread.setupThread(pid, base);
        try thread_list.put(pid, t);
    }

    try boot.setupKernelRingBuffer(base);

    var kernel_queue = system.ipc.getKernelBuffer().?;

    outer: while (true) {
        var msg_type: u64 = undefined;
        while (kernel_queue.readType(u64, &msg_type)) {
            switch (msg_type) {
                @intFromEnum(system.kernel.KernelMessage.MessageReceived) => {
                    var id: u64 = undefined;
                    if (!kernel_queue.readType(u64, &id)) continue :outer;

                    var sender = thread_list.getPtr(id).?;

                    var data: u8 = undefined;
                    if (sender.connection.read(u8, &data)) {
                        syscalls.print(id);
                        syscalls.print(data);
                    }
                },
                else => {},
            }
        }

        syscalls.wait();
    }
}
