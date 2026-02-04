const std = @import("std");
pub const DaytonaEnv = struct {
    api: []const u8,
    context: []const u8,
    container_id: []const u8,
    pub fn execute_code(self: *const DaytonaEnv, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        // Use self.api, self.context, self.container_id
        _ = self;
        _ = code;
        _ = allocator;
        return error.NotImplemented;
    }
};
