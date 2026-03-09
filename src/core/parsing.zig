const std = @import("std");

/// Internal struct representing a code block to be executed
const CodeToBeRun = struct {
    label: []const u8,
    code: []const u8,
};

/// Find and extract code blocks from text
///
/// Parses markdown-style code blocks (```language\ncode\n```) from the input text.
/// Currently only supports Python code blocks with "repl" or "python" labels.
///
/// ## Parameters
/// - `input`: The text to search for code blocks
/// - `allocator`: Memory allocator for the result list
///
/// ## Returns
/// ArrayList of CodeToBeRun structs containing the language label and code content
///
/// ## Example
/// ```zig
/// const blocks = try find_code_blocks(
///     \`
///     \python
///     \print("Hello")
///     \`
/// , allocator);
/// defer blocks.deinit(allocator);
/// ```
pub fn find_code_blocks(
    input: []const u8,
    allocator: std.mem.Allocator,
) !std.ArrayList(CodeToBeRun) {
    var blocks = try std.ArrayList(CodeToBeRun).initCapacity(allocator, 0);

    var search_start: usize = 0;
    while (search_start < input.len) {
        // Find opening ``` followed by a language label
        const backtick_pos = std.mem.indexOf(u8, input[search_start..], "```");
        if (backtick_pos == null) break;

        const block_start = search_start + backtick_pos.?;
        const after_backticks = block_start + 3;

        // Find end of line (or end of input)
        var line_end = after_backticks;
        while (line_end < input.len and input[line_end] != '\n') : (line_end += 1) {}

        // Extract and parse the label from this line
        const label_line = input[after_backticks..line_end];
        const label = std.mem.trim(u8, label_line, " \t\r");

        if (label.len == 0) {
            // No label, skip this and continue searching
            search_start = after_backticks;
            continue;
        }

        // Find the end of the first token (the language label)
        var token_end: usize = 0;
        while (token_end < label.len and label[token_end] != ' ' and label[token_end] != '\t') : (token_end += 1) {}
        const lang_label = label[0..token_end];

        // Code starts after the newline
        const code_start = if (line_end < input.len) line_end + 1 else line_end;

        // Find closing ```
        const closing_pos = std.mem.indexOf(u8, input[code_start..], "\n```");
        if (closing_pos == null) break; // No closing marker found

        const code_end = code_start + closing_pos.?;

        // Add the block
        try blocks.append(allocator, .{
            .label = lang_label,
            .code = input[code_start..code_end],
        });

        // Continue searching after this block
        search_start = code_end + 4; // +4 for "\n```"
    }

    return blocks;
}

// TODO: - now only supports python code, should support bash code as well.
test "find_code_blocks" {
    var res = try find_code_blocks(
        \\dsaf```python
        \\print("Hello, World!")
        \\print("This is a test.")
        \\print("Goodbye!")
        \\```
    ,
        std.testing.allocator,
    );
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("print(\"Hello, World!\")\nprint(\"This is a test.\")\nprint(\"Goodbye!\")", res.items[0].code);
}

test "find_code_blocks with text before opening marker" {
    var res = try find_code_blocks(
        \\Some text before```python
        \\x = 1
        \\print(x)
        \\```
    ,
        std.testing.allocator,
    );
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(1, res.items.len);
    try std.testing.expectEqualStrings("python", res.items[0].label);
    try std.testing.expectEqualStrings("x = 1\nprint(x)", res.items[0].code);
}

test "find_code_blocks multiple blocks" {
    var res = try find_code_blocks(
        \\```python
        \\x = 1
        \\```
        \\Some middle text
        \\```repl
        \\y = 2
        \\```
    ,
        std.testing.allocator,
    );
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(2, res.items.len);
    try std.testing.expectEqualStrings("python", res.items[0].label);
    try std.testing.expectEqualStrings("x = 1", res.items[0].code);
    try std.testing.expectEqualStrings("repl", res.items[1].label);
    try std.testing.expectEqualStrings("y = 2", res.items[1].code);
}

test "find_code_blocks no code blocks" {
    var res = try find_code_blocks(
        \\Just some plain text without code blocks
    ,
        std.testing.allocator,
    );
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, res.items.len);
}

test "find_code_blocks inline backticks not confused" {
    var res = try find_code_blocks(
        \\Use `code` inline but not a block
    ,
        std.testing.allocator,
    );
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqual(0, res.items.len);
}
