const std = @import("std");
const QueryMetadata = @import("types.zig").QueryMetadata;
const Message = @import("types.zig").Message;

/// System prompt for long-text incremental synthesis.
pub const RLM_SYSTEM_PROMPT: []const u8 =
    \\You answer a root question by reading a very long material incrementally.
    \\
    \\You will receive one material chunk at a time plus a running summary from earlier chunks. Your job on each iteration is to update that running summary so it becomes a better evidence-backed answer to the root question.
    \\
    \\Rules:
    \\- Use only the current chunk and the prior running summary.
    \\- Keep the running summary compact, factual, and cumulative.
    \\- Preserve uncertainty when the chunk is inconclusive.
    \\- Prefer quoting or paraphrasing concrete evidence from the chunk over speculation.
    \\- Do not produce the final user-facing answer during chunk processing unless explicitly asked to finalize.
    \\- If the root question requests executable code, do not add prose explanations around that final code unless the root question explicitly asks for explanation.
    \\
    \\When processing a chunk, return an updated running summary only.
    \\When finalizing, follow the requested output format using the accumulated summary. This may be a direct answer or executable code depending on the task.
    \\If the root question asks for code only, return bare code without Markdown fences.
;

/// Build the per-chunk prompt used for incremental synthesis.
///
/// ## Parameters
/// - `input_parameters`: Struct containing:
///   - `root_prompt`: The question to answer
///   - `chunk`: Current chunk of material
///   - `chunk_index`: Current chunk index (0-indexed)
///   - `total_chunks`: Total number of chunks
///   - `running_summary`: Summary accumulated so far
/// - `allocator`: Memory allocator for allocations
///
/// ## Returns
/// ArrayList of Message structs containing the user prompt
pub fn buildUserPrompt(
    input_parameters: struct {
        root_prompt: []const u8,
        chunk: []const u8,
        chunk_index: u32,
        total_chunks: u32,
        running_summary: ?[]const u8 = null,
    },
    allocator: std.mem.Allocator,
) !std.ArrayList(Message) {
    const running_summary = input_parameters.running_summary orelse "(no relevant evidence found yet)";
    const summary_prompt = try std.fmt.allocPrint(
        allocator,
        \\Running summary so far:
        \\{s}
    ,
        .{running_summary},
    );
    const chunk_prompt = try std.fmt.allocPrint(
        allocator,
        \\Material chunk {d}/{d}:
        \\{s}
    ,
        .{ input_parameters.chunk_index + 1, input_parameters.total_chunks, input_parameters.chunk },
    );
    const task_prompt = try allocator.dupe(u8,
        \\Task:
        \\Update the running summary using only the material chunk above.
        \\- Keep it concise and cumulative.
        \\- Keep only details that help answer the root question.
        \\- If the chunk adds nothing useful, return the prior summary with a short note that this chunk was not relevant.
        \\- Return plain text only.
    );

    var result: std.ArrayList(Message) = .empty;
    try result.append(allocator, Message{
        .role = "user",
        .content = try std.fmt.allocPrint(allocator, "Root question:\n{s}", .{input_parameters.root_prompt}),
    });
    try result.append(allocator, Message{
        .role = "assistant",
        .content = summary_prompt,
    });
    try result.append(allocator, Message{
        .role = "user",
        .content = chunk_prompt,
    });
    try result.append(allocator, Message{
        .role = "user",
        .content = task_prompt,
    });
    return result;
}

/// Build the final aggregation prompt.
pub fn buildFinalPrompt(
    root_prompt: []const u8,
    running_summary: []const u8,
    allocator: std.mem.Allocator,
) !std.ArrayList(Message) {
    const summary_prompt = try std.fmt.allocPrint(
        allocator,
        \\Accumulated evidence summary:
        \\{s}
    ,
        .{running_summary},
    );

    var result: std.ArrayList(Message) = .empty;
    try result.append(allocator, Message{
        .role = "user",
        .content = try std.fmt.allocPrint(allocator, "Root question:\n{s}", .{root_prompt}),
    });
    try result.append(allocator, Message{
        .role = "assistant",
        .content = summary_prompt,
    });
    try result.append(allocator, Message{
        .role = "user",
        .content = try allocator.dupe(u8,
            \\Task:
            \\Answer the root question using only the evidence summary above.
            \\- Follow the format requested by the root question.
            \\- If the root question asks for executable code, return only the code unless the question says otherwise.
            \\- Do not wrap returned code in Markdown fences unless the root question explicitly asks for fenced code.
            \\- Do not prepend or append explanatory text around returned code unless the root question explicitly asks for explanation.
            \\- If the evidence is incomplete, say what is missing instead of inventing details.
        ),
    });
    return result;
}

test "buildUserPrompt works" {
    const allocator = std.testing.allocator;
    var prompt_with_root = try buildUserPrompt(.{
        .root_prompt = "What is the capital of France?",
        .chunk = "Paris is the capital city and largest urban area in France.",
        .chunk_index = 0,
        .total_chunks = 3,
        .running_summary = null,
    }, allocator);
    defer prompt_with_root.deinit(allocator);
    defer ReleaseMessageArray(prompt_with_root, allocator);

    try std.testing.expectEqual(@as(usize, 4), prompt_with_root.items.len);
    try std.testing.expect(std.mem.eql(u8, prompt_with_root.items[0].role, "user"));
    try std.testing.expect(std.mem.eql(u8, prompt_with_root.items[1].role, "assistant"));
    try std.testing.expect(std.mem.indexOf(u8, prompt_with_root.items[0].content, "Root question") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt_with_root.items[1].content, "Running summary so far") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt_with_root.items[2].content, "Material chunk 1/3") != null);
    try std.testing.expect(std.mem.indexOf(u8, prompt_with_root.items[2].content, "Paris is the capital city") != null);
}

test "buildFinalPrompt works" {
    const allocator = std.testing.allocator;
    var final_prompt = try buildFinalPrompt(
        "What is the capital of France?",
        "The material states that Paris is the capital city of France.",
        allocator,
    );
    defer final_prompt.deinit(allocator);
    defer ReleaseMessageArray(final_prompt, allocator);

    try std.testing.expectEqual(@as(usize, 3), final_prompt.items.len);
    try std.testing.expect(std.mem.indexOf(u8, final_prompt.items[0].content, "Root question") != null);
    try std.testing.expect(std.mem.eql(u8, final_prompt.items[1].role, "assistant"));
    try std.testing.expect(std.mem.indexOf(u8, final_prompt.items[1].content, "Accumulated evidence summary") != null);
    try std.testing.expect(std.mem.indexOf(u8, final_prompt.items[2].content, "Follow the format requested by the root question") != null);
    try std.testing.expect(std.mem.indexOf(u8, final_prompt.items[2].content, "Do not wrap returned code in Markdown fences") != null);
}

/// Build the system prompt for RLM initialization
///
/// Creates the initial system messages including the system prompt and
/// context metadata information.
///
/// ## Parameters
/// - `custom_system_prompt`: Optional custom system prompt to override default
/// - `query_metadata`: Metadata about the query context
/// - `allocator`: Memory allocator for allocations
///
/// ## Returns
/// ArrayList of 2 Message structs (system prompt and context info)
///
/// ## Memory Management
/// The caller must release both the returned ArrayList AND its contents
/// using `ReleaseMessageArray`.
///
/// ## Example
/// ```zig
/// var system_msgs = try buildSystemPrompt(null, metadata, allocator);
/// defer ReleaseMessageArray(system_msgs, allocator);
/// ```
pub fn buildSystemPrompt(custom_system_prompt: ?[]const u8, query_metadata: QueryMetadata, allocator: std.mem.Allocator) !std.ArrayList(Message) {
    const context_lengths = query_metadata.context_length;
    const context_total_length = query_metadata.context_total_length;
    const context_type = query_metadata.context_type;
    var context_lengths_str: []u8 = undefined;

    if (context_lengths.len > 100) {
        const others = context_lengths.len - 100;
        context_lengths_str = try std.fmt.allocPrint(
            allocator,
            "[{any}] ... [{d} others]",
            .{ context_lengths[0..100], others },
        );
    } else {
        context_lengths_str = try std.fmt.allocPrint(
            allocator,
            "{any}",
            .{context_lengths},
        );
    }
    defer allocator.free(context_lengths_str);

    const context_info: []u8 = try std.fmt.allocPrint(
        allocator,
        "Your material is a {s} with {d} total characters, and is broken up into chunks of char lengths: {s}.",
        .{
            context_type,
            context_total_length,
            context_lengths_str,
        },
    );
    var system_content: []u8 = undefined;
    system_content = try std.fmt.allocPrint(
        allocator,
        "{s}",
        .{custom_system_prompt orelse RLM_SYSTEM_PROMPT},
    );

    var system_prompt: std.ArrayList(Message) = .empty;
    try system_prompt.append(allocator, Message{ .role = "system", .content = system_content });
    try system_prompt.append(allocator, Message{ .role = "assistant", .content = context_info });
    return system_prompt;
}

test "buildSystemPrompt works" {
    const allocator = std.testing.allocator;
    const query_metadata: QueryMetadata = .{
        .context_length = &[2]u32{ 10, 20 },
        .context_total_length = 30,
        .context_type = "chunked_str",
    };
    var system_prompt = try buildSystemPrompt(null, query_metadata, allocator);
    defer system_prompt.deinit(allocator);
    defer ReleaseMessageArray(system_prompt, allocator);
    const formatter = std.json.fmt(.{ .message = system_prompt }, .{});

    std.debug.print("\nTESTING:System Prompt\n{f}\n", .{formatter});
}

/// Release memory for a message ArrayList
///
/// Frees all content strings in the ArrayList.
/// Must be used to clean up ArrayLists returned by buildUserPrompt and buildSystemPrompt.
/// Note: This does NOT deallocate the ArrayList itself - you must call `deinit()` separately.
///
/// ## Parameters
/// - `messages`: The message ArrayList to release (passed by value)
/// - `allocator`: Memory allocator used for allocations
///
/// ## Example
/// ```zig
/// var messages = try buildUserPrompt(..., allocator);
/// defer messages.deinit(allocator);
/// defer ReleaseMessageArray(messages, allocator);
/// ```
pub fn ReleaseMessageArray(messages: std.ArrayList(Message), allocator: std.mem.Allocator) void {
    for (messages.items) |msg| {
        allocator.free(msg.content);
    }
}
