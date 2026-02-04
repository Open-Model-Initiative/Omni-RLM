const std = @import("std");
pub const DaytonaEnv = struct {
    api_url: []const u8 = "",
    api_key: []const u8 = "",
    context: ?[]const u8 = null,
    container_id: ?[]const u8 = null,
    pub fn execute_code(self: *const DaytonaEnv, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        // Use self.api_url, self.context, self.container_id
        _ = self;
        _ = code;
        _ = allocator;
        return error.NotImplemented;
    }
    pub fn init(self: *DaytonaEnv, kwargs: []const u8, prompt: []const u8, allocator: std.mem.Allocator) !void {
        const parsed: std.json.Parsed(DaytonaEnv) = try std.json.parseFromSlice(DaytonaEnv, allocator, kwargs, .{});
        defer parsed.deinit();
        self.* = parsed.value;
        self.context = prompt;
    }
};
test "read json kwargs in DaytonaEnv" {
    const allocator = std.testing.allocator;
    const kwags = "{\"api_url\": \"http://daytona.api.endpoint\", \"container_id\": \"container_123\"}";
    const prompt = "This is a prompt.";
    var env = DaytonaEnv{};
    try env.init(kwags, prompt, allocator);
    try std.testing.expectEqualStrings("http://daytona.api.endpoint", env.api_url);
    try std.testing.expectEqualStrings("container_123", env.container_id orelse "");
}
