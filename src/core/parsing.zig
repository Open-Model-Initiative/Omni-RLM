const std = @import("std");
const RLMIteration = @import("types.zig").RLMIteration;
const mvzr = @import("mvzr");

pub fn find_code_blocks(input: []const u8, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    // const res = try std.process.Child.run(.{
    //     .allocator = allocator,
    //     .argv = &[_][]const u8{
    //         "python",
    //         "python_script/find_code_blocks.py",
    //         input,
    //     },
    // });
    // defer allocator.free(res.stdout);
    // defer allocator.free(res.stderr);
    // const rtext = try std.fmt.allocPrint(allocator, "{s}", .{res.stdout});
    // return rtext;
    var pat = mvzr.compile("```repl.*?```");
    var out = pat.?.iterator(input);
    var out_list: std.ArrayList([]const u8) = .empty;
    while (out.next()) |m| {
        var str = m.slice;
        str = std.mem.trim(u8, str, "```repl");
        str = std.mem.trim(u8, str, "```");
        try out_list.append(allocator, str);
    }
    return out_list;
}

test "find_code_blocks" {
    var res = try find_code_blocks(
        \\```repl
        \\print("Hello, World!")
        \\print("This is a test.")
        \\print("Goodbye!")
        \\```
    , std.testing.allocator);
    defer res.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("\nprint(\"Hello, World!\")\nprint(\"This is a test.\")\nprint(\"Goodbye!\")\n", res.items[0]);
}
