const std = @import("std");
pub const local = @import("local/local.zig").LocalEnv;

/// Environment type enumeration
///
/// Defines the available material storage backends.
pub const env_type = enum {
    /// Local in-memory material storage.
    local,
};

/// Union type for environment handlers
///
/// Provides a unified interface for different material storage environments.
/// Use this type to work with any supported environment uniformly.
pub const EnvHandler = union(env_type) {
    local: local,

    /// Initialize the environment handler
    ///
    /// ## Parameters
    /// - `etype`: The environment type to initialize
    /// - `kwargs`: JSON string with environment-specific configuration
    /// - `material`: The long-form material for the session
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Errors
    /// Returns error if initialization fails or configuration is invalid
    pub fn init(self: *EnvHandler, etype: env_type, kwargs: []const u8, material: []const u8, allocator: std.mem.Allocator) !void {
        _ = kwargs;
        _ = allocator;
        switch (etype) {
            .local => {
                var local_env = local{};
                try local_env.init(material);
                self.* = .{ .local = local_env };
            },
        }
    }

    /// Return the number of chunks in the stored material.
    pub fn count_chunks(self: *const EnvHandler, chunk_size: usize) usize {
        switch (self.*) {
            .local => {
                return self.local.count_chunks(chunk_size);
            },
        }
    }

    /// Read a single material chunk.
    pub fn read_chunk(self: *const EnvHandler, chunk_index: usize, chunk_size: usize, allocator: std.mem.Allocator) ![]u8 {
        switch (self.*) {
            .local => {
                return self.local.read_chunk(chunk_index, chunk_size, allocator);
            },
        }
    }

    /// Read a chunk with overlap from previous chunk for context preservation.
    pub fn read_chunk_with_overlap(
        self: *const EnvHandler,
        chunk_index: usize,
        chunk_size: usize,
        overlap_size: usize,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        switch (self.*) {
            .local => {
                // Temporarily set overlap size on the local env
                var env_copy = self.local;
                env_copy.setOverlap(overlap_size);
                return env_copy.read_chunk_with_overlap(chunk_index, chunk_size, allocator);
            },
        }
    }

    /// Set overlap size for context preservation between chunks.
    pub fn set_overlap(self: *EnvHandler, overlap: usize) void {
        switch (self.*) {
            .local => {
                self.local.setOverlap(overlap);
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
        _ = allocator;
        switch (self.*) {
            .local => {
                self.local.deinit();
            },
        }
    }

};

test "EnvHandler local read_chunk" {
    const allocator = std.testing.allocator;

    var env: EnvHandler = undefined;
    try env.init(.local, "{}", "abcdefghijklmnopqrstuvwxyz", allocator);
    const result = try env.read_chunk(1, 5, allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("fghij", result);
    try env.deinit(allocator);
}

test "EnvHandler local read_chunk_with_overlap" {
    const allocator = std.testing.allocator;

    var env: EnvHandler = undefined;
    try env.init(.local, "{}", "Sentence one. Sentence two. Sentence three.", allocator);
    
    // Set overlap size
    env.set_overlap(10);
    
    // Read chunk 1 with overlap
    const result = try env.read_chunk_with_overlap(1, 15, 10, allocator);
    defer allocator.free(result);
    
    // Chunk 1 should include overlap from chunk 0
    try std.testing.expect(result.len > 0);
    
    try env.deinit(allocator);
}
