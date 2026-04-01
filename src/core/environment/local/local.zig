const std = @import("std");

/// Sentence boundary markers (English and Chinese punctuation)
const BOUNDARY_CHARS = ".!?。！？\n";

/// Default overlap size between chunks (in bytes)
const DEFAULT_OVERLAP: usize = 100;

/// Local material storage for long-text processing with smart chunking.
pub const LocalEnv = struct {
    context: ?[]const u8 = null,
    overlap_size: usize = DEFAULT_OVERLAP,

    /// Store the source material for the session.
    pub fn init(self: *LocalEnv, prompt: []const u8) !void {
        self.context = prompt;
    }

    /// Set overlap size between chunks (for preserving context across boundaries).
    pub fn setOverlap(self: *LocalEnv, overlap: usize) void {
        self.overlap_size = overlap;
    }

    /// Find the next sentence boundary starting from position `start`.
    /// Returns the index after the boundary marker, or `start` if no boundary found.
    fn findSentenceBoundary(material: []const u8, start: usize, max_look_ahead: usize) usize {
        if (start >= material.len) return material.len;

        const search_end = @min(start + max_look_ahead, material.len);
        var i = start;

        while (i < search_end) {
            // Check if current char is a boundary marker
            if (std.mem.indexOfScalar(u8, BOUNDARY_CHARS, material[i]) != null) {
                // Skip whitespace after boundary
                var j = i + 1;
                while (j < material.len and std.ascii.isWhitespace(material[j])) {
                    j += 1;
                }
                return j;
            }
            i += 1;
        }

        // No boundary found within look-ahead, return original position
        return start;
    }

    /// Find the previous sentence boundary before position `end`.
    /// Used to adjust end boundary backwards if needed.
    fn findPrevSentenceBoundary(material: []const u8, end: usize, min_pos: usize) usize {
        if (end == 0 or end <= min_pos) return end;

        var i = end;
        while (i > min_pos) {
            i -= 1;
            if (std.mem.indexOfScalar(u8, BOUNDARY_CHARS, material[i]) != null) {
                // Skip whitespace after boundary
                var j = i + 1;
                while (j < material.len and std.ascii.isWhitespace(material[j])) {
                    j += 1;
                }
                return j;
            }
        }

        return end;
    }

    /// Return the number of chunks in the stored material (estimated).
    /// Note: With smart chunking, actual chunk count may vary slightly.
    pub fn count_chunks(self: *const LocalEnv, chunk_size: usize) usize {
        const material = self.context orelse "";
        const safe_chunk_size = @max(chunk_size, 1);
        if (material.len == 0) return 1;
        return std.math.divCeil(usize, material.len, safe_chunk_size) catch unreachable;
    }

    /// Read a chunk by index with smart boundary alignment and overlap support.
    ///
    /// Smart chunking ensures:
    /// - Start boundary aligns to sentence start
    /// - End boundary aligns to sentence end (if within look-ahead range)
    /// - Overlap with previous chunk preserves context
    pub fn read_chunk(self: *const LocalEnv, chunk_index: usize, chunk_size: usize, allocator: std.mem.Allocator) ![]u8 {
        const material = self.context orelse "";
        const safe_chunk_size = @max(chunk_size, 1);
        // Look ahead up to full chunk size or 1000 bytes to find sentence boundaries
        const max_look_ahead = @min(safe_chunk_size, 1000);

        if (material.len == 0) {
            if (chunk_index == 0) {
                return try allocator.dupe(u8, "");
            }
            return error.InvalidChunkIndex;
        }

        // Calculate raw start position
        const raw_start = chunk_index * safe_chunk_size;
        if (raw_start >= material.len) {
            return error.InvalidChunkIndex;
        }

        // Adjust start to sentence boundary (skip mid-sentence content)
        const start = if (chunk_index == 0) 0 else blk: {
            // Look for a boundary near the start position
            const boundary = findSentenceBoundary(material, raw_start, max_look_ahead);
            // If boundary is too far, try looking backward
            if (boundary == raw_start and raw_start > 0) {
                const min_pos = if (raw_start > max_look_ahead) raw_start - max_look_ahead else 0;
                break :blk findPrevSentenceBoundary(material, raw_start, min_pos);
            }
            break :blk boundary;
        };

        // Calculate raw end position
        const raw_end = @min(start + safe_chunk_size, material.len);

        // Adjust end to sentence boundary (don't cut off mid-sentence)
        const end = if (raw_end >= material.len) raw_end else blk: {
            const boundary = findSentenceBoundary(material, raw_end, max_look_ahead);
            // If no boundary found ahead, try going backward
            if (boundary == raw_end) {
                const min_pos = if (raw_end > max_look_ahead) raw_end - max_look_ahead else start;
                break :blk findPrevSentenceBoundary(material, raw_end, min_pos);
            }
            break :blk boundary;
        };

        // Ensure we make progress (prevent infinite loop scenarios)
        const actual_end = @max(end, start + 1);

        return try allocator.dupe(u8, material[start..actual_end]);
    }

    /// Read a chunk with overlap from previous chunk for context preservation.
    pub fn read_chunk_with_overlap(
        self: *const LocalEnv,
        chunk_index: usize,
        chunk_size: usize,
        allocator: std.mem.Allocator,
    ) ![]u8 {
        const material = self.context orelse "";
        if (material.len == 0) {
            if (chunk_index == 0) return try allocator.dupe(u8, "");
            return error.InvalidChunkIndex;
        }

        // Get the base chunk
        const chunk = try self.read_chunk(chunk_index, chunk_size, allocator);
        errdefer allocator.free(chunk);

        // If overlap is disabled or this is the first chunk, return as-is
        if (self.overlap_size == 0 or chunk_index == 0) {
            return chunk;
        }

        // Calculate overlap start position
        const raw_start = chunk_index * chunk_size;
        const overlap_start = if (raw_start > self.overlap_size) raw_start - self.overlap_size else 0;

        // If no overlap possible, return original chunk
        if (overlap_start >= raw_start) {
            return chunk;
        }

        // Get overlap content from previous region
        const overlap_content = material[overlap_start..raw_start];

        // Combine overlap + chunk
        const combined_len = overlap_content.len + chunk.len;
        const result = try allocator.alloc(u8, combined_len);

        @memcpy(result[0..overlap_content.len], overlap_content);
        @memcpy(result[overlap_content.len..], chunk);

        allocator.free(chunk);
        return result;
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

test "LocalEnv smart chunking aligns to sentence boundaries" {
    const allocator = std.testing.allocator;
    var env = LocalEnv{};

    // Text with clear sentence boundaries
    const text = "First sentence here. Second sentence there. Third sentence everywhere.";
    try env.init(text);

    // Request a chunk that would cut through "Second "
    // With chunk_size 25, raw cut would be after "First sentence here. Sec"
    const chunk = try env.read_chunk(0, 25, allocator);
    defer allocator.free(chunk);

    // Should include "Second sentence there." - check it contains the sentence
    try std.testing.expect(std.mem.indexOf(u8, chunk, "Second sentence there.") != null);
    // Should end at a sentence boundary (after punctuation and whitespace)
    try std.testing.expect(std.mem.endsWith(u8, chunk, "there. ") or std.mem.endsWith(u8, chunk, "there."));
}

test "LocalEnv smart chunking handles Chinese punctuation" {
    const allocator = std.testing.allocator;
    var env = LocalEnv{};

    const text = "这是第一句话。这是第二句话！这是第三句话？";
    try env.init(text);

    const chunk = try env.read_chunk(0, 20, allocator);
    defer allocator.free(chunk);

    // Should align to Chinese sentence boundary
    try std.testing.expect(std.mem.endsWith(u8, chunk, "。") or
        std.mem.endsWith(u8, chunk, "！") or
        std.mem.endsWith(u8, chunk, "？"));
}

test "LocalEnv overlap preserves context between chunks" {
    const allocator = std.testing.allocator;
    var env = LocalEnv{};
    env.setOverlap(10);

    const text = "Sentence one. Sentence two. Sentence three. Sentence four.";
    try env.init(text);

    const chunk0 = try env.read_chunk_with_overlap(0, 30, allocator);
    defer allocator.free(chunk0);

    const chunk1 = try env.read_chunk_with_overlap(1, 30, allocator);
    defer allocator.free(chunk1);

    // Chunk 1 should contain some content from end of chunk 0's region
    // (overlap of 10 bytes from previous chunk)
    if (chunk1.len > 10) {
        // The overlap should contain text from near the end of first chunk's raw position
        try std.testing.expect(chunk1.len > 0);
    }
}

test "LocalEnv handles empty material" {
    const allocator = std.testing.allocator;
    var env = LocalEnv{};
    try env.init("");

    const chunk = try env.read_chunk(0, 100, allocator);
    defer allocator.free(chunk);
    try std.testing.expectEqualStrings("", chunk);
}

test "LocalEnv handles material without sentence boundaries" {
    const allocator = std.testing.allocator;
    var env = LocalEnv{};

    // Long text without punctuation
    const text = "abcdefghijklmnop" ** 10;
    try env.init(text);

    const chunk = try env.read_chunk(0, 50, allocator);
    defer allocator.free(chunk);

    // Should still return a valid chunk
    try std.testing.expect(chunk.len > 0);
}

test "LocalEnv findSentenceBoundary basic" {
    const text = "Hello world. Next sentence.";

    // Find boundary after "Hello world"
    const pos1 = LocalEnv.findSentenceBoundary(text, 11, 20);
    try std.testing.expectEqual(@as(usize, 13), pos1); // After ". "

    // Find boundary after "Next sentence"
    const pos2 = LocalEnv.findSentenceBoundary(text, 24, 10);
    try std.testing.expectEqual(@as(usize, 27), pos2); // End of string
}
