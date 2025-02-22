const std = @import("std");
const core = @import("core/build.zig");
const system = @import("system/build.zig");

pub fn build(b: *std.Build) void {
    const build_step = b.step("all", "Build and install everything");

    const optimize = b.standardOptimizeOption(.{});

    const system_module = b.addModule("system", .{
        .root_source_file = b.path("system/lib/system.zig"),
    });

    core.buildAsSubmodule(b, build_step, optimize, system_module);
    system.buildAsSubmodule(b, build_step, optimize, system_module);

    b.default_step = build_step;
}
