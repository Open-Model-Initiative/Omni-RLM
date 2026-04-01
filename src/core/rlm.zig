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

        var running_summary = try allocator.dupe(u8, "No evidence processed yet.");
        defer allocator.free(running_summary);

        // Set overlap size on environment if enabled
        if (self.chunk_overlap > 0) {
            env.set_overlap(self.chunk_overlap);
        }

        for (0..total_chunks) |chunk_index| {
            // Use overlap-aware chunk reading if overlap is enabled
            const chunk = if (self.chunk_overlap > 0)
                try env.read_chunk_with_overlap(chunk_index, chunk_size, self.chunk_overlap, allocator)
            else
                try env.read_chunk(chunk_index, chunk_size, allocator);
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
