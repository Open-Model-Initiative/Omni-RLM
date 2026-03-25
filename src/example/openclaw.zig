const std = @import("std");
const RLM = @import("omni-rlm").RLM;
const RLMLogger = @import("omni-rlm").RLMLogger;
const config_env = @import("omni-rlm").config_env;

const openclaw_system_prompt =
    \\You are OpenClaw-Zig operating in long-text analysis mode.
    \\
    \\You will receive a user task as the root question and a long material document.
    \\Process the material chunk by chunk and maintain a compact running summary.
    \\
    \\Rules:
    \\- Do not request tools, bash, Python, or file operations.
    \\- Use only the provided material.
    \\- Keep intermediate summaries concise and evidence-based.
    \\- Provide a direct final answer after all chunks have been processed.
;

fn readPrompt(allocator: std.mem.Allocator, args: [][:0]u8) ![]u8 {
    if (args.len > 1) {
        return try allocator.dupe(u8, args[1]);
    }

    std.debug.print(
        "Usage: zig build openclaw -- \"<task>\"\n" ++
            "No task argument provided. Falling back to a sample prompt.\n",
        .{},
    );

    return try allocator.dupe(u8, "Tell me what is the main purpose of the project in the current working directory. ");
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var backend_cfg = config_env.load_backend_env_config(allocator, ".env") catch {
        std.debug.print("Failed to load backend config from .env. Required keys: OMNIRLM_API_KEY (or DASHSCOPE_API_KEY/OPENAI_API_KEY), OMNIRLM_BASE_URL, OMNIRLM_MODEL_NAME.\n", .{});
        return error.MissingBackendConfig;
    };
    defer backend_cfg.deinit(allocator);

    const task_prompt = try readPrompt(allocator, args);
    defer allocator.free(task_prompt);

    const logger = try RLMLogger.init("./logs", "openclaw", allocator);

    var rlm: RLM = .{
        .backend = "openai",
        .backend_kwargs = backend_cfg,
        .environment = "local",
        .environment_kwargs = "{}",
        .max_depth = 2,
        .max_iterations = 8,
        .material_chunk_size = 8 * 1024,
        .custom_system_prompt = openclaw_system_prompt,
        .logger = logger,
        .allocator = allocator,
    };

    try rlm.init();
    defer rlm.deinit();

    const material_path = "README.md";

    const result = try rlm.completion(task_prompt, material_path);
    defer allocator.free(result.response);

    std.debug.print("\n=== OpenClaw (Zig + Omni-RLM) ===\n", .{});
    std.debug.print("Model: {s}\n", .{result.root_model});
    std.debug.print("Execution time: {d}ms\n\n", .{result.execution_time});
    std.debug.print("{s}\n", .{result.response});
}
