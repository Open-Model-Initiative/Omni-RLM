const std = @import("std");

const local_init_script =
    \\import dill, sys, dotenv
    \\dotenv.load_dotenv()
    \\def FINAL_VAR(name):
    \\    variable_name = name.strip().strip("\"'")
    \\    if variable_name in globals():
    \\        return str(globals()[variable_name])
    \\    return None
    \\def FINAL(name):
    \\    """Return the value as a final answer."""
    \\    return str(name)
    \\def llm_query(prompt):
    \\    from openai import OpenAI
    \\    api_key = os.getenv("OMNIRLM_API_KEY")
    \\    client = OpenAI(api_key=api_key, base_url=os.getenv("OMNIRLM_BASE_URL"))
    \\    response = client.chat.completions.create(
    \\        model=os.getenv("OMNIRLM_MODEL_NAME"),
    \\        messages=[{"role": "system", "content": "You are a helpful assistant."},{"role": "user", "content": prompt}],
    \\    )
    \\    return response.choices[0].message.content or ""
    \\code = sys.argv[1]
    \\context = sys.argv[2] if len(sys.argv) > 2 else ""
    \\try:
    \\    dill.load_session("env.dill")
    \\except FileNotFoundError:
    \\    pass
    \\exec(code)
    \\del code
    \\dill.dump_session("env.dill")
;

/// Local Python environment handler
///
/// Manages local Python code execution using subprocess.
/// The Python REPL maintains state across code executions via pickle serialization.
///
/// ## Fields
/// - `context`: The user prompt/context passed to the Python environment
///
/// ## Example
/// ```zig
/// var env = LocalEnv{};
/// try env.init("What is 2+2?", allocator);
/// defer env.deinit();
///
/// const result = try env.execute_code("print(2+2)", allocator);
/// defer allocator.free(result.stdout);
/// defer allocator.free(result.stderr);
/// ```
pub const LocalEnv = struct {
    context: ?[]const u8 = null,

    /// Execute Python code in the local REPL environment
    ///
    /// Runs the code through the Python initialization script which maintains
    /// state across calls using pickle serialization (env.dill).
    ///
    /// ## Parameters
    /// - `code`: Python source code to execute
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// Process execution result with stdout, stderr, and exit status
    ///
    /// ## Errors
    /// Returns error if Python execution fails
    pub fn execute_code(self: *const LocalEnv, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "python", "-c", local_init_script, code, self.context orelse "" },
        });
        return result;
    }

    /// Initialize the local environment
    ///
    /// Stores prompt context for the local execution session.
    ///
    /// ## Parameters
    /// - `prompt`: The user prompt/context
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Errors
    /// Reserved for interface compatibility; currently does not return custom init errors.
    pub fn init(self: *LocalEnv, prompt: []const u8) !void {
        self.context = prompt;
    }

    /// Deinitialize the local environment
    ///
    /// Cleans up by deleting the pickle state file (env.dill).
    pub fn deinit(self: *LocalEnv) void {
        // clean up if necessary
        _ = self;
        std.fs.cwd().deleteFile("env.dill") catch {};
    }

    /// Find final answer in model response
    ///
    /// Uses Python script to parse FINAL() or FINAL_VAR() markers from text.
    ///
    /// ## Parameters
    /// - `text`: The model response text to parse
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// The extracted final answer, or null if not found
    ///
    /// ## Errors
    /// Returns error if parsing fails
    pub fn find_final_answer(self: *const LocalEnv, text: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
        _ = self;
        const find_final_answer_script =
            \\import re, sys, dill
            \\dill.load_session("env.dill")
            \\text = sys.argv[1]
            \\final_var_pattern = r"^\s*FINAL(_VAR)?\((.*?)\)"
            \\match = re.search(final_var_pattern, text, re.MULTILINE | re.DOTALL)
            \\if match:
            \\    variable_name = match.group(2).strip().strip('"').strip("'")
            \\    if variable_name in globals():
            \\        final_answer = FINAL_VAR(variable_name)
            \\    else:
            \\        final_answer = FINAL(variable_name)
            \\    if final_answer is not None:
            \\        final_answer = final_answer.strip()
            \\    print(final_answer if final_answer else None)
        ;
        const res = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "-c",
                find_final_answer_script,
                text,
            },
        });
        defer allocator.free(res.stdout);
        defer allocator.free(res.stderr);
        if (std.mem.eql(u8, res.stdout, "None\n") or res.stderr.len != 0 or res.stdout.len == 0) {
            return null;
        } else {
            return try allocator.dupe(u8, res.stdout);
        }
    }
};

test "LocalEnv init sets context" {
    var env = LocalEnv{};
    try env.init("test prompt");
    try std.testing.expect(env.context != null);
    try std.testing.expectEqualStrings("test prompt", env.context.?);
}
