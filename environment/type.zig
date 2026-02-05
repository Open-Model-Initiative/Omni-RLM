const std = @import("std");
pub const local = @import("local.zig").LocalEnv;
pub const daytona = @import("daytona.zig").DaytonaEnv;

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
        }
    }

    pub fn execute_code(self: *const EnvHandler, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        switch (self.*) {
            .local => {
                return self.local.execute_code(code, allocator);
            },
    pub fn deinit(self: *EnvHandler, allocator: std.mem.Allocator) !void {
        switch (self.*) {
            .local => {
                self.local.deinit();
            },
        }
    }
    pub fn find_final_answer(self: *const EnvHandler, response: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
        switch (self.*) {
            .local => {
                return self.local.find_final_answer(response, allocator);
            },
            },
        }
    }
};

test "EnvHandler execute_code" {
    const allocator = std.testing.allocator;
    const environment = "daytona";
    const kwargs = "{\"api_url\": \"https://app.daytona.io/api\", \"api_key\": \"\"}";
    var env: EnvHandler = undefined;
    switch (std.meta.stringToEnum(env_type, environment) orelse env_type.local) {
        .local => {
            var local_env = local{};
            try local_env.init(kwargs, "", allocator);
            env = .{ .local = local_env };
        },
        .daytona => {
            var daytona_env = daytona{};
            try daytona_env.init(kwargs, "", allocator);
            env = .{ .daytona = daytona_env };
        },
    }
    const code = "for i in range(1):\n   print('Hello from EnvHandler')";
    const result = env.execute_code(code, allocator) catch {
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expectEqualStrings("Hello from EnvHandler\n", result.stdout);
    std.fs.cwd().deleteFile("env.dill") catch {};
}

test "environment selection" {
    const allocator = std.testing.allocator;
    const string = try allocator.dupe(u8, "daytona");
    defer allocator.free(string);

    const x = std.meta.stringToEnum(env_type, string) orelse env_type.local;
    std.debug.print("\nEnvironment selected: {s}\n", .{switch (x) {
        .local => "local",
        .daytona => "daytona",
    }});
}
