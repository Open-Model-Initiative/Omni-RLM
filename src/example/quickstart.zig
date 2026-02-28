// Please provide valid api_key in the RLM initialization to run this quickstart example or it will return an attempt to use null value error.
const RLMLogger = @import("omni-rlm").RLMLogger;
const std = @import("std");
const RLM = @import("omni-rlm").RLM;

test "quickstart run" {
    std.debug.print("\n*******RLM started*******\n", .{});

    const allocator = std.testing.allocator;
    const api_key = try std.process.getEnvVarOwned(allocator, "DASHSCOPE_API_KEY");
    defer allocator.free(api_key);

    const logger = try RLMLogger.init("./logs", "quickstart", allocator);

    var rlm: RLM =
        .{
            .backend = "openai",
            // must provide full information of api_key, base_url, model_name in json format
            .backend_kwargs = .{
                .base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                .api_key = api_key,
                .model_name = "qwen-plus",
            },
            .environment = "local",
            .environment_kwargs = "{\"mainfunc\": \"src/core/environment/local/env_init.py\"}",
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
