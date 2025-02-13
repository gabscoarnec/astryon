const std = @import("std");
const core = @import("core/build.zig");
const system = @import("system/build.zig");

pub fn build(b: *std.Build) void {
    const build_step = b.step("all", "Build and install everything");

    const optimize = b.standardOptimizeOption(.{});

    core.build(b, build_step, optimize);
    system.build(b, build_step, optimize);

    b.default_step = build_step;
}
