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
            .backend_kwargs = .{
                .base_url = backend_cfg.base_url,
                .api_key = backend_cfg.api_key,
                .model_name = backend_cfg.model_name,
            },
            .environment = "local",
            .environment_kwargs = "{}",
            .max_depth = 1,
            .logger = logger,
            .allocator = allocator,
            .max_iterations = 5,
        };

    try rlm.init();
    defer rlm.deinit();
    const prompt = "Print me the first 100 powers of two, each on a newline.";
    const p = try allocator.dupe(u8, prompt);
    defer allocator.free(p);
    std.debug.print("INPUT:{s}", .{prompt});
    const result = try rlm.completion(p, null);
    defer allocator.free(result.response);
    std.debug.print("total time: {d}ms\n", .{result.execution_time});

    std.debug.print("\n*******RLM finished*******\n", .{});
}
