const RLMLogger = @import("rlm_logger.zig").RLMLogger;
const std = @import("std");
const PROMPT = @import("prompt.zig");
const RLMIteration = @import("types.zig").RLMIteration;
const QueryMetadata = @import("types.zig").QueryMetadata;
const RLMMetadata = @import("types.zig").RLMMetadata;
const Message = @import("types.zig").Message;
const CodeBlock = @import("types.zig").CodeBlock;
const ModelHandler = @import("Model_info.zig").ModelHandler;
const find_code_blocks = @import("parsing.zig").find_code_blocks;
const EnvHandler = @import("types.zig").EnvHandler;
const RLMChatCompletion = @import("types.zig").RLMChatCompletion;

pub const RLM = struct {
    backend: []const u8 = "openai",
    /// Please provide full information of api_key, base_url, model_name in json format
    backend_kwargs: []const u8 = "{}",
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

    pub fn init(self: *RLM) !void {
        // Initialization logic if needed
        if (self.logger != null) {
            const parsed_backend_kwargs = try std.json.parseFromSlice(std.json.Value, self.allocator, self.backend_kwargs, .{});
            defer parsed_backend_kwargs.deinit();

            const metadata: RLMMetadata = .{
                .root_model = parsed_backend_kwargs.value.object.get("model_name").?.string,
                .max_depth = self.max_depth,
                .max_iterations = self.max_iterations,
                .backend = self.backend,
                .backend_kwargs = self.backend_kwargs,
                .environment_type = self.environment,
                .environment_kwargs = self.environment_kwargs,
                .other_backends = self.other_backends,
            };
            try self.logger.?.log_metadata(metadata, self.allocator);
        }

        // Clean up previous session file if exists
        std.fs.cwd().deleteFile("env.dill") catch {};
    }

    pub fn deinit(self: *RLM) void {
        if (self.logger != null) {
            self.logger.?.deinit(self.allocator);
        }
        self.* = undefined;
    }

    fn setup_prompt(self: *RLM, prompt: []u8, allocator: std.mem.Allocator) ![]Message {
        // Implementation for setting up the prompt
        var metadata: QueryMetadata = QueryMetadata.init(prompt, allocator);
        defer metadata.deinit(allocator);
        var message_history: []Message = undefined;
        message_history = try PROMPT.buildSystemPrompt(self.custom_system_prompt, metadata, allocator);
        return message_history;
    }

    fn fallback_answer(self: *RLM, prompt: []u8, lm_handler: ModelHandler, allocator: std.mem.Allocator) !RLMChatCompletion {
        // Simple single iteration: ask and get final answer without system prompt setup
        _ = self;
        const timestart = std.time.milliTimestamp();

        // Create a simple user message with just the prompt
        var simple_message = try allocator.alloc(Message, 1);
        defer allocator.free(simple_message);
        simple_message[0] = Message{ .role = "user", .content = prompt };

        // Make a direct request to the model
        const response = try lm_handler.make_request(simple_message, allocator);
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

    fn default_answer(self: *RLM, prompt: []u8, message_history: []Message, lm_handler: ModelHandler, allocator: std.mem.Allocator) !RLMChatCompletion {
        _ = self;
        // Generate a final answer when max iterations reached without finding a final answer
        const timestart = std.time.milliTimestamp();

        // Create a final prompt asking for a summary/answer based on the conversation
        var final_prompt_message = try allocator.alloc(Message, 1);
        defer allocator.free(final_prompt_message);
        final_prompt_message[0] = Message{
            .role = "user",
            .content = "Please provide a final answer to the user's question based on the information provided.",
        };

        // Combine message history with final prompt
        var complete_messages = try allocator.alloc(Message, message_history.len + final_prompt_message.len);
        defer allocator.free(complete_messages);

        for (message_history, 0..) |msg, idx| {
            complete_messages[idx] = msg;
        }
        for (final_prompt_message, 0..) |msg, idx| {
            complete_messages[message_history.len + idx] = msg;
        }

        // Make final request to get default answer
        const response = try lm_handler.make_request(complete_messages, allocator);
        defer allocator.free(response);

        const timeend = std.time.milliTimestamp();

        const final_response = try allocator.dupe(u8, response);
        return RLMChatCompletion{
            .root_model = lm_handler.model_name,
            .prompt = prompt,
            .response = final_response,
            .execution_time = timeend - timestart,
        };
    }

    pub fn completion(self: *RLM, prompt: []u8, root_prompt: ?[]u8) !RLMChatCompletion {
        // Implementation for completion logic goes here
        const allocator = self.allocator;
        const timestart = std.time.milliTimestamp();

        //Setup environment handler
        const env: EnvHandler = .{ .mainfunc = "python_script/env_init.py", .context = prompt };
        defer {
            // Clean up environment if needed
            std.fs.cwd().deleteFile("env.dill") catch {};
        }

        //Setup model handler
        const processed_backend_kwargs: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(std.json.Value, allocator, self.backend_kwargs, .{});
        defer processed_backend_kwargs.deinit();
        const lm_handler = ModelHandler{
            .api_key = processed_backend_kwargs.value.object.get("api_key").?.string,
            .base_url = processed_backend_kwargs.value.object.get("base_url").?.string,
            .model_name = processed_backend_kwargs.value.object.get("model_name").?.string,
        };

        if (self.depth >= self.max_depth) {
            return try self.fallback_answer(prompt, lm_handler, allocator);
        }

        var message_history: []Message = try self.setup_prompt(prompt, allocator);
        defer {
            PROMPT.ReleaseMessageArray(message_history, allocator);
        }
        var current_prompt: []Message = try allocator.alloc(Message, 1);
        defer allocator.free(current_prompt);

        for (0..self.max_iterations) |i| {
            const user_prompt = try PROMPT.buildUserPrompt(root_prompt, @intCast(i), allocator);

            defer PROMPT.ReleaseMessageArray(user_prompt, allocator);
            current_prompt = try allocator.realloc(current_prompt, message_history.len + user_prompt.len);
            for (message_history, 0..) |msg, idx| {
                current_prompt[idx] = msg;
            }
            for (user_prompt, 0..) |msg, idx| {
                current_prompt[message_history.len + idx] = msg;
            }

            var iteration: RLMIteration = try self.completion_turn(current_prompt, lm_handler, env, allocator);
            defer {
                allocator.free(iteration.response);
                iteration.code_blocks.deinit(allocator);
            }

            // Print iteration summary with response
            std.debug.print("\n========== ITERATION {d} ==========\n", .{i});
            std.debug.print("Response:\n{s}\n", .{iteration.response});
            std.debug.print("Execution Time: {d}ms\n", .{iteration.iteration_time});
            std.debug.print("===============================\n\n", .{});

            try iteration.find_final_answer(allocator);

            if (self.logger != null) {
                try self.logger.?.log_iteration(iteration, allocator);
            }

            if (iteration.final_answer != null) {
                std.debug.print("\nFinal answer found: \n{s}\n", .{iteration.final_answer.?});
                const timeend = std.time.milliTimestamp();
                return RLMChatCompletion{
                    .root_model = lm_handler.model_name,
                    .prompt = prompt,
                    .response = iteration.final_answer.?,
                    .execution_time = timeend - timestart,
                };
            }

            const new_messages = try iteration.format_iteration(allocator);
            defer allocator.free(new_messages);
            message_history = try allocator.realloc(message_history, message_history.len + new_messages.len);
            for (new_messages, 0..) |msg, idx| {
                message_history[message_history.len - new_messages.len + idx] = msg;
            }
        }

        return try self.default_answer(prompt, message_history, lm_handler, allocator);
    }

    fn completion_turn(self: *RLM, prompt: []Message, lm_handler: ModelHandler, env: EnvHandler, allocator: std.mem.Allocator) !RLMIteration {
        _ = self; // to avoid unused variable warning
        const iter_start = std.time.milliTimestamp();
        const response = try lm_handler.make_request(prompt, allocator); //TODO find out what is the difference between @This() and *T
        const code_block_str = try find_code_blocks(response, allocator);

        const code_result = try env.execute_code(code_block_str, allocator);

        const code_blocks: CodeBlock = .{
            .code = code_block_str,
            .result = code_result,
        };
        const iter_time = std.time.milliTimestamp() - iter_start;
        return RLMIteration{
            .prompt = prompt,
            .response = response,
            .code_blocks = code_blocks,
            .iteration_time = iter_time,
            .final_answer = null,
        };
    }
};
