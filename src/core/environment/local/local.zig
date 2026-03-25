const std = @import("std");

/// Local material storage for long-text processing.
pub const LocalEnv = struct {
    context: ?[]const u8 = null,

    /// Store the source material for the session.
    pub fn init(self: *LocalEnv, prompt: []const u8) !void {
        self.context = prompt;
    }

    /// Return the number of chunks in the stored material.
    pub fn count_chunks(self: *const LocalEnv, chunk_size: usize) usize {
        const material = self.context orelse "";
        const safe_chunk_size = @max(chunk_size, 1);
        if (material.len == 0) return 1;
        return std.math.divCeil(usize, material.len, safe_chunk_size) catch unreachable;
    }

    /// Read a chunk by index.
    pub fn read_chunk(self: *const LocalEnv, chunk_index: usize, chunk_size: usize, allocator: std.mem.Allocator) ![]u8 {
        const material = self.context orelse "";
        const safe_chunk_size = @max(chunk_size, 1);

        if (material.len == 0) {
            if (chunk_index == 0) {
                return try allocator.dupe(u8, "");
            }
            return error.InvalidChunkIndex;
        }

        const start = chunk_index * safe_chunk_size;
        if (start >= material.len) {
            return error.InvalidChunkIndex;
        }

        const end = @min(start + safe_chunk_size, material.len);
        return try allocator.dupe(u8, material[start..end]);
    }

    /// Deinitialize the local environment.
    pub fn deinit(self: *LocalEnv) void {
        self.* = undefined;
    }
};

test "LocalEnv init sets context" {
    var env = LocalEnv{};
    try env.init("test prompt");
    try std.testing.expect(env.context != null);
    try std.testing.expectEqualStrings("test prompt", env.context.?);
}

test "LocalEnv reads chunks" {
    const allocator = std.testing.allocator;
    var env = LocalEnv{};
    try env.init("abcdefghijklmnopqrstuvwxyz");

    try std.testing.expectEqual(@as(usize, 6), env.count_chunks(5));

    const chunk = try env.read_chunk(2, 5, allocator);
    defer allocator.free(chunk);
    try std.testing.expectEqualStrings("klmno", chunk);
}
