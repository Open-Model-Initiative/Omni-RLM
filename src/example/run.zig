const RLMLogger = @import("omni-rlm").RLMLogger;
const std = @import("std");
const RLM = @import("omni-rlm").RLM;
const config_env = @import("omni-rlm").config_env;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var backend_cfg = config_env.load_backend_env_config(allocator, ".env") catch {
        std.debug.print("Failed to load backend config from .env. Required keys: OMNIRLM_API_KEY (or DASHSCOPE_API_KEY/OPENAI_API_KEY), OMNIRLM_BASE_URL, OMNIRLM_MODEL_NAME.\n", .{});
        return error.MissingBackendConfig;
    };
    defer backend_cfg.deinit(allocator);

    std.debug.print("\n*******RLM started*******\n", .{});

    const logger = try RLMLogger.init("./logs", "run", allocator);

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
