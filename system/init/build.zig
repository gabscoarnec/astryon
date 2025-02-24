const std = @import("std");

const here = "system/init";

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

    const init = b.addExecutable(.{
        .name = "init",
        .root_source_file = b.path(here ++ "/main.zig"),
        .target = b.resolveTargetQuery(target_query),
        .optimize = optimize,
        .code_model = .default,
    });

    init.root_module.addImport("system", system_module);

    const install = b.addInstallArtifact(init, .{
        .dest_dir = .{
            .override = .{ .custom = "boot/astryon/" },
        },
    });

    var init_step = b.step("init", "Build the init service");
    init_step.dependOn(&init.step);
    init_step.dependOn(&install.step);

    build_step.dependOn(init_step);
}
