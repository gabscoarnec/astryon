const kernel = @import("kernel.zig");

export fn _start(base: u64) callconv(.C) noreturn {
    kernel.print(base);

    while (true) {
        kernel.yield();
    }
}
