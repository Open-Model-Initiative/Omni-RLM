const RLMLogger = @import("rlm_logger.zig").RLMLogger;
const std = @import("std");
const backendKwargs = @import("types.zig").backendKwargs;
const PROMPT = @import("prompt.zig");
const RLMIteration = @import("types.zig").RLMIteration;
const QueryMetadata = @import("types.zig").QueryMetadata;
const RLMMetadata = @import("types.zig").RLMMetadata;
const Message = @import("types.zig").Message;
const CodeBlock = @import("types.zig").CodeBlock;
const ModelHandler = @import("Model_info.zig").ModelHandler;
const find_code_blocks = @import("parsing.zig").find_code_blocks;
const environment = @import("environment/type.zig");
const RLMChatCompletion = @import("types.zig").RLMChatCompletion;

/// RLM (Recursive Language Model) orchestrator for managing recursive LLM completions
///
/// The RLM struct manages the recursive completion loop, allowing LLMs to:
/// - Execute code in a controlled environment (local Python or Daytona sandbox)
/// - Make recursive LLM calls via the `llm_query` function
/// - Iterate until a final answer is found or limits are reached
///
/// ## Fields
/// - `backend`: Backend type (default: "openai")
/// - `backend_kwargs`: API configuration including api_key, base_url, model_name
/// - `environment`: Execution environment type - "local" or "daytona" (default: "local")
/// - `environment_kwargs`: JSON string with environment-specific configuration
/// - `depth`: Current recursion depth (automatically managed)
/// - `max_depth`: Maximum recursion depth (default: 1)
/// - `max_iterations`: Maximum iterations per completion (default: 4)
/// - `custom_system_prompt`: Optional custom system prompt to override default
/// - `other_backends`: Optional other backend configurations
/// - `other_backend_kwargs`: Optional other backend kwargs
/// - `logger`: Optional RLMLogger for structured logging
/// - `allocator`: Memory allocator for all allocations
///
/// ## Example
/// ```zig
/// var rlm: RLM = .{
///     .backend_kwargs = .{
///         .api_key = api_key,
///         .base_url = "https://api.example.com/v1/chat/completions",
///         .model_name = "gpt-4",
///     },
///     .environment = "local",
///     .environment_kwargs = "{}",
///     .max_depth = 2,
///     .max_iterations = 10,
///     .allocator = allocator,
/// };
/// try rlm.init();
/// defer rlm.deinit();
/// ```
pub const RLM = struct {
    backend: []const u8 = "openai",
    /// Please provide full information of api_key, base_url, model_name in json format
    backend_kwargs: backendKwargs,
    environment: []const u8 = "local",
    environment_kwargs: []const u8 = "{}",
    depth: u32 = 0,
    max_depth: u32 = 1,
    max_iterations: u32 = 4,
    custom_system_prompt: ?[]const u8 = null,
    other_backends: ?[]const u8 = null,
    other_backend_kwargs: ?[]const u8 = null,
    logger: ?RLMLogger = null,
    allocator: std.mem.Allocator,

    /// Initialize the RLM instance
    ///
    /// Logs metadata if a logger is configured and cleans up previous session files.
    /// This should be called before using the RLM instance.
    ///
    /// ## Errors
    /// Returns error if metadata logging fails
    pub fn init(self: *RLM) !void {
        // Initialization logic if needed
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

        // Clean up previous session file if exists
        std.fs.cwd().deleteFile("env.dill") catch {};
    }

    /// Deinitialize the RLM instance
    ///
    /// Frees resources associated with the RLM including the logger if present.
    /// This should be called when done using the RLM instance.
    pub fn deinit(self: *RLM) void {
        if (self.logger) |*logger| {
            logger.deinit(self.allocator);
        }
        self.* = undefined;
    }

    /// Set up the system prompt for the completion
    fn setup_prompt(self: *RLM, prompt: []const u8, allocator: std.mem.Allocator) !std.ArrayList(Message) {
        // Implementation for setting up the prompt
        var metadata: QueryMetadata = QueryMetadata.init(prompt, allocator);
        defer metadata.deinit(allocator);
        var system_messages = try PROMPT.buildSystemPrompt(self.custom_system_prompt, metadata, allocator);
        defer system_messages.deinit(allocator);

        var message_history: std.ArrayList(Message) = .empty;
        try message_history.appendSlice(allocator, system_messages.items);
        return message_history;
    }

    /// Fallback answer when max depth is reached
    ///
    /// Makes a simple direct request to the model without the REPL system prompt.
    fn fallback_answer(self: *RLM, prompt: []const u8, lm_handler: ModelHandler, allocator: std.mem.Allocator) !RLMChatCompletion {
        // Simple single iteration: ask and get final answer without system prompt setup
        _ = self;
        const timestart = std.time.milliTimestamp();

        // Create a simple user message with just the prompt
        var simple_message: std.ArrayList(Message) = .empty;
        defer simple_message.deinit(allocator);
        try simple_message.append(allocator, Message{ .role = "user", .content = prompt });

        // Make a direct request to the model
        const response = try lm_handler.make_request(simple_message, allocator, .{});
        defer allocator.free(response);

        const timeend = std.time.milliTimestamp();

        // Return the model response directly as final answer
        const final_response = try allocator.dupe(u8, response);
        return RLMChatCompletion{
            .root_model = lm_handler.model_name,
            .prompt = prompt,
            .response = final_response,
            .execution_time = timeend - timestart,
        };
    }

    /// Default answer when max iterations reached without finding a final answer
    fn default_answer(self: *RLM, prompt: []const u8, message_history: std.ArrayList(Message), lm_handler: ModelHandler, allocator: std.mem.Allocator) !RLMChatCompletion {
        _ = self;
        // Generate a final answer when max iterations reached without finding a final answer
        const timestart = std.time.milliTimestamp();

        // Create complete messages by cloning history and appending final prompt
        var complete_messages: std.ArrayList(Message) = .empty;
        defer complete_messages.deinit(allocator);
        // Copy message history
        try complete_messages.appendSlice(allocator, message_history.items);

        // Append final prompt
        try complete_messages.append(allocator, Message{
            .role = "assistant",
            .content = "Please provide a final answer to the user's question based on the information provided.",
        });

        // Make final request to get default answer
        const response = try lm_handler.make_request(complete_messages, allocator, .{});
        const timeend = std.time.milliTimestamp();

        return RLMChatCompletion{
            .root_model = lm_handler.model_name,
            .prompt = prompt,
            .response = response,
            .execution_time = timeend - timestart,
        };
    }

    /// Execute a recursive completion
    ///
    /// This is the main entry point for RLM completions. It:
    /// 1. Sets up the execution environment
    /// 2. Iteratively prompts the model
    /// 3. Executes code blocks from responses
    /// 4. Continues until a final answer is found or limits are reached
    ///
    /// ## Parameters
    /// - `prompt`: The user query/prompt
    /// - `root_prompt`: Optional original prompt for recursive calls
    ///
    /// ## Returns
    /// `RLMChatCompletion` containing the final response and metadata
    ///
    /// ## Errors
    /// Returns errors if API requests fail, environment setup fails, or memory allocation fails
    ///
    /// ## Example
    /// ```zig
    /// const result = try rlm.completion("What is 2+2?", null);
    /// defer allocator.free(result.response);
    /// std.debug.print("Answer: {s}\n", .{result.response});
    /// ```
    pub fn completion(self: *RLM, prompt: []const u8, root_prompt: ?[]const u8) !RLMChatCompletion {
        // Implementation for completion logic goes here
        const allocator = self.allocator;
        const timestart = std.time.milliTimestamp();

        //Setup environment handler
        var env: environment.EnvHandler = undefined;
        const env_type = std.meta.stringToEnum(environment.env_type, self.environment) orelse environment.env_type.local;
        try env.init(env_type, self.environment_kwargs, prompt, allocator);
        defer env.deinit(allocator) catch {};

        //Setup model handler
        const lm_handler = ModelHandler{
            .api_key = self.backend_kwargs.api_key,
            .base_url = self.backend_kwargs.base_url,
            .model_name = self.backend_kwargs.model_name,
        };

        if (self.depth >= self.max_depth) {
            return try self.fallback_answer(prompt, lm_handler, allocator);
        }

        var message_history = try self.setup_prompt(prompt, allocator);
        defer message_history.deinit(allocator);
        defer PROMPT.ReleaseMessageArray(message_history, allocator);

        for (0..self.max_iterations) |i| {
            var user_prompt = try PROMPT.buildUserPrompt(
                .{
                    .root_prompt = root_prompt,
                    .iteration = @intCast(i),
                },
                allocator,
            );
            defer user_prompt.deinit(allocator);
            defer PROMPT.ReleaseMessageArray(user_prompt, allocator);

            // Build current_prompt using ArrayList
            var current_prompt: std.ArrayList(Message) = .empty;
            defer current_prompt.deinit(allocator);

            // Append message history
            try current_prompt.appendSlice(allocator, message_history.items);

            // Append user prompt
            try current_prompt.appendSlice(allocator, user_prompt.items);

            std.debug.print("\n========== ITERATION {d} ==========\n", .{i});

            var iteration: RLMIteration = try self.completion_turn(current_prompt, lm_handler, env, allocator);
            defer {
                allocator.free(iteration.response);
                for (0..iteration.code_blocks.len) |index| {
                    iteration.code_blocks[index].deinit(allocator);
                }
                allocator.free(iteration.code_blocks);
            }

            // Print iteration summary with response
            std.debug.print("\nExecution Time: {d}ms\n", .{iteration.iteration_time});
            std.debug.print("===============================\n\n", .{});

            const final_answer = try env.find_final_answer(iteration.response, allocator);
            iteration.final_answer = final_answer;

            if (self.logger) |*logger| {
                try logger.log_iteration(iteration, allocator);
            }

            if (iteration.final_answer) |ans| {
                std.debug.print("\nFinal answer found: \n{s}\n", .{ans});
                const timeend = std.time.milliTimestamp();
                return RLMChatCompletion{
                    .root_model = lm_handler.model_name,
                    .prompt = prompt,
                    .response = ans,
                    .execution_time = timeend - timestart,
                };
            }

            var new_messages = try iteration.format_iteration(allocator);
            defer new_messages.deinit(allocator);

            // Append new messages to message_history
            try message_history.appendSlice(allocator, new_messages.items);
        }

        return try self.default_answer(prompt, message_history, lm_handler, allocator);
    }

    /// Execute a single completion turn (one model request + code execution)
    fn completion_turn(self: *RLM, prompt: std.ArrayList(Message), lm_handler: ModelHandler, env: environment.EnvHandler, allocator: std.mem.Allocator) !RLMIteration {
        _ = self; // to avoid unused variable warning
        const iter_start = std.time.milliTimestamp();
        const response = try lm_handler.make_request(prompt, allocator, .{
            .stream = true,
            .enable_thinking = false,
        });
        // TODO: only support python code execution now, need to support bash code execution as well.
        var code_block_strs = try find_code_blocks(response, allocator);
        defer code_block_strs.deinit(allocator);
        var code_blocks: std.ArrayList(CodeBlock) = .empty;
        defer code_blocks.deinit(allocator);

        for (code_block_strs.items) |code_block_str| {
            const code_result = try env.execute_code(code_block_str.code, allocator);
            try code_blocks.append(allocator, CodeBlock{
                .code = try allocator.dupe(u8, code_block_str.code),
                .result = code_result,
            });
        }

        const iter_time = std.time.milliTimestamp() - iter_start;
        return RLMIteration{
            .prompt = prompt,
            .response = response,
            .code_blocks = try code_blocks.toOwnedSlice(allocator),
            .iteration_time = iter_time,
            .final_answer = null,
        };
    }
};
