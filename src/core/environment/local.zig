const std = @import("std");
pub const LocalEnv = struct {
    mainfunc: []const u8 = "",
    context: ?[]const u8 = null,
    pub fn execute_code(self: *const LocalEnv, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "python", self.mainfunc, code, self.context orelse "" },
        });
        return result;
    }
    pub fn init(self: *LocalEnv, kwargs: []const u8, prompt: []const u8, allocator: std.mem.Allocator) !void {
        const parsed: std.json.Parsed(LocalEnv) = try std.json.parseFromSlice(LocalEnv, allocator, kwargs, .{});
        defer parsed.deinit();
        self.* = parsed.value;
        self.context = prompt;
    }
    pub fn deinit(self: *LocalEnv) void {
        // clean up if necessary
        _ = self;
        std.fs.cwd().deleteFile("env.dill") catch {};
    }
    pub fn find_final_answer(self: *const LocalEnv, text: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
        _ = self;
        const res = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "src/python_script/find_final_answer.py",
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
    const kwags = "{\"mainfunc\": \"src/python_script/env_init.py\"}";
    const parsed: std.json.Parsed(LocalEnv) = try std.json.parseFromSlice(LocalEnv, allocator, kwags, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("src/python_script/env_init.py", parsed.value.mainfunc);
}
