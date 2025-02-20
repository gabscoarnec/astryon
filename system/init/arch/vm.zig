const std = @import("std");
const target = @import("builtin").target;

pub const arch = switch (target.cpu.arch) {
    .x86_64 => @import("x86_64/vm.zig"),
    else => {
        @compileError("unsupported architecture");
    },
};
