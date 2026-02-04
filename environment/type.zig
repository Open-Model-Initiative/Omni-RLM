const std = @import("std");
const local = @import("local.zig");
const daytona = @import("daytona.zig");

pub const env_type = enum {
    local,
    daytona,
};

pub const EnvHandler = union(env_type) {
    local: local.LocalEnv,
    daytona: daytona.DaytonaEnv,

    pub fn execute_code(self: *const EnvHandler, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        switch (self.*) {
            .local => |local_env| {
                return local_env.execute_code(code, allocator);
            },
            .daytona => |daytona_env| {
                // Use daytona_env.api, daytona_env.context, daytona_env.container_id
                return daytona_env.execute_code(code, allocator);
            },
        }
    }
};

test "EnvHandler local execute_code" {
    const allocator = std.testing.allocator;
    var env = EnvHandler{
        .local = .{
            .mainfunc = "python_script/env_init.py",
            .context = null,
        },
    };
    const code = "for i in range(1):\n   print('Hello from EnvHandler')";
    const result = try env.execute_code(code, allocator);
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
