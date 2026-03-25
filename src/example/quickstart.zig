const RLMLogger = @import("omni-rlm").RLMLogger;
const std = @import("std");
const RLM = @import("omni-rlm").RLM;
const config_env = @import("omni-rlm").config_env;

test "quickstart run" {
    std.debug.print("\n*******RLM started*******\n", .{});

    const allocator = std.testing.allocator;
    var backend_cfg = config_env.load_backend_env_config(allocator, ".env") catch |err| {
        std.debug.print("Skipping quickstart test: failed to load .env backend config ({any}).\n", .{err});
        return error.SkipZigTest;
    };
    defer backend_cfg.deinit(allocator);

    const logger = try RLMLogger.init("./logs", "quickstart", allocator);

    var rlm: RLM =
        .{
            .backend = "openai",
            .backend_kwargs = backend_cfg,
            .environment = "local",
            .environment_kwargs = "{}",
            .max_depth = 1,
            .material_chunk_size = 128,
            .logger = logger,
            .allocator = allocator,
            .max_iterations = 5,
        };

    try rlm.init();
    defer rlm.deinit();
    const root = "According to README.md, what are the three main characteristics of Omni-RLM?";
    const material_path = "README.md";

    std.debug.print("INPUT:{s}\n", .{root});
    const result = try rlm.completion(root, material_path);
    defer allocator.free(result.response);
    std.debug.print("total time: {d}ms\n", .{result.execution_time});
    std.debug.print("Answer:\n{s}\n", .{result.response});

    std.debug.print("\n*******RLM finished*******\n", .{});
}
