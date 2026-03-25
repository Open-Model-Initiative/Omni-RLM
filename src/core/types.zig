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

    /// Initialize QueryMetadata for chunked long-form material.
    pub fn initChunked(material: []const u8, chunk_size: usize, allocator: std.mem.Allocator) !QueryMetadata {
        const safe_chunk_size = @max(chunk_size, 1);
        const chunk_count = if (material.len == 0) 1 else std.math.divCeil(usize, material.len, safe_chunk_size) catch unreachable;
        const context_length = try allocator.alloc(u32, chunk_count);

        var offset: usize = 0;
        for (0..chunk_count) |index| {
            const remaining = material.len -| offset;
            const current_chunk_len = if (remaining == 0) 0 else @min(safe_chunk_size, remaining);
            context_length[index] = @intCast(current_chunk_len);
            offset += current_chunk_len;
        }

        return QueryMetadata{
            .context_length = context_length,
            .context_total_length = @intCast(material.len),
            .context_type = "chunked_str",
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

/// Represents a single iteration in the long-text completion loop.
///
/// Captures all information about one model request/response cycle,
/// including the prompt, updated running summary, chunk metadata, and timing.
///
/// ## Fields
/// - `prompt`: Array of messages sent to the model
/// - `response`: Raw text response from the model
/// - `chunk_index`: Index of the processed material chunk
/// - `total_chunks`: Total number of material chunks
/// - `chunk_length`: Character length of the processed chunk
/// - `running_summary`: Updated cumulative summary after this chunk
/// - `iteration_time`: Time taken for this iteration in milliseconds
///
/// ## Example
/// ```zig
/// var iteration = RLMIteration{
///     .prompt = messages,
///     .response = response_text,
///     .chunk_index = 0,
///     .total_chunks = 8,
///     .chunk_length = 4096,
///     .running_summary = response_text,
///     .iteration_time = 1000,
/// };
/// ```
pub const RLMIteration = struct {
    prompt: std.ArrayList(Message),
    /// Incremental synthesis response from the model.
    response: []const u8,
    chunk_index: u32,
    total_chunks: u32,
    chunk_length: u32,
    running_summary: []const u8,
    iteration_time: i64,
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
