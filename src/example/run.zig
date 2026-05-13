const RLMLogger = @import("omni-rlm").RLMLogger;
const std = @import("std");
const RLM = @import("omni-rlm").RLM;
const config_env = @import("omni-rlm").config_env;

/// Basic RLM example demonstrating smart chunking with sentence boundary alignment
/// and optional overlap for context preservation.
///
/// Smart chunking features:
/// - Automatically aligns chunk boundaries to sentence boundaries
/// - Supports both English (. ! ?) and Chinese (。！？) punctuation
/// - Overlap between chunks preserves context across boundaries
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var backend_cfg = config_env.load_backend_env_config(allocator, ".env") catch |err| {
        return err;
    };
    defer backend_cfg.deinit(allocator);

    std.debug.print(
        \\******* RLM Smart Chunking Demo *******
        \\This demo shows:
        \\  1. Sentence boundary alignment (chunks end at . ! ? 。！？)
        \\  2. Context overlap between chunks (configurable)
        \\***************************************
    , .{});

    const logger = try RLMLogger.init("./logs", "run", allocator);

    // Configuration: Smart chunking with overlap
    // - chunk_overlap: 500 bytes of context from previous chunk
    //   This helps maintain continuity when processing long documents
    var rlm: RLM = .{
        .backend = "openai",
        .backend_kwargs = backend_cfg,
        .environment = "local",
        .environment_kwargs = "{}",
        .max_depth = 1,
        .material_chunk_size = 8 * 1024, // 8KB base chunk size
        .chunk_overlap = 500, // 500 bytes overlap for context preservation
        .logger = logger,
        .allocator = allocator,
        .max_iterations = 5,
        .parallel = true, // Enable parallel processing of chunks
    };

    try rlm.init();
    defer rlm.deinit();

    const root =
        "Based on this API reference, return a minimal directly executable Zig example showing how to call " ++
        "completion.";
    const material_path = "API_reference.md";

    std.debug.print("\nINPUT: {s}\n", .{root});
    std.debug.print("Material: {s}\n", .{material_path});
    std.debug.print("Chunk size: {d} bytes\n", .{rlm.material_chunk_size});
    std.debug.print("Chunk overlap: {d} bytes\n\n", .{rlm.chunk_overlap});

    const result = try rlm.completion(root, material_path);
    defer allocator.free(result.response);

    std.debug.print("\n========== RESULT ==========\n", .{});
    std.debug.print("Total execution time: {d}ms\n", .{result.execution_time});
    std.debug.print("Model used: {s}\n\n", .{result.root_model});
    std.debug.print("Answer:\n{s}\n", .{result.response});
    std.debug.print("\n******* RLM finished *******\n", .{});
}

/// Alternative example: Smart chunking without overlap
/// Use this for independent chunk processing where context carry-over is not needed
fn runWithoutOverlap(allocator: std.mem.Allocator, backend_cfg: anytype, logger: RLMLogger) !void {
    var rlm: RLM = .{
        .backend = "openai",
        .backend_kwargs = backend_cfg,
        .environment = "local",
        .max_depth = 1,
        .material_chunk_size = 16 * 1024, // Larger chunks without overlap
        .chunk_overlap = 0, // No overlap - chunks are processed independently
        .logger = logger,
        .allocator = allocator,
        .max_iterations = 8,
    };

    try rlm.init();
    defer rlm.deinit();

    const root = "Summarize the key features of this API.";
    const result = try rlm.completion(root, "API_reference.md");
    defer allocator.free(result.response);

    std.debug.print("Result: {s}\n", .{result.response});
}
