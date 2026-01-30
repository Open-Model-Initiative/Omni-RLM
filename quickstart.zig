// Please provide valid api_key in the RLM initialization to run this quickstart example or it will return an attempt to use null value error.
const RLMLogger = @import("rlm_logger.zig").RLMLogger;
const std = @import("std");
const RLM = @import("rlm.zig").RLM;

test "quickstart runs without error" {
    std.debug.print("\n*******RLM started*******\n", .{});

    const allocator = std.testing.allocator;

    const logger = try RLMLogger.init("./logs", "quickstart", allocator);

    var rlm: RLM =
        .{
            .backend = "openai",
            // must provide full information of api_key, base_url, model_name in json format
            .backend_kwargs =
            \\{
            \\"base_url":"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            \\"api_key":"",
            \\"model_name":"qwen-plus"
            \\}
            ,
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
