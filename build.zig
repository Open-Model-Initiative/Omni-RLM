const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_filters = b.option([]const u8, "test-filter", "Comma-separated list of test filters to run");

    const omni_rlm = b.addModule("omni-rlm", .{
        .root_source_file = b.path("src/omni-rlm.zig"),
        .target = target,
        .optimize = optimize,
    });

    const debug = b.addExecutable(.{
        .name = "run_debug",
        .root_module = b.addModule("slow", .{
            .root_source_file = b.path("src/example/run.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "omni-rlm", .module = omni_rlm },
            },
        }),
    });

    const run_artifact = b.addRunArtifact(debug);
    const run_step = b.step("run", "Run the RLM example");
    run_step.dependOn(&run_artifact.step);

    b.installArtifact(debug);

    const test_comp = b.addTest(.{
        .root_module = b.addModule("test", .{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "omni-rlm", .module = omni_rlm },
            },
        }),
        .filters = &.{test_filters orelse ""},
    });

    const test_artifact = b.addRunArtifact(test_comp);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&test_artifact.step);

    const test_run = b.addTest(.{
        .root_module = b.addModule("test run", .{
            .root_source_file = b.path("src/example/quickstart.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "omni-rlm", .module = omni_rlm },
            },
        }),
        .filters = &.{"quickstart run"},
    });

    const test_run_artifact = b.addRunArtifact(test_run);
    const test_run_step = b.step("quickstart", "Run quickstart test");
    test_run_step.dependOn(&test_run_artifact.step);
}
