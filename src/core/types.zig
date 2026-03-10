const std = @import("std");
const json = std.json;
const Value = json.Value;

/// Backend configuration for API access
///
/// Contains all necessary parameters to connect to an OpenAI-compatible API endpoint
///
/// ## Fields
/// - `api_key`: API key for authentication (e.g., "sk-...")
/// - `base_url`: Full URL for the chat completions endpoint
/// - `model_name`: Name of the model to use (e.g., "gpt-4", "qwen-plus")
pub const backendKwargs = struct {
    api_key: []const u8,
    base_url: []const u8,
    model_name: []const u8,
    pub fn deinit(self: *backendKwargs, allocator: std.mem.Allocator) void {
        allocator.free(self.api_key);
        allocator.free(self.base_url);
        allocator.free(self.model_name);
        self.* = undefined;
    }
};

/// Metadata for RLM execution session
///
/// Captures configuration and settings for logging and debugging purposes
///
/// ## Fields
/// - `root_model`: Primary model name used for completions
/// - `max_depth`: Maximum recursion depth allowed
/// - `max_iterations`: Maximum iterations per completion
/// - `backend`: Backend type identifier
/// - `backend_kwargs`: API configuration
/// - `environment_type`: Execution environment type
/// - `environment_kwargs`: Environment-specific configuration as JSON string
/// - `other_backends`: Optional additional backend configurations
pub const RLMMetadata = struct {
    root_model: []const u8,
    max_depth: u32 = 1,
    max_iterations: u32 = 10,
    backend: []const u8 = "openai",
    backend_kwargs: backendKwargs,
    environment_type: ?[]const u8 = null,
    environment_kwargs: []const u8 = "{}",
    other_backends: ?[]const u8 = null,
};

/// Query metadata for tracking context information
///
/// Tracks the size and type of context being processed
///
/// ## Fields
/// - `context_length`: Array of chunk lengths for each context segment
/// - `context_total_length`: Total length of all context combined
/// - `context_type`: Type identifier for the context (e.g., "str")
///
/// ## Example
/// ```zig
/// var metadata = QueryMetadata.init("Hello, world!", allocator);
/// defer metadata.deinit(allocator);
/// ```
pub const QueryMetadata = struct {
    context_length: []const u32,
    context_total_length: u32,
    context_type: []const u8,

    /// Initialize QueryMetadata from a prompt string
    ///
    /// ## Parameters
    /// - `prompt`: The prompt/context string to analyze
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// New QueryMetadata with calculated lengths
    pub fn init(prompt: []const u8, allocator: std.mem.Allocator) QueryMetadata {
        const context_length = allocator.alloc(u32, 1) catch unreachable;
        context_length[0] = @as(u32, @intCast(prompt.len));
        return QueryMetadata{
            .context_length = context_length,
            .context_total_length = context_length[0],
            .context_type = "str",
        };
    }

    /// Deinitialize QueryMetadata
    ///
    /// Frees allocated memory for context lengths
    ///
    /// ## Parameters
    /// - `allocator`: Memory allocator used for allocation
    pub fn deinit(self: *QueryMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.context_length);
        self.* = undefined;
    }
};

/// Represents a single iteration in the RLM completion loop
///
/// Captures all information about one model request/response cycle,
/// including the prompt, response, executed code blocks, and timing
///
/// ## Fields
/// - `prompt`: Array of messages sent to the model
/// - `response`: Raw text response from the model
/// - `code_blocks`: Array of code blocks extracted and executed
/// - `final_answer`: Optional final answer if found in this iteration
/// - `iteration_time`: Time taken for this iteration in milliseconds
///
/// ## Example
/// ```zig
/// var iteration = RLMIteration{
///     .prompt = messages,
///     .response = response_text,
///     .code_blocks = code_blocks,
///     .iteration_time = 1000,
/// };
/// ```
pub const RLMIteration = struct {
    prompt: std.ArrayList(Message),
    ///repl like response from LM
    response: []const u8,
    code_blocks: []CodeBlock,
    final_answer: ?[]const u8 = null,
    iteration_time: i64,

    /// Format iteration results as messages for the next turn
    ///
    /// Converts the model response and code execution results into
    /// a message array suitable for appending to conversation history
    ///
    /// ## Parameters
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// ArrayList of Message structs representing this iteration
    pub fn format_iteration(self: *RLMIteration, allocator: std.mem.Allocator) !std.ArrayList(Message) {
        var messages: std.ArrayList(Message) = .empty;
        try messages.append(allocator, Message{
            .role = "assistant",
            .content = try allocator.dupe(u8, self.response),
        });
        for (0..self.code_blocks.len) |index| {
            const code = self.code_blocks[index].code;
            const result = try std.fmt.allocPrint(
                allocator,
                "STDOUT:\n{s}\n\nSTDERR:\n{s}\n\n",
                .{ self.code_blocks[index].result.stdout, self.code_blocks[index].result.stderr },
            );
            defer allocator.free(result);
            try messages.append(allocator, Message{
                .role = "user",
                .content = try std.fmt.allocPrint(allocator, "Code executed:\n```python\n{s}\n```\nREPL output::\n{s}", .{ code, result }),
            });
        }
        return messages;
    }
};

/// Result of an RLM chat completion
///
/// Contains the final response and metadata about the completion
///
/// ## Fields
/// - `root_model`: Model name that generated the response
/// - `prompt`: Original user prompt
/// - `response`: Final answer text
/// - `execution_time`: Total time for completion in milliseconds
pub const RLMChatCompletion = struct {
    root_model: []const u8,
    prompt: []const u8,
    response: []const u8,
    // usage_sumary: []const u8,//TODO implement usage summary
    execution_time: i64,
};

/// A code block with its execution result
///
/// Represents a single extracted code block and the result of its execution
///
/// ## Fields
/// - `code`: The source code that was executed
/// - `result`: Process execution result containing stdout, stderr, and exit status
///
/// ## Example
/// ```zig
/// var block = CodeBlock{
///     .code = "print('hello')",
///     .result = run_result,
/// };
/// defer block.deinit(allocator);
/// ```
pub const CodeBlock = struct {
    code: []const u8,
    result: std.process.Child.RunResult, // TODO change the struct support locals, execution_time, rlm_calls.

    /// Deinitialize CodeBlock
    ///
    /// Frees all allocated memory for code and execution results
    ///
    /// ## Parameters
    /// - `allocator`: Memory allocator used for allocations
    pub fn deinit(self: *CodeBlock, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.result.stderr);
        allocator.free(self.result.stdout);
        self.* = undefined;
    }
};

/// A chat message for LLM APIs
///
/// Standard OpenAI-compatible message format
///
/// ## Fields
/// - `role`: Message role - "system", "user", or "assistant"
/// - `content`: Message content text
///
/// ## Example
/// ```zig
/// const msg = Message{
///     .role = "user",
///     .content = "Hello!",
/// };
/// ```
pub const Message = struct {
    role: []const u8 = "user",
    content: []const u8 = "",
};
