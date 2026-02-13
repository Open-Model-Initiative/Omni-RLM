const std = @import("std");
const json = std.json;
const Value = json.Value;

pub const backendKwargs = struct {
    api_key: []const u8,
    base_url: []const u8,
    model_name: []const u8,
};

pub const RLMMetadata = struct {
    root_model: []const u8,
    max_depth: u32,
    max_iterations: u32,
    backend: []const u8,
    backend_kwargs: backendKwargs,
    environment_type: ?[]const u8 = null,
    environment_kwargs: ?[]const u8 = null,
    other_backends: ?[]const u8 = null,
};

////TODO add split prompt metadata, now only support str context(multi types e.g. dict, list)
/// Need to Init and Deinit
pub const QueryMetadata = struct {
    context_length: []const u32,
    context_total_length: u32,
    context_type: []const u8,

    pub fn init(prompt: []const u8, allocator: std.mem.Allocator) QueryMetadata {
        const context_length = allocator.alloc(u32, 1) catch unreachable;
        context_length[0] = @as(u32, @intCast(prompt.len));
        return QueryMetadata{
            .context_length = context_length,
            .context_total_length = context_length[0],
            .context_type = "str",
        };
    }
    pub fn deinit(self: *QueryMetadata, allocator: std.mem.Allocator) void {
        allocator.free(self.context_length);
        self.* = undefined;
    }
};

pub const RLMIteration = struct {
    prompt: []Message,
    ///repl like response from LM
    response: []const u8,
    code_blocks: []CodeBlock,
    final_answer: ?[]const u8 = null,
    iteration_time: i64,
    pub fn format_iteration(self: *RLMIteration, allocator: std.mem.Allocator) ![]Message {
        var Messages = try allocator.alloc(Message, self.code_blocks.len + 1);
        Messages[0] = Message{
            .role = "assistant",
            .content = try allocator.dupe(u8, self.response),
        };
        for (0..self.code_blocks.len) |index| {
            const code = self.code_blocks[index].code;
            const result = try std.fmt.allocPrint(
                allocator,
                "STDOUT:\n{s}\n\nSTDERR:\n{s}\n\n",
                .{ self.code_blocks[index].result.stdout, self.code_blocks[index].result.stderr },
            );
            defer allocator.free(result);
            Messages[index + 1] = Message{
                .role = "user",
                .content = try std.fmt.allocPrint(allocator, "Code executed:\n```python\n{s}\n```\nREPL output::\n{s}", .{ code, result }),
            };
        }
        return Messages;
    }
};

pub const RLMChatCompletion = struct {
    root_model: []const u8,
    prompt: []const u8,
    response: []const u8,
    // usage_sumary: []const u8,//TODO implement usage summary
    execution_time: i64,
};

pub const CodeBlock = struct {
    code: []const u8,
    result: std.process.Child.RunResult, // TODO change the struct support locals, execution_time, rlm_calls.
    pub fn deinit(self: *CodeBlock, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.result.stderr);
        allocator.free(self.result.stdout);
        self.* = undefined;
    }
};

pub const Message = struct {
    role: []const u8 = "user",
    content: []const u8 = "",
};
