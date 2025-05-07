pub const kernel = @import("kernel.zig");
pub const ring_buffer = @import("ring_buffer.zig");
pub const syscalls = @import("syscalls.zig");
pub const vm = @import("arch/vm.zig");
pub const ipc = @import("ipc.zig");
pub const heap = @import("heap.zig");
pub const services = @import("services.zig");
pub const io = @import("io.zig");

pub var system_allocator: heap.SystemAllocator = undefined;

pub fn runHosted(ipc_base: u64, inner: *const fn () anyerror!void) noreturn {
    const connection = ipc.readInitBuffers(ipc_base);

    var map_alloc = heap.MapMemoryAllocator.create(connection);
    system_allocator = heap.SystemAllocator.init(map_alloc.page_allocator());

    inner() catch |err| {
        io.print("Program exited with error {any}\n", .{err});
        while (true) {}
    };

    while (true) {}
}
