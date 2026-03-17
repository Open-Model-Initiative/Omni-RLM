const std = @import("std");
const Client = std.http.Client;
const Request = Client.Request;
const config_env = @import("config_env.zig");
const Message = @import("types.zig").Message;

/// HTTP client wrapper for OpenAI-compatible chat completion APIs.
///
/// `ModelHandler` builds a JSON request body from message history, sends it to
/// the configured endpoint, and returns only the assistant answer content.
///
/// Notes:
/// - `base_url` can be either a base API URL or a full `/chat/completions` URL.
/// - `api_key` supports both raw token and `Bearer ...` format.
pub const ModelHandler = struct {
    base_url: []const u8 = "",
    api_key: []const u8 = "",
    model_name: []const u8 = "",

    /// Runtime options for a single chat completion request.
    ///
    /// - `stream`: Enables SSE stream parsing (`data: ...` lines).
    /// - `enable_thinking`: Prints `reasoning_content` when backend provides it.
    pub const RequestConfig = struct {
        stream: bool = false,
        enable_thinking: bool = false,
    };

    const StreamState = struct {
        printed_thinking_header: bool = false,
        printed_answer_header: bool = false,
        received_answer: bool = false,
    };

    const ChatCompletionPayload = struct {
        model: []const u8,
        messages: []const Message,
        stream: bool,
        enable_thinking: bool,
    };

    fn printAll(text: []const u8) !void {
        const cwd = std.fs.cwd();
        try cwd.makePath("logs");

        var log_file = try cwd.createFile("logs/model_stream_output.log", .{ .truncate = false });
        defer log_file.close();

        try log_file.seekFromEnd(0);
        try log_file.writeAll(text);
    }

    fn printThinkingHeader(state: *StreamState) !void {
        if (state.printed_thinking_header) return;
        try printAll("\n[thinking]\n");
        state.printed_thinking_header = true;
    }

    fn printAnswerHeader(state: *StreamState) !void {
        if (state.printed_answer_header) return;
        if (state.printed_thinking_header) {
            try printAll("\n[answer]\n");
        }
        state.printed_answer_header = true;
    }

    fn resolveEndpoint(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        if (std.mem.endsWith(u8, self.base_url, "/chat/completions")) {
            return allocator.dupe(u8, self.base_url);
        }
        return std.fmt.allocPrint(allocator, "{s}/chat/completions", .{self.base_url});
    }

    fn resolveAuthorization(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        if (std.mem.startsWith(u8, self.api_key, "Bearer ")) {
            return allocator.dupe(u8, self.api_key);
        }
        return std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
    }

    fn appendReasoningDelta(delta_object: std.json.ObjectMap, state: *StreamState, enable_thinking: bool) !void {
        if (!enable_thinking) return;
        if (delta_object.get("reasoning_content")) |reasoning_content| {
            if (reasoning_content == .string and reasoning_content.string.len > 0) {
                try printThinkingHeader(state);
                try printAll(reasoning_content.string);
            }
        }
    }

    fn appendContentDelta(
        allocator: std.mem.Allocator,
        delta_object: std.json.ObjectMap,
        state: *StreamState,
        output: *std.ArrayList(u8),
    ) !void {
        if (delta_object.get("content")) |content| {
            if (content == .string and content.string.len > 0) {
                try printAnswerHeader(state);
                try printAll(content.string);
                try output.appendSlice(allocator, content.string);
                state.received_answer = true;
            }
        }
    }

    fn handleStreamLine(
        allocator: std.mem.Allocator,
        line: []const u8,
        output: *std.ArrayList(u8),
        state: *StreamState,
        enable_thinking: bool,
    ) !bool {
        const trimmed = std.mem.trim(u8, line, "\r\n \t");
        if (trimmed.len == 0) return false;
        if (!std.mem.startsWith(u8, trimmed, "data: ")) return false;

        const payload = trimmed[6..];
        if (std.mem.eql(u8, payload, "[DONE]")) return true;

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch {
            return false;
        };
        defer parsed.deinit();

        const choices = parsed.value.object.get("choices") orelse return false;
        if (choices != .array or choices.array.items.len == 0) return false;

        const first_choice = choices.array.items[0];
        if (first_choice != .object) return false;

        const delta = first_choice.object.get("delta") orelse return false;
        if (delta != .object) return false;

        try appendReasoningDelta(delta.object, state, enable_thinking);
        try appendContentDelta(allocator, delta.object, state, output);

        return false;
    }

    fn readStreamResponse(response: *Client.Response, allocator: std.mem.Allocator, enable_thinking: bool) ![]u8 {
        var transfer_buffer: [128]u8 = undefined;
        const reader = response.reader(&transfer_buffer);

        var output: std.ArrayList(u8) = .empty;
        errdefer output.deinit(allocator);

        var pending: std.ArrayList(u8) = .empty;
        defer pending.deinit(allocator);

        var state = StreamState{};
        var chunk_buffer: [4096]u8 = undefined;
        var vecs = [_][]u8{chunk_buffer[0..]};
        var done = false;

        while (!done) {
            const bytes_read = reader.readVec(&vecs) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |read_err| return read_err,
            };
            if (bytes_read == 0) continue;

            try pending.appendSlice(allocator, chunk_buffer[0..bytes_read]);

            while (std.mem.indexOfScalar(u8, pending.items, '\n')) |line_end| {
                const line = pending.items[0..line_end];
                done = try handleStreamLine(allocator, line, &output, &state, enable_thinking);

                const remaining = pending.items[line_end + 1 ..];
                std.mem.copyForwards(u8, pending.items, remaining);
                pending.items.len = remaining.len;

                if (done) break;
            }
        }

        if (!done and pending.items.len > 0) {
            _ = try handleStreamLine(allocator, pending.items, &output, &state, enable_thinking);
        }

        if (state.received_answer or state.printed_thinking_header) {
            try printAll("\n");
        }

        return output.toOwnedSlice(allocator);
    }

    fn readNonStreamResponse(response: *Client.Response, allocator: std.mem.Allocator, config: RequestConfig) ![]u8 {
        const reader = response.reader(&.{});
        const text = try reader.allocRemaining(allocator, .unlimited);
        defer allocator.free(text);

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
        defer parsed.deinit();

        const choices = parsed.value.object.get("choices") orelse return error.InvalidResponse;
        if (choices != .array or choices.array.items.len == 0) return error.InvalidResponse;

        const first_choice = choices.array.items[0];
        if (first_choice != .object) return error.InvalidResponse;

        const message = first_choice.object.get("message") orelse return error.InvalidResponse;
        if (message != .object) return error.InvalidResponse;

        if (config.enable_thinking) {
            if (message.object.get("reasoning_content")) |reasoning| {
                if (reasoning == .string and reasoning.string.len > 0) {
                    try printAll("[thinking]\n");
                    try printAll(reasoning.string);
                    try printAll("\n[answer]\n");
                }
            }
        }

        const content = message.object.get("content") orelse return error.InvalidResponse;
        if (content != .string) return error.InvalidResponse;

        try printAll(content.string);
        try printAll("\n");

        return allocator.dupe(u8, content.string);
    }

    /// Sends a chat completion request and returns model answer text.
    ///
    /// Parameters:
    /// - `messages`: Conversation history packed in `std.ArrayList(Message)`.
    /// - `allocator`: Allocator used for request/response buffers.
    /// - `config`: Per-request behavior switches (streaming/thinking output).
    ///
    /// Returns:
    /// - Owned `[]u8` answer content; caller must free it.
    ///
    /// Errors:
    /// - `error.HttpRequestFailed` when HTTP status is not success.
    /// - `error.InvalidResponse` when non-stream JSON shape is invalid.
    /// - Propagates allocator/network/JSON parsing errors.
    pub fn make_request(
        self: @This(),
        messages: std.ArrayList(Message),
        allocator: std.mem.Allocator,
        config: RequestConfig,
    ) ![]u8 {
        const endpoint_url = try self.resolveEndpoint(allocator);
        defer allocator.free(endpoint_url);

        const authorization = try self.resolveAuthorization(allocator);
        defer allocator.free(authorization);

        const endpoint = try std.Uri.parse(endpoint_url);

        var client: Client = .{ .allocator = allocator };
        defer client.deinit();

        const headers: Request.Headers = .{
            .accept_encoding = .{ .override = "identity" },
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = authorization },
        };
        var request: Request = try client.request(.POST, endpoint, .{ .headers = headers });
        defer request.deinit();

        const payload = ChatCompletionPayload{
            .model = self.model_name,
            .messages = messages.items,
            .stream = config.stream,
            .enable_thinking = config.enable_thinking,
        };
        const request_body = try std.json.Stringify.valueAlloc(allocator, payload, .{});
        defer allocator.free(request_body);

        try request.sendBodyComplete(request_body);

        var redirect_buffer: [1024]u8 = undefined;
        var response = try request.receiveHead(&redirect_buffer);

        if (response.head.status.class() != .success) {
            return error.HttpRequestFailed;
        }

        if (config.stream) {
            return readStreamResponse(&response, allocator, config.enable_thinking);
        }

        return readNonStreamResponse(&response, allocator, config);
    }
};

test "streaming content is appended and returned" {
    const allocator = std.testing.allocator;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    var state = ModelHandler.StreamState{};

    try std.testing.expectEqual(false, try ModelHandler.handleStreamLine(
        allocator,
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}",
        &output,
        &state,
        false,
    ));
    try std.testing.expectEqual(false, try ModelHandler.handleStreamLine(
        allocator,
        "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}",
        &output,
        &state,
        false,
    ));
    try std.testing.expectEqual(true, try ModelHandler.handleStreamLine(
        allocator,
        "data: [DONE]",
        &output,
        &state,
        false,
    ));
    try std.testing.expectEqualStrings("Hello", output.items);
}

test "streaming reasoning is printed but not appended" {
    const allocator = std.testing.allocator;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    var state = ModelHandler.StreamState{};

    try std.testing.expectEqual(false, try ModelHandler.handleStreamLine(
        allocator,
        "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"Thinking...\"}}]}",
        &output,
        &state,
        true,
    ));
    try std.testing.expectEqual(false, try ModelHandler.handleStreamLine(
        allocator,
        "data: {\"choices\":[{\"delta\":{\"content\":\"Answer\"}}]}",
        &output,
        &state,
        true,
    ));

    try std.testing.expect(state.printed_thinking_header);
    try std.testing.expect(state.received_answer);
    try std.testing.expectEqualStrings("Answer", output.items);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var backend_config = try config_env.load_backend_env_config(allocator, ".env");
    defer backend_config.deinit(allocator);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const prompt = if (args.len > 1)
        args[1]
    else
        "写一个1000字的故事";

    var messages: std.ArrayList(Message) = .empty;
    defer messages.deinit(allocator);

    try messages.append(allocator, .{
        .role = "system",
        .content = "You are a concise assistant. Respond clearly and briefly.",
    });
    try messages.append(allocator, .{
        .role = "assistant",
        .content = "好的，我会直接回答，并在需要时展示思考过程。",
    });
    try messages.append(allocator, .{
        .role = "user",
        .content = prompt,
    });

    std.debug.print("Requesting model {s} at {s}\n", .{ backend_config.model_name, backend_config.base_url });

    const handler = ModelHandler{
        .base_url = backend_config.base_url,
        .api_key = backend_config.api_key,
        .model_name = backend_config.model_name,
    };

    const response = try handler.make_request(messages, allocator, .{
        .stream = true,
        .enable_thinking = false,
    });
    defer allocator.free(response);

    std.debug.print("Returned {d} bytes from the model.\n", .{response.len});
}
