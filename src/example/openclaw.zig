const std = @import("std");
const RLM = @import("omni-rlm").RLM;
const RLMLogger = @import("omni-rlm").RLMLogger;
const config_env = @import("omni-rlm").config_env;

const openclaw_system_prompt =
    \\You are OpenClaw-Zig, an autonomous coding and operations assistant powered by Omni-RLM.
    \\Operate in a deliberate loop:
    \\1) Analyze the user task and environment.
    \\2) Propose a short plan.
    \\3) Execute only the Python code required.
    \\4) Reflect on outputs and update the plan.
    \\5) Return a concise final answer.
    \\
    \\Rules:
    \\- You can use os lib to access the working directory, and can manipulate files.
    \\- Keep actions minimal and verifiable.
    \\- Prefer deterministic commands.
    \\- Executable code MUST appear inside ```python or ```repl fenced blocks.
    \\- Always use print() for any output from Python code, never return values directly from code blocks.
    \\- Never output executable code in unlabeled ``` fences.
    \\- If a step fails, explain why and provide the next best action.
    \\- If you have a final answer, end with either FINAL("<answer>") or FINAL_VAR("<variable_name>").
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
        .backend_kwargs = .{
            .base_url = backend_cfg.base_url,
            .api_key = backend_cfg.api_key,
            .model_name = backend_cfg.model_name,
        },
        .environment = "local",
        .environment_kwargs = "{}",
        .max_depth = 2,
        .max_iterations = 8,
        .custom_system_prompt = openclaw_system_prompt,
        .logger = logger,
        .allocator = allocator,
    };

    try rlm.init();
    defer rlm.deinit();

    const result = try rlm.completion(task_prompt, null);
    defer allocator.free(result.response);

    std.debug.print("\n=== OpenClaw (Zig + Omni-RLM) ===\n", .{});
    std.debug.print("Model: {s}\n", .{result.root_model});
    std.debug.print("Execution time: {d}ms\n\n", .{result.execution_time});
    std.debug.print("{s}\n", .{result.response});
}
