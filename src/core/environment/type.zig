const std = @import("std");
pub const local = @import("local/local.zig").LocalEnv;
pub const daytona = @import("daytona/daytona.zig").DaytonaEnv;

pub const env_type = enum {
    local,
    daytona,
};

pub const EnvHandler = union(env_type) {
    local: local,
    daytona: daytona,

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
