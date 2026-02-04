const std = @import("std");
pub const LocalEnv = struct {
    mainfunc: []const u8,
    context: ?[]const u8,
    pub fn execute_code(self: *const LocalEnv, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "python", self.mainfunc, code, self.context orelse "" },
        });
        return result;
    }
};
