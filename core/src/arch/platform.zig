const std = @import("std");
const target = @import("builtin").target;

pub usingnamespace switch (target.cpu.arch) {
    .x86_64 => @import("x86_64/platform.zig"),
    else => {
        @compileError("unsupported architecture");
    },
};
