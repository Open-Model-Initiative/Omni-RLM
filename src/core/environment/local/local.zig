const std = @import("std");

/// Local Python environment handler
///
/// Manages local Python code execution using subprocess.
/// The Python REPL maintains state across code executions via pickle serialization.
///
/// ## Fields
/// - `mainfunc`: Path to the Python initialization script (env_init.py)
/// - `context`: The user prompt/context passed to the Python environment
///
/// ## Example
/// ```zig
/// var env = LocalEnv{};
/// try env.init(
///     "{\"mainfunc\": \"src/core/environment/local/env_init.py\"}",
///     "What is 2+2?",
///     allocator
/// );
/// defer env.deinit();
///
/// const result = try env.execute_code("print(2+2)", allocator);
/// defer allocator.free(result.stdout);
/// defer allocator.free(result.stderr);
/// ```
pub const LocalEnv = struct {
    mainfunc: []const u8 = "",
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
            .argv = &[_][]const u8{ "python", self.mainfunc, code, self.context orelse "" },
        });
        return result;
    }

    /// Initialize the local environment
    ///
    /// Parses configuration from JSON and sets up the context.
    ///
    /// ## Parameters
    /// - `kwargs`: JSON string with configuration (mainfunc path)
    /// - `prompt`: The user prompt/context
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Errors
    /// Returns error if JSON parsing fails
    pub fn init(self: *LocalEnv, kwargs: []const u8, prompt: []const u8, allocator: std.mem.Allocator) !void {
        const parsed: std.json.Parsed(LocalEnv) = try std.json.parseFromSlice(LocalEnv, allocator, kwargs, .{});
        defer parsed.deinit();
        self.* = parsed.value;
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
        const res = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "src/core/environment/local/find_final_answer.py",
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

test "read json kwargs in LocalEnv" {
    const allocator = std.testing.allocator;
    const kwags = "{\"mainfunc\": \"src/core/environment/local/env_init.py\"}";
    const parsed: std.json.Parsed(LocalEnv) = try std.json.parseFromSlice(LocalEnv, allocator, kwags, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("src/core/environment/local/env_init.py", parsed.value.mainfunc);
}
