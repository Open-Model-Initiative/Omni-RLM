const std = @import("std");
const RLM = @import("omni-rlm").RLM;
const RLMLogger = @import("omni-rlm").RLMLogger;

const openclaw_system_prompt =
    \\You are OpenClaw-Zig, an autonomous coding and operations assistant powered by Omni-RLM.
    \\Operate in a deliberate loop:
    \\1) Analyze the user task and environment.
    \\2) Propose a short plan.
    \\3) Execute only the code or shell actions required.
    \\4) Reflect on outputs and update the plan.
    \\5) Return a concise final answer.
    \\
    \\Rules:
    \\- Keep actions minimal and verifiable.
    \\- Prefer deterministic commands.
    \\- If a step fails, explain why and provide the next best action.
    \\- Always end with a "Final answer" section.
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

    return try allocator.dupe(u8, "Inspect this repository and suggest one improvement.");
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const api_key = std.process.getEnvVarOwned(allocator, "OPENAI_API_KEY") catch {
        std.debug.print("Environment variable OPENAI_API_KEY is not set.\n", .{});
        return error.MissingApiKey;
    };
    defer allocator.free(api_key);

    const base_url = std.process.getEnvVarOwned(allocator, "OPENAI_BASE_URL") catch try allocator.dupe(u8, "https://api.openai.com/v1/chat/completions");
    defer allocator.free(base_url);

    const model_name = std.process.getEnvVarOwned(allocator, "OPENAI_MODEL") catch try allocator.dupe(u8, "gpt-4o-mini");
    defer allocator.free(model_name);

    const task_prompt = try readPrompt(allocator, args);
    defer allocator.free(task_prompt);

    const logger = try RLMLogger.init("./logs", "openclaw", allocator);

    var rlm: RLM = .{
        .backend = "openai",
        .backend_kwargs = .{
            .base_url = base_url,
            .api_key = api_key,
            .model_name = model_name,
        },
        .environment = "local",
        .environment_kwargs = "{\"mainfunc\": \"src/core/environment/local/env_init.py\"}",
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
