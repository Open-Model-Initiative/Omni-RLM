const RLMLogger = @import("omni-rlm").RLMLogger;
const std = @import("std");
const RLM = @import("omni-rlm").RLM;
const config_env = @import("omni-rlm").config_env;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var backend_cfg = config_env.load_backend_env_config(allocator, ".env") catch |err| {
        return err;
    };
    defer backend_cfg.deinit(allocator);

    std.debug.print("\n*******RLM started*******\n", .{});

    const logger = try RLMLogger.init("./logs", "run", allocator);

    var rlm: RLM =
        .{
            .backend = "openai",
            .backend_kwargs = backend_cfg,
            .environment = "local",
            .environment_kwargs = "{}",
            .max_depth = 1,
            .logger = logger,
            .allocator = allocator,
            .max_iterations = 5,
        };

    try rlm.init();
    defer rlm.deinit();
    const prompt = "read the README.md file at current directory and summarize it in 3 sentences.";
    const p = try allocator.dupe(u8, prompt);
    defer allocator.free(p);
    std.debug.print("INPUT:{s}", .{prompt});
    const result = try rlm.completion(p, null);
    defer allocator.free(result.response);
    std.debug.print("total time: {d}ms\n", .{result.execution_time});

    std.debug.print("\n*******RLM finished*******\n", .{});
}
