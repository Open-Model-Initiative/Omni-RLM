const std = @import("std");
const Client = std.http.Client;
const Request = Client.Request;
const Message = @import("types.zig").Message;

pub const ModelHandler = struct {
    base_url: []const u8 = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
    api_key: []const u8 = "",
    model_name: []const u8 = "qwen-plus",

    pub fn make_request(self: @This(), messages: []Message, allocator: std.mem.Allocator) ![]u8 {
        const endpoint = try std.Uri.parse(self.base_url);
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

    var model_handler = ModelHandler{ .base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", .api_key = "", .model_name = "qwen-plus" };
    const to_be_post_messages = try allocator.alloc(Message, 1);
    defer allocator.free(to_be_post_messages);
    to_be_post_messages[0] = Message{
        .role = "user",
        .content = "你好",
    };

    const result = try model_handler.make_request(to_be_post_messages, allocator);
    defer allocator.free(result);
    std.debug.print("\n{s}\n", .{result});
}
