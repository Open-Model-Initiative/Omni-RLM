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
};

test "read json kwargs in LocalEnv" {
    const allocator = std.testing.allocator;
    const kwags = "{\"mainfunc\": \"python_script/env_init.py\"}";
    const parsed: std.json.Parsed(LocalEnv) = try std.json.parseFromSlice(LocalEnv, allocator, kwags, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("python_script/env_init.py", parsed.value.mainfunc);
}
