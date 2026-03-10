const std = @import("std");
const Client = std.http.Client;
const Request = Client.Request;
const Message = @import("types.zig").Message;

/// Handler for LLM API requests
///
/// Manages HTTP communication with OpenAI-compatible API endpoints.
/// Currently supports standard chat completions endpoints.
///
/// ## Fields
/// - `base_url`: Full URL for the chat completions endpoint
/// - `api_key`: API key for authentication
/// - `model_name`: Name of the model to use
///
/// ## Example
/// ```zig
/// const handler = ModelHandler{
///     .base_url = "https://api.openai.com/v1/chat/completions",
///     .api_key = "sk-...",
///     .model_name = "gpt-4",
/// };
/// const response = try handler.make_request(messages, allocator);
/// ```
// TODO only support openai backend for now, we will add more backend support in the future
pub const ModelHandler = struct {
    base_url: []const u8 = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
    api_key: []const u8 = "",
    model_name: []const u8 = "qwen-plus",

    /// Make an API request to the LLM endpoint
    ///
    /// Sends a chat completion request with the provided messages and returns
    /// the model's response text.
    ///
    /// ## Parameters
    /// - `messages`: Array of Message structs representing the conversation
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// The response content string (caller owns memory)
    ///
    /// ## Errors
    /// Returns error if:
    /// - HTTP request fails
    /// - Response parsing fails
    /// - Expected fields are missing from response
    pub fn make_request(self: @This(), messages: []Message, allocator: std.mem.Allocator) ![]u8 {
        const url = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{self.base_url});
        defer allocator.free(url);
        const endpoint = try std.Uri.parse(url);
        var client: Client = .{ .allocator = allocator };
        defer client.deinit();

        const headers: Request.Headers = .{
            .accept_encoding = .{ .override = "identity" },
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = self.api_key },
        };
        var request: Request = try client.request(.POST, endpoint, .{ .headers = headers });
        defer request.deinit();

        const str_formatter = std.json.fmt(.{ .model = self.model_name, .messages = messages }, .{});
        const to_be_post = try std.fmt.allocPrint(allocator, "{f}", .{str_formatter});
        defer allocator.free(to_be_post);

        _ = try request.sendBodyComplete(to_be_post);
        var redirect_buffer: [1024]u8 = undefined;
        var response = try request.receiveHead(&redirect_buffer);

        const reader = response.reader(&.{});

        const text = try reader.allocRemaining(allocator, .unlimited);
        defer allocator.free(text);
        const parsed: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
        defer parsed.deinit();

        const response_text = parsed.value.object.get("choices").?.array.items[0].object.get("message").?.object.get("content").?;
        const response_text_str = try allocator.dupe(u8, response_text.string);
        return response_text_str;
    }
};

test "ModelHandler_make_request" {
    const allocator = std.testing.allocator;
    //if you need to test model request, please provide valid api_key
    const api_key = std.process.getEnvVarOwned(allocator, "DASHSCOPE_API_KEY") catch {
        return error.SkipZigTest;
    };
    defer allocator.free(api_key);
    var model_handler = ModelHandler{ .base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", .api_key = api_key, .model_name = "qwen-plus" };
    const to_be_post_messages = try allocator.alloc(Message, 1);
    defer allocator.free(to_be_post_messages);
    to_be_post_messages[0] = Message{
        .role = "user",
        .content = "你好",
    };

    const result = try model_handler.make_request(to_be_post_messages, allocator);
    defer allocator.free(result);
    std.debug.print("\nModel response:\n{s}\n", .{result});
}

test "api key" {
    const allocator = std.testing.allocator;
    const api_key = std.process.getEnvVarOwned(allocator, "DASHSCOPE_API_KEY") catch {
        std.debug.print("\nEnvironment variable DASHSCOPE_API_KEY is not set.\n", .{});
        return error.MissingApiKey;
    };
    defer allocator.free(api_key);
}
