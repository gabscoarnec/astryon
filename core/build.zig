const std = @import("std");

const here = "core";

pub fn build(b: *std.Build, build_step: *std.Build.Step, optimize: std.builtin.OptimizeMode) void {
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

    const core = b.addExecutable(.{
        .name = "core",
        .root_source_file = b.path(here ++ "/src/main.zig"),
        .target = b.resolveTargetQuery(target_query),
        .optimize = optimize,
        .code_model = .kernel,
    });

    core.addIncludePath(b.path(here ++ "/../easyboot/"));

    core.setLinkerScript(b.path(here ++ "/src/link.ld"));
    const install = b.addInstallArtifact(core, .{
        .dest_dir = .{
            .override = .{ .custom = "boot/" },
        },
    });

    var kernel_step = b.step("core", "Build the core microkernel");
    kernel_step.dependOn(&core.step);
    kernel_step.dependOn(&install.step);

    build_step.dependOn(kernel_step);
}
