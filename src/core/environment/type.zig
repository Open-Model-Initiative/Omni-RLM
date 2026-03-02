const std = @import("std");
pub const local = @import("local/local.zig").LocalEnv;
pub const daytona = @import("daytona/daytona.zig").DaytonaEnv;

/// Environment type enumeration
///
/// Defines the available execution environments for code execution.
pub const env_type = enum {
    /// Local Python environment using subprocess execution
    local,
    /// Daytona sandbox environment for isolated execution
    daytona,
};

/// Union type for environment handlers
///
/// Provides a unified interface for different execution environments.
/// Use this type to work with any supported environment uniformly.
///
/// ## Example
/// ```zig
/// var env: EnvHandler = undefined;
/// try env.init(env_type.local, kwargs, prompt, allocator);
/// defer env.deinit(allocator) catch {};
///
/// const result = try env.execute_code("print('hello')", allocator);
/// ```
pub const EnvHandler = union(env_type) {
    local: local,
    daytona: daytona,

    /// Initialize the environment handler
    ///
    /// ## Parameters
    /// - `etype`: The environment type to initialize
    /// - `kwargs`: JSON string with environment-specific configuration
    /// - `prompt`: The user prompt/context for the session
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Errors
    /// Returns error if initialization fails or configuration is invalid
    pub fn init(self: *EnvHandler, etype: env_type, kwargs: []const u8, prompt: []const u8, allocator: std.mem.Allocator) !void {
        switch (etype) {
            .local => {
                var local_env = local{};
                try local_env.init(kwargs, prompt, allocator);
                self.* = .{ .local = local_env };
            },
            .daytona => {
                var daytona_env = daytona{};
                try daytona_env.init(kwargs, prompt, allocator);
                self.* = .{ .daytona = daytona_env };
            },
        }
    }

    /// Execute code in the environment
    ///
    /// ## Parameters
    /// - `code`: The source code to execute
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// Process execution result containing stdout, stderr, and exit status
    ///
    /// ## Errors
    /// Returns error if code execution fails
    pub fn execute_code(self: *const EnvHandler, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        switch (self.*) {
            .local => {
                return self.local.execute_code(code, allocator);
            },
            .daytona => {
                return self.daytona.execute_code(code, allocator);
            },
        }
    }

    /// Deinitialize the environment
    ///
    /// Frees resources associated with the environment.
    ///
    /// ## Parameters
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Errors
    /// Returns error if cleanup fails
    pub fn deinit(self: *EnvHandler, allocator: std.mem.Allocator) !void {
        switch (self.*) {
            .local => {
                self.local.deinit();
            },
            .daytona => {
                try self.daytona.deinit(allocator);
            },
        }
    }

    /// Find the final answer in a response
    ///
    /// Parses the model response to extract FINAL() or FINAL_VAR() markers.
    ///
    /// ## Parameters
    /// - `response`: The model response text to parse
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// The extracted final answer, or null if not found
    ///
    /// ## Errors
    /// Returns error if parsing fails
    pub fn find_final_answer(self: *const EnvHandler, response: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
        switch (self.*) {
            .local => {
                return self.local.find_final_answer(response, allocator);
            },
            .daytona => {
                return self.daytona.find_final_answer(response, allocator);
            },
        }
    }
};

test "EnvHandler local execute_code" {
    const allocator = std.testing.allocator;

    //// Test with local environment
    const environment = "local";
    const kwargs = "{\"mainfunc\": \"src/core/environment/local/env_init.py\"}";

    var env: EnvHandler = undefined;
    const Test_env_type = std.meta.stringToEnum(env_type, environment) orelse env_type.local;
    try env.init(Test_env_type, kwargs, "", allocator);
    switch (env) {
        .local => {},
        .daytona => |daytona_env| {
            if (daytona_env.api_key.len == 0) {
                std.debug.print("\nSkipping EnvHandler execute_code test due to missing daytona api_key.\n", .{});
                return error.SkipZigTest;
            }
        },
    }
    const code = "for i in range(1):\n   print('Hello from EnvHandler')";
    const result = try env.execute_code(code, allocator);
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    try std.testing.expectEqualStrings("Hello from EnvHandler\n", result.stdout);
    try env.deinit(allocator);
}
test "EnvHandler daytona execute_code" {
    const allocator = std.testing.allocator;

    //// Test with daytona environment
    const environment = "daytona";
    const kwargs = "{\"api_url\": \"https://app.daytona.io/api\", \"api_key\": \"\"}";
    const parsed = try std.json.parseFromSlice(daytona, allocator, kwargs, .{});
    defer parsed.deinit();
    if (parsed.value.api_key.len == 0) {
        std.debug.print("\nSkipping DaytonaEnv execute_code test due to missing daytona api_key.\n", .{});
        return error.SkipZigTest;
    }

    var env: EnvHandler = undefined;
    const Test_env_type = std.meta.stringToEnum(env_type, environment) orelse env_type.local;
    try env.init(Test_env_type, kwargs, "", allocator);
    switch (env) {
        .local => {},
        .daytona => |daytona_env| {
            if (daytona_env.api_key.len == 0) {
                std.debug.print("\nSkipping EnvHandler execute_code test due to missing daytona api_key.\n", .{});
                return error.SkipZigTest;
            }
        },
    }
    const code = "for i in range(1):\n   print('Hello from EnvHandler')";
    const result = try env.execute_code(code, allocator);
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }
    try std.testing.expectEqualStrings("Hello from EnvHandler\n", result.stdout);
    try env.deinit(allocator);
}
