const std = @import("std");

/// Daytona sandbox environment handler
///
/// Manages code execution in Daytona sandbox containers via API calls.
/// Provides isolated execution environment with automatic container lifecycle management.
///
/// ## Fields
/// - `api_url`: Daytona API endpoint URL
/// - `api_key`: API key for Daytona authentication
/// - `context`: The user prompt/context for the session
/// - `container_id`: ID of the created sandbox container
///
/// ## Example
/// ```zig
/// var env = DaytonaEnv{};
/// try env.init(
///     "{\"api_url\": \"https://app.daytona.io/api\", \"api_key\": \"key\"}",
///     "What is 2+2?",
///     allocator
/// );
/// defer env.deinit(allocator) catch {};
///
/// const result = try env.execute_code("print(2+2)", allocator);
/// defer allocator.free(result.stdout);
/// defer allocator.free(result.stderr);
/// ```
pub const DaytonaEnv = struct {
    api_url: []const u8 = "https://app.daytona.io/api",
    api_key: []const u8 = "",
    context: ?[]const u8 = null,
    container_id: ?[]const u8 = null,

    /// Initialize the Daytona environment
    ///
    /// Creates a new sandbox container via the Daytona API.
    /// The container ID is stored for subsequent operations.
    ///
    /// ## Parameters
    /// - `kwargs`: JSON string with configuration (api_url, api_key)
    /// - `prompt`: The user prompt/context
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Errors
    /// Returns error if container creation fails
    pub fn init(self: *DaytonaEnv, kwargs: []const u8, prompt: []const u8, allocator: std.mem.Allocator) !void {
        const parsed: std.json.Parsed(DaytonaEnv) = try std.json.parseFromSlice(DaytonaEnv, allocator, kwargs, .{});
        defer parsed.deinit();
        self.* = parsed.value;
        self.context = prompt;
        const run_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "environment/daytona_script.py",
                self.api_key,
                "--api-url",
                self.api_url,
                "--container-id",
                self.container_id orelse "",
                "--prompt",
                prompt,
            },
        });
        defer {
            allocator.free(run_result.stdout);
            allocator.free(run_result.stderr);
        }
        std.debug.print("\nContainer: {s} created\n", .{run_result.stdout});
        self.container_id = try allocator.dupe(u8, run_result.stdout);
    }

    /// Deinitialize the Daytona environment
    ///
    /// Deletes the sandbox container and frees associated resources.
    ///
    /// ## Parameters
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Errors
    /// Returns error if container deletion fails
    pub fn deinit(self: *DaytonaEnv, allocator: std.mem.Allocator) !void {
        const run_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "environment/daytona_script.py",
                self.api_key,
                "--api-url",
                self.api_url,
                "--container-id",
                self.container_id orelse "",
                "delete",
            },
        });
        defer {
            allocator.free(run_result.stdout);
            allocator.free(run_result.stderr);
        }
        std.debug.print("\nContainer: {s} deleted\n", .{run_result.stdout});
        if (self.container_id) |id| {
            allocator.free(id);
            self.container_id = null;
        }
    }

    /// Execute code in the Daytona sandbox
    ///
    /// Runs the code in the sandbox container via API call.
    ///
    /// ## Parameters
    /// - `code`: Source code to execute
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// Process execution result with stdout, stderr, and exit status
    ///
    /// ## Errors
    /// Returns error if code execution fails
    pub fn execute_code(self: *const DaytonaEnv, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        const run_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "environment/daytona_script.py",
                self.api_key,
                "--api-url",
                self.api_url,
                "--container-id",
                self.container_id orelse "",
                "--code",
                code,
            },
        });
        return run_result;
    }

    /// Find final answer in model response
    ///
    /// Uses Daytona sandbox to parse FINAL() or FINAL_VAR() markers from text.
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
    pub fn find_final_answer(self: *const DaytonaEnv, text: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
        const run_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "environment/daytona_script.py",
                self.api_key,
                "--api-url",
                self.api_url,
                "--container-id",
                self.container_id orelse "",
                "--find_final_answer",
                text,
            },
        });
        defer {
            allocator.free(run_result.stdout);
            allocator.free(run_result.stderr);
        }
        if (std.mem.eql(u8, run_result.stdout, "None") or run_result.stderr.len != 0 or run_result.stdout.len == 0) {
            return null;
        } else {
            return try allocator.dupe(u8, run_result.stdout);
        }
    }
};

test "DaytonaEnv execute_code" {
    const allocator = std.testing.allocator;
    const kwargs = "{\"api_url\": \"https://app.daytona.io/api\", \"api_key\": \"\"}";
    const parsed = try std.json.parseFromSlice(DaytonaEnv, allocator, kwargs, .{});
    defer parsed.deinit();
    if (parsed.value.api_key.len == 0) {
        std.debug.print("\nSkipping DaytonaEnv execute_code test due to missing daytona api_key.\n", .{});
        return error.SkipZigTest;
    }
    var env = DaytonaEnv{};
    try env.init(kwargs, "This is a prompt", allocator);
    const code = "print(context)\nprint('Hello from DaytonaEnv')";
    const result = try env.execute_code(code, allocator);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expectEqualStrings("This is a prompt\nHello from DaytonaEnv\n", result.stdout);
    try env.deinit(allocator);
}
