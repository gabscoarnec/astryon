const kernel = @import("kernel.zig");

export fn _start(base: u64) callconv(.C) noreturn {
    kernel.print(base);
    kernel.print(kernel.getPriority());

    kernel.setPriority(128);
    kernel.print(kernel.getPriority());

    while (true) {
        kernel.yield();
    }
}
