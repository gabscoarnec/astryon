const std = @import("std");

const here = "system/memory";

pub fn buildAsSubmodule(b: *std.Build, build_step: *std.Build.Step, optimize: std.builtin.OptimizeMode, system_module: *std.Build.Module) void {
    var disabled_features = std.Target.Cpu.Feature.Set.empty;
    var enabled_features = std.Target.Cpu.Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.mmx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse2));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx2));
    enabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.soft_float));

    const target_query = std.Target.Query{
        .cpu_arch = std.Target.Cpu.Arch.x86_64,
        .os_tag = std.Target.Os.Tag.freestanding,
        .abi = std.Target.Abi.none,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    };

    const memory = b.addExecutable(.{
        .name = "memory",
        .root_source_file = b.path(here ++ "/main.zig"),
        .target = b.resolveTargetQuery(target_query),
        .optimize = optimize,
        .code_model = .default,
    });

    memory.root_module.addImport("system", system_module);

    const install = b.addInstallArtifact(memory, .{
        .dest_dir = .{
            .override = .{ .custom = "boot/" },
        },
    });

    var memory_step = b.step("memory", "Build the memory manager");
    memory_step.dependOn(&memory.step);
    memory_step.dependOn(&install.step);

    build_step.dependOn(memory_step);
}
