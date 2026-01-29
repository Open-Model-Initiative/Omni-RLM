const std = @import("std");
const json = std.json;
const Value = json.Value;

////********TODO********////
//finish tostr implementations for each struct
////*********************////

pub const RLMMetadata = struct {
    root_model: []const u8,
    max_depth: u32,
    max_iterations: u32,
    backend: []const u8,
    backend_kwargs: []const u8,
    environment_type: []const u8,
    environment_kwargs: []const u8,
    other_backends: ?[]const u8 = null,
    pub fn tostr() void {} //TODO implement tostr
};

test "RLMMetadata" {
    const metadata = RLMMetadata{
        .root_model = "TestModel",
        .max_depth = 5,
        .max_iterations = 100,
        .backend = "openai",
        .backend_kwargs =
        \\{"api_key":"secret"}
        ,
        .environment_type = "local",
        .environment_kwargs = "{}",
        .other_backends = null,
    };

    const parsed: json.Parsed(Value) = try std.json.parseFromSlice(Value, std.testing.allocator, metadata.backend_kwargs, .{});
    defer parsed.deinit();

    var obj: std.array_hash_map.StringArrayHashMap(Value) = parsed.value.object;
    const api_key = obj.get("api_key");

    try std.testing.expectEqualStrings(api_key.?.string, "secret");
    try std.testing.expectEqualStrings(metadata.root_model, "TestModel");
    try std.testing.expect(metadata.max_depth == 5);
    try std.testing.expectEqualStrings(metadata.backend, "openai");
}

////TODO add split prompt metadata, now only support str context(multi types e.g. dict, list)
/// Need to Init and Deinit
pub const QueryMetadata = struct {
    context_length: []const u32,
    context_total_length: u32,
    context_type: []const u8,
    pub fn tostr() void {} //TODO implement tostr

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
    code_blocks: CodeBlock, // TODO change to array in the future, when changing the function format_iteration need to be changed too
    final_answer: ?[]const u8 = null,
    iteration_time: i64,
    pub fn tostr() void {} //TODO implement tostr
    pub fn format_iteration(self: *RLMIteration, allocator: std.mem.Allocator) ![]Message {
        var Messages = try allocator.alloc(Message, 2);

        Messages[0] = Message{
            .role = "assistant",
            .content = try allocator.dupe(u8, self.response),
        };
        const code = self.code_blocks.code;
        const result = try std.fmt.allocPrint(allocator, "STDOUT:\n{s}\n\nSTDERR:\n{s}\n\n", .{ self.code_blocks.result.stdout, self.code_blocks.result.stderr });
        defer allocator.free(result);
        Messages[1] = Message{
            .role = "system",
            .content = try std.fmt.allocPrint(allocator, "Code executed:\n```python\n{s}\n```\nREPL output::\n{s}", .{ code, result }),
        };
        return Messages;
    }

    pub fn find_final_answer(self: *RLMIteration, allocator: std.mem.Allocator) !void {
        const text = self.response;
        const res = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "-c",
                \\import re, sys, dill
                \\dill.load_session("env.dill")
                \\text = sys.argv[1]
                \\final_var_pattern = r"^\s*FINAL(_VAR)?\((.*?)\)"
                \\match = re.search(final_var_pattern, text, re.MULTILINE | re.DOTALL)
                \\if match:
                \\    variable_name = match.group(2).strip().strip('"').strip("'")
                \\    if variable_name in globals():
                \\        final_answer = FINAL_VAR(variable_name)
                \\    else:
                \\        final_answer = FINAL(variable_name)
                \\    if final_answer is not None:
                \\        final_answer = final_answer.strip()
                \\    print(final_answer if final_answer else None)
                ,
                text,
            },
        });
        defer allocator.free(res.stdout);
        defer allocator.free(res.stderr);
        if (std.mem.eql(u8, res.stdout, "None\n") or res.stderr.len != 0 or res.stdout.len == 0) {} else {
            self.final_answer = try allocator.dupe(u8, res.stdout);
        }
    }
};

test "RLMIteration find_final_answer" {
    const allocator = std.testing.allocator;
    var iteration = RLMIteration{
        .prompt = &[_]Message{},
        .response =
        \\FINAL(result)\n```
        ,
        .code_blocks = CodeBlock{
            .code = "",
            .result = std.process.Child.RunResult{
                .stdout = "",
                .stderr = "",
                .term = .{ .Exited = 0 },
            },
        },
        .final_answer = null,
        .iteration_time = 123456,
    };

    try iteration.find_final_answer(allocator);
    defer {
        if (iteration.final_answer) |fa| {
            allocator.free(fa);
        }
    }
    if (iteration.final_answer == null) {
        std.debug.print("\nNo final answer found\n", .{});
    } else {
        std.debug.print("\nFinal answer: {s}\n", .{iteration.final_answer.?});
    }
}

pub const RLMChatCompletion = struct {
    root_model: []const u8,
    prompt: []const u8,
    response: []const u8,
    // usage_sumary: []const u8,//TODO implement usage summary
    execution_time: i64,
};

pub const CodeBlock = struct {
    code: []const u8,
    result: std.process.Child.RunResult,
    pub fn tostr() void {} //TODO implement tostr
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

pub const EnvHandler = struct {
    mainfunc: []const u8 = "python_script/env_init.py",
    context: ?[]const u8 = null,
    pub fn tostr() void {} //TODO implement tostr
    pub fn execute_code(self: *const EnvHandler, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "python", self.mainfunc, code, self.context orelse "" },
        });
        return result;
    }
};

test "EnvHandler execute_code" {
    const allocator = std.testing.allocator;
    const env = EnvHandler{
        .mainfunc = "python_script/env_init.py",
    };
    const code = "for i in range(20):\n   print('Hello from EnvHandler')";
    const result = try env.execute_code(code, allocator);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    std.debug.print("{s}", .{result.stdout});
}
