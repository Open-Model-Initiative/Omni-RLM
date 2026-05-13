const RLMLogger = @import("rlm_logger.zig").RLMLogger;
const std = @import("std");
const backendKwargs = @import("types.zig").backendKwargs;
const PROMPT = @import("prompt.zig");
const RLMIteration = @import("types.zig").RLMIteration;
const QueryMetadata = @import("types.zig").QueryMetadata;
const RLMMetadata = @import("types.zig").RLMMetadata;
const Message = @import("types.zig").Message;
const ModelHandler = @import("Model_info.zig").ModelHandler;
const environment = @import("environment/type.zig");
const RLMChatCompletion = @import("types.zig").RLMChatCompletion;

// ---------------------------------------------------------------------------
// Parallel chunk processing helpers
// ---------------------------------------------------------------------------

/// Result produced by a single parallel chunk worker thread.
/// `summary` is allocated with `std.heap.page_allocator`; the parent must free it.
const ChunkWorkerResult = struct {
    summary: ?[]u8 = null,
    iteration_time: i64 = 0,
    err: ?anyerror = null,
};

/// Arguments passed to each parallel chunk worker thread.
const ChunkWorkerCtx = struct {
    root_prompt: []const u8,
    /// Slice owned by the parent; valid for the lifetime of the thread.
    chunk: []const u8,
    chunk_index: u32,
    /// Pre-loaded CA bundle from the main thread (read-only, shared across
    /// all workers). Must outlive every worker thread.
    ca_bundle: *const std.crypto.Certificate.Bundle,
    total_chunks: u32,
    /// Read-only slice; safe to share across threads.
    base_messages: []const Message,
    lm_handler: ModelHandler,
    result: *ChunkWorkerResult,
};

/// Thread entry point: processes one material chunk independently.
/// Uses its own arena allocator; the final summary is duped into page_allocator
/// so it survives after the arena is freed.
fn chunkWorker(ctx: ChunkWorkerCtx) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const iter_start = std.time.milliTimestamp();

    var user_prompt = PROMPT.buildUserPrompt(.{
        .root_prompt = ctx.root_prompt,
        .chunk = ctx.chunk,
        .chunk_index = ctx.chunk_index,
        .total_chunks = ctx.total_chunks,
        .running_summary = null,
    }, alloc) catch |e| {
        ctx.result.err = e;
        return;
    };
    defer user_prompt.deinit(alloc);
    defer PROMPT.ReleaseMessageArray(user_prompt, alloc);

    var messages: std.ArrayList(Message) = .empty;
    defer messages.deinit(alloc);
    messages.appendSlice(alloc, ctx.base_messages) catch |e| {
        ctx.result.err = e;
        return;
    };
    messages.appendSlice(alloc, user_prompt.items) catch |e| {
        ctx.result.err = e;
        return;
    };

    const response = ctx.lm_handler.make_request(messages, alloc, .{
        .ca_bundle = ctx.ca_bundle,
    }) catch |e| {
        ctx.result.err = e;
        return;
    };

    ctx.result.iteration_time = std.time.milliTimestamp() - iter_start;
    ctx.result.summary = std.heap.page_allocator.dupe(u8, response) catch |e| {
        ctx.result.err = e;
        return;
    };
}

// ---------------------------------------------------------------------------

/// Read chunk `index` from `env`, applying overlap when configured.
/// Caller owns the returned slice.
inline fn readChunk(
    env: *environment.EnvHandler,
    index: usize,
    chunk_size: usize,
    chunk_overlap: usize,
    allocator: std.mem.Allocator,
) ![]u8 {
    return if (chunk_overlap > 0)
        env.read_chunk_with_overlap(index, chunk_size, chunk_overlap, allocator)
    else
        env.read_chunk(index, chunk_size, allocator);
}

/// RLM orchestrator specialized for long-text question answering.
pub const RLM = struct {
    backend: []const u8 = "openai",
    /// Please provide full information of api_key, base_url, model_name in json format.
    backend_kwargs: backendKwargs,
    environment: []const u8 = "local",
    environment_kwargs: []const u8 = "{}",
    depth: u32 = 0,
    max_depth: u32 = 1,
    max_iterations: u32 = 8,
    material_chunk_size: usize = 16 * 1024,
    /// Overlap size in bytes between consecutive chunks for context preservation.
    /// Default is 0 (no overlap). Typical values: 100-500 bytes.
    chunk_overlap: usize = 0,
    custom_system_prompt: ?[]const u8 = null,
    other_backends: ?[]const u8 = null,
    other_backend_kwargs: ?[]const u8 = null,
    /// When true, all material chunks are processed concurrently using one thread
    /// per chunk. Each thread processes its chunk independently (no running-summary
    /// chain between chunks). The per-chunk summaries are combined and passed to the
    /// final synthesis step. Streaming is disabled in parallel mode.
    parallel: bool = false,
    logger: ?RLMLogger = null,
    allocator: std.mem.Allocator,

    pub fn init(self: *RLM) !void {
        if (self.logger) |*logger| {
            const metadata: RLMMetadata = .{
                .root_model = self.backend_kwargs.model_name,
                .max_depth = self.max_depth,
                .max_iterations = self.max_iterations,
                .backend = self.backend,
                .backend_kwargs = self.backend_kwargs,
                .environment_type = self.environment,
                .environment_kwargs = self.environment_kwargs,
                .other_backends = self.other_backends,
            };
            try logger.log_metadata(metadata, self.allocator);
        }
    }

    pub fn deinit(self: *RLM) void {
        if (self.logger) |*logger| {
            logger.deinit(self.allocator);
        }
        self.* = undefined;
    }

    fn computeChunkSize(self: *const RLM, material_len: usize) usize {
        const configured = @max(self.material_chunk_size, 1);
        if (self.max_iterations == 0 or material_len == 0) return configured;

        const min_chunk_size = std.math.divCeil(usize, material_len, self.max_iterations) catch unreachable;
        return @max(configured, min_chunk_size);
    }

    /// Reads material from the given path. `self` is intentionally unused for now,
    /// but is kept to allow future use of instance configuration and to maintain
    /// a consistent internal method signature within `RLM`.
    fn readMaterialFromPath(self: *const RLM, material_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
        _ = self;

        var file = try std.fs.cwd().openFile(material_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const max_size: u64 = std.math.maxInt(usize);
        if (file_size > max_size) return error.FileTooBig;
        return try file.readToEndAlloc(allocator, @intCast(file_size));
    }

    fn setup_prompt(self: *RLM, material: []const u8, chunk_size: usize, allocator: std.mem.Allocator) !std.ArrayList(Message) {
        var metadata: QueryMetadata = try QueryMetadata.initChunked(material, chunk_size, allocator);
        defer metadata.deinit(allocator);

        var system_messages = try PROMPT.buildSystemPrompt(self.custom_system_prompt, metadata, allocator);
        defer system_messages.deinit(allocator);

        var message_history: std.ArrayList(Message) = .empty;
        try message_history.appendSlice(allocator, system_messages.items);
        return message_history;
    }

    fn fallback_answer(self: *RLM, root_prompt: []const u8, material: []const u8, lm_handler: ModelHandler, allocator: std.mem.Allocator) !RLMChatCompletion {
        _ = self;
        const timestart = std.time.milliTimestamp();

        var simple_message: std.ArrayList(Message) = .empty;
        defer simple_message.deinit(allocator);

        const user_content = try std.fmt.allocPrint(
            allocator,
            "Root question:\n{s}\n\nMaterial:\n{s}\n\nAnswer the root question using only the material. Follow the format requested in the root question. If the root question asks for code, return code only unless it explicitly requests explanation.",
            .{ root_prompt, material },
        );
        defer allocator.free(user_content);

        try simple_message.append(allocator, Message{ .role = "user", .content = user_content });

        const response = try lm_handler.make_request(simple_message, allocator, .{});
        const timeend = std.time.milliTimestamp();

        return RLMChatCompletion{
            .root_model = lm_handler.model_name,
            .prompt = root_prompt,
            .response = response,
            .execution_time = timeend - timestart,
        };
    }

    fn finalize_answer(self: *RLM, root_prompt: []const u8, running_summary: []const u8, base_messages: std.ArrayList(Message), lm_handler: ModelHandler, allocator: std.mem.Allocator) !RLMChatCompletion {
        _ = self;
        const timestart = std.time.milliTimestamp();

        var final_prompt = try PROMPT.buildFinalPrompt(root_prompt, running_summary, allocator);
        defer final_prompt.deinit(allocator);
        defer PROMPT.ReleaseMessageArray(final_prompt, allocator);

        var complete_messages: std.ArrayList(Message) = .empty;
        defer complete_messages.deinit(allocator);
        try complete_messages.appendSlice(allocator, base_messages.items);
        try complete_messages.appendSlice(allocator, final_prompt.items);

        const response = try lm_handler.make_request(complete_messages, allocator, .{});
        const timeend = std.time.milliTimestamp();

        return RLMChatCompletion{
            .root_model = lm_handler.model_name,
            .prompt = root_prompt,
            .response = response,
            .execution_time = timeend - timestart,
        };
    }

    /// Execute a long-text completion using a material file path.
    pub fn completion(self: *RLM, root_prompt: []const u8, material_path: []const u8) !RLMChatCompletion {
        const allocator = self.allocator;
        const timestart = std.time.milliTimestamp();
        const material = try self.readMaterialFromPath(material_path, allocator);
        defer allocator.free(material);

        var env: environment.EnvHandler = undefined;
        const env_type = std.meta.stringToEnum(environment.env_type, self.environment) orelse environment.env_type.local;
        try env.init(env_type, self.environment_kwargs, material, allocator);
        defer env.deinit(allocator) catch {};

        const lm_handler = ModelHandler{
            .api_key = self.backend_kwargs.api_key,
            .base_url = self.backend_kwargs.base_url,
            .model_name = self.backend_kwargs.model_name,
        };

        if (self.depth >= self.max_depth) {
            const fallback_result = try self.fallback_answer(root_prompt, material, lm_handler, allocator);
            if (self.logger) |*logger| {
                try logger.log_completion(fallback_result, allocator);
            }
            return fallback_result;
        }

        const chunk_size = self.computeChunkSize(material.len);
        const total_chunks = env.count_chunks(chunk_size);

        var base_messages = try self.setup_prompt(material, chunk_size, allocator);
        defer base_messages.deinit(allocator);
        defer PROMPT.ReleaseMessageArray(base_messages, allocator);

        // In sequential mode the initial value seeds the first chunk's context.
        // In parallel mode it is immediately replaced, so we skip the copy.
        var running_summary: []u8 = if (!self.parallel)
            try allocator.dupe(u8, "No evidence processed yet.")
        else
            try allocator.alloc(u8, 0);
        defer allocator.free(running_summary);

        // Set overlap size on environment if enabled
        if (self.chunk_overlap > 0) {
            env.set_overlap(self.chunk_overlap);
        }

        if (self.parallel) {
            // ---------------------------------------------------------------
            // Parallel path: all chunks are processed concurrently.
            // Each worker thread handles one chunk independently (no running-
            // summary chain). Results are collected in order and combined into
            // a single summary for the final synthesis step.
            // ---------------------------------------------------------------

            // 0. Pre-load CA certificates on the main thread.
            //    On macOS the Security-framework APIs used for this scan must
            //    be called from the main (or an AppKit-friendly) thread, so we
            //    do it once here and share the read-only result with workers.
            var shared_bundle: std.crypto.Certificate.Bundle = .{};
            try shared_bundle.rescan(std.heap.page_allocator);
            defer shared_bundle.deinit(std.heap.page_allocator);

            // 1. Pre-read all chunks (must be done before threads start so we
            //    can pass stable slices to each worker).
            const all_chunks = try allocator.alloc([]u8, total_chunks);
            defer {
                for (all_chunks) |c| allocator.free(c);
                allocator.free(all_chunks);
            }
            for (0..total_chunks) |i| {
                all_chunks[i] = try readChunk(&env, i, chunk_size, self.chunk_overlap, allocator);
            }

            // 2. Allocate per-worker result slots and thread contexts.
            const worker_results = try allocator.alloc(ChunkWorkerResult, total_chunks);
            defer allocator.free(worker_results);
            @memset(worker_results, .{});
            defer {
                for (worker_results) |*r| {
                    if (r.summary) |s| std.heap.page_allocator.free(s);
                }
            }

            const ctxs = try allocator.alloc(ChunkWorkerCtx, total_chunks);
            defer allocator.free(ctxs);
            for (0..total_chunks) |i| {
                ctxs[i] = .{
                    .root_prompt = root_prompt,
                    .chunk = all_chunks[i],
                    .chunk_index = @intCast(i),
                    .total_chunks = @intCast(total_chunks),
                    .base_messages = base_messages.items,
                    .lm_handler = lm_handler,
                    .ca_bundle = &shared_bundle,
                    .result = &worker_results[i],
                };
            }

            // 3. Spawn one thread per chunk then join all.
            std.debug.print("\n[Parallel] Launching {d} chunk workers...\n", .{total_chunks});
            const threads = try allocator.alloc(std.Thread, total_chunks);
            defer allocator.free(threads);
            for (0..total_chunks) |i| {
                threads[i] = try std.Thread.spawn(.{}, chunkWorker, .{ctxs[i]});
            }
            for (threads) |t| t.join();

            // 4. Check errors, log iterations and print diagnostics in one pass.
            for (worker_results, 0..) |r, i| {
                if (r.err) |e| {
                    std.debug.print("[Parallel] Chunk {d} failed: {}\n", .{ i, e });
                    return e;
                }
                const summary = r.summary orelse "";
                const iteration = RLMIteration{
                    .prompt = base_messages,
                    .response = summary,
                    .chunk_index = @intCast(i),
                    .total_chunks = @intCast(total_chunks),
                    .chunk_length = @intCast(all_chunks[i].len),
                    .running_summary = summary,
                    .iteration_time = r.iteration_time,
                };
                if (self.logger) |*logger| {
                    try logger.log_iteration(iteration, allocator);
                }
                std.debug.print("\n========== CHUNK {d}/{d} ==========\n", .{ i + 1, total_chunks });
                std.debug.print("Execution Time: {d}ms\n", .{r.iteration_time});
                std.debug.print("Summary length: {d}\n", .{summary.len});
                std.debug.print("===============================\n\n", .{});
            }

            // 6. Build combined running summary (chunk summaries joined in order).
            var combined: std.ArrayList(u8) = .empty;
            defer combined.deinit(allocator);
            for (worker_results, 0..) |r, i| {
                const s = r.summary orelse "";
                const piece = try std.fmt.allocPrint(allocator, "=== Chunk {d}/{d} ===\n{s}\n\n", .{ i + 1, total_chunks, s });
                defer allocator.free(piece);
                try combined.appendSlice(allocator, piece);
            }
            allocator.free(running_summary);
            running_summary = try combined.toOwnedSlice(allocator);
        } else {
            // ---------------------------------------------------------------
            // Sequential path: chunks are processed one by one, each receiving
            // the running summary accumulated from all previous chunks.
            // ---------------------------------------------------------------
            for (0..total_chunks) |chunk_index| {
                const chunk = try readChunk(&env, chunk_index, chunk_size, self.chunk_overlap, allocator);
                defer allocator.free(chunk);

                var user_prompt = try PROMPT.buildUserPrompt(.{
                    .root_prompt = root_prompt,
                    .chunk = chunk,
                    .chunk_index = @intCast(chunk_index),
                    .total_chunks = @intCast(total_chunks),
                    .running_summary = running_summary,
                }, allocator);
                defer user_prompt.deinit(allocator);
                defer PROMPT.ReleaseMessageArray(user_prompt, allocator);

                var current_prompt: std.ArrayList(Message) = .empty;
                defer current_prompt.deinit(allocator);
                try current_prompt.appendSlice(allocator, base_messages.items);
                try current_prompt.appendSlice(allocator, user_prompt.items);

                std.debug.print("\n========== CHUNK {d}/{d} ==========\n", .{ chunk_index + 1, total_chunks });
                if (self.chunk_overlap > 0) {
                    std.debug.print("[Overlap: {d} bytes]\n", .{self.chunk_overlap});
                }

                const iteration = try self.completion_turn(
                    current_prompt,
                    lm_handler,
                    @intCast(chunk_index),
                    @intCast(total_chunks),
                    @intCast(chunk.len),
                    allocator,
                );
                defer {
                    allocator.free(iteration.response);
                    allocator.free(iteration.running_summary);
                }

                if (self.logger) |*logger| {
                    try logger.log_iteration(iteration, allocator);
                }

                allocator.free(running_summary);
                running_summary = try allocator.dupe(u8, iteration.running_summary);

                std.debug.print("Execution Time: {d}ms\n", .{iteration.iteration_time});
                std.debug.print("Running summary length: {d}\n", .{running_summary.len});
                std.debug.print("===============================\n\n", .{});
            }
        }

        var result = try self.finalize_answer(root_prompt, running_summary, base_messages, lm_handler, allocator);
        result.execution_time = std.time.milliTimestamp() - timestart;
        if (self.logger) |*logger| {
            try logger.log_completion(result, allocator);
        }
        return result;
    }

    fn completion_turn(
        self: *RLM,
        prompt: std.ArrayList(Message),
        lm_handler: ModelHandler,
        chunk_index: u32,
        total_chunks: u32,
        chunk_length: u32,
        allocator: std.mem.Allocator,
    ) !RLMIteration {
        _ = self;
        const iter_start = std.time.milliTimestamp();

        const response = try lm_handler.make_request(prompt, allocator, .{
            .stream = true,
            .enable_thinking = false,
        });

        const iter_time = std.time.milliTimestamp() - iter_start;
        return RLMIteration{
            .prompt = prompt,
            .response = response,
            .chunk_index = chunk_index,
            .total_chunks = total_chunks,
            .chunk_length = chunk_length,
            .running_summary = try allocator.dupe(u8, response),
            .iteration_time = iter_time,
        };
    }
};
