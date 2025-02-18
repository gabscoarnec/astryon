const kernel = @import("kernel.zig");

export fn _start(base: u64) callconv(.C) noreturn {
    kernel.print(base);
    kernel.print(kernel.getPriority());

    var counter: u64 = 0;

    while (true) : (counter += 4) {
        kernel.sleep(1000);
        kernel.print(counter);
    }
}
