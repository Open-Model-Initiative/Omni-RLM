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
///     \\`
///     \\python
///     \\print("Hello")
///     \\`
/// , allocator);
/// defer blocks.deinit(allocator);
/// ```
pub fn find_code_blocks(
    input: []const u8,
    allocator: std.mem.Allocator,
) !std.ArrayList(CodeToBeRun) {
    var blocks = try std.ArrayList(CodeToBeRun).initCapacity(allocator, 0);

    var inside_block = false;
    var current_label: []const u8 = "";
    var code_start: usize = 0;

    var i: usize = 0;
    while (i < input.len) {
        const line_start = i;
        while (i < input.len and input[i] != '\n') : (i += 1) {}
        const line_end = i;

        var trimmed_end = line_end;
        if (trimmed_end > line_start and input[trimmed_end - 1] == '\r') {
            trimmed_end -= 1;
        }
        const line = input[line_start..trimmed_end];

        if (!inside_block) {
            if (line.len >= 3 and std.mem.eql(u8, line[0..3], "```")) {
                const rest = std.mem.trimLeft(u8, line[3..], " \t");
                var token_end: usize = 0;
                while (token_end < rest.len and rest[token_end] != ' ' and rest[token_end] != '\t') : (token_end += 1) {}

                if (token_end > 0) {
                    current_label = rest[0..token_end];
                    inside_block = true;
                    code_start = if (i < input.len and input[i] == '\n') i + 1 else i;
                }
            }
        } else {
            if (std.mem.eql(u8, line, "```")) {
                try blocks.append(allocator, .{
                    .label = current_label,
                    .code = input[code_start..line_start],
                });
                inside_block = false;
                current_label = "";
            }
        }

        if (i < input.len and input[i] == '\n') {
            i += 1;
        }
    }

    return blocks;
}

// TODO: - now only supports python code, should support bash code as well.
test "find_code_blocks" {
    var res = try find_code_blocks(
        \\```python
        \\print("Hello, World!")
        \\print("This is a test.")
        \\print("Goodbye!")
        \\```
    ,
        std.testing.allocator,
    );
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("print(\"Hello, World!\")\nprint(\"This is a test.\")\nprint(\"Goodbye!\")\n", res.items[0].code);
}
