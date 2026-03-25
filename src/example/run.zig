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
            .material_chunk_size = 8 * 1024,
            .logger = logger,
            .allocator = allocator,
            .max_iterations = 5,
        };

    try rlm.init();
    defer rlm.deinit();
    const root =
        "Based on this API reference, return a minimal directly executable Zig example showing how to call " ++
        "completion.";
    const material_path = "API_reference.md";

    std.debug.print("INPUT:{s}\n", .{root});
    const result = try rlm.completion(root, material_path);
    defer allocator.free(result.response);
    std.debug.print("total time: {d}ms\n", .{result.execution_time});
    std.debug.print("Answer:\n{s}\n", .{result.response});

    std.debug.print("\n*******RLM finished*******\n", .{});
}
