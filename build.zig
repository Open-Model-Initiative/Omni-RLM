const std = @import("std");

pub fn build(b: *std.Build) void {
    const mvzr = b.dependency("mvzr", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const run_slow = b.addExecutable(.{
        .name = "run_debug",
        .root_module = b.addModule("slow", .{
            .root_source_file = b.path("run.zig"),
            .target = target,
            .optimize = .Debug,
            .imports = &.{
                .{ .name = "mvzr", .module = mvzr.module("mvzr") },
            },
        }),
    });

    // const run_fast = b.addExecutable(.{
    //     .name = "run_ReleaseFast",
    //     .root_module = b.addModule("fast", .{
    //         .root_source_file = b.path("run.zig"),
    //         .target = target,
    //         .optimize = .ReleaseFast,
    //     }),
    // });

    // b.installArtifact(run_fast);
    b.installArtifact(run_slow);

    const test_comp = b.addTest(.{
        .root_module = b.addModule("test", .{
            .root_source_file = b.path("test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mvzr", .module = mvzr.module("mvzr") },
            },
        }),
    });

    const test_run = b.addTest(.{
        .root_module = b.addModule("test run", .{
            .root_source_file = b.path("quickstart.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mvzr", .module = mvzr.module("mvzr") },
            },
        }),
        .filters = &.{"quickstart run"},
    });

    const test_artifact = b.addRunArtifact(test_comp);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&test_artifact.step);

    const test_run_artifact = b.addRunArtifact(test_run);
    const test_run_step = b.step("quickstart", "Run quickstart test");
    test_run_step.dependOn(&test_run_artifact.step);

    const run_artifact = b.addRunArtifact(run_slow);
    const run_step = b.step("run", "Run the RLM example");
    run_step.dependOn(&run_artifact.step);
}
