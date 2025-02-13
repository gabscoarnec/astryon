const std = @import("std");
const init = @import("init/build.zig");

pub fn build(b: *std.Build, build_step: *std.Build.Step, optimize: std.builtin.OptimizeMode) void {
    const system_step = b.step("system", "Build core system services");
    init.build(b, system_step, optimize);

    build_step.dependOn(system_step);
}
