const std = @import("std");
const RLMIteration = @import("types.zig").RLMIteration;
const Messages = @import("types.zig").Message;

pub fn find_code_blocks(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "python",
            "python_script/find_code_blocks.py",
            input,
        },
    });
    defer allocator.free(res.stdout);
    defer allocator.free(res.stderr);
    const rtext = try std.fmt.allocPrint(allocator, "{s}", .{res.stdout});
    return rtext;
}

test "test" {
    const res = try find_code_blocks(
        \\```repl
        \\print("Hello, World!")
        \\print("This is a test.")
        \\print("Goodbye!")
        \\```
    , std.testing.allocator);
    defer std.testing.allocator.free(res);
    try std.testing.expectEqualStrings("print(\"Hello, World!\")\nprint(\"This is a test.\")\nprint(\"Goodbye!\")\n", res);
}
