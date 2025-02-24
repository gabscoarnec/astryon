const std = @import("std");
const init = @import("init/build.zig");
const memory = @import("memory/build.zig");

pub fn buildAsSubmodule(b: *std.Build, build_step: *std.Build.Step, optimize: std.builtin.OptimizeMode, system_module: *std.Build.Module) void {
    const system_step = b.step("system", "Build core system services");
    init.buildAsSubmodule(b, system_step, optimize, system_module);
    memory.buildAsSubmodule(b, system_step, optimize, system_module);

    build_step.dependOn(system_step);
}
