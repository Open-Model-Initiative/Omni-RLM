const std = @import("std");
const RLMIteration = @import("types.zig").RLMIteration;
const Messages = @import("types.zig").Message;

pub fn find_code_blocks(input: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "python3",
            "-c",
            \\import re, sys
            \\def find_code_blocks(input):
            \\     pattern = r"```repl\s*\n(.*?)```"
            \\     result = []
            \\     for match in re.finditer(pattern, input, re.DOTALL):
            \\         code_content = match.group(1).strip()
            \\         result.append(code_content)
            \\     return result
            \\input = sys.argv[1]
            \\out = "\\n".join(find_code_blocks(input))
            \\final = re.search(r"FINAL(_VAR)?\((.*?)\)", input)
            \\if final and "FINAL" not in out:
            \\    out += "\n" + final.group(0)
            \\print(out)
            ,
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
        \\
        \\```repl
        \\x = 5
        \\y = 10
        \\print(f"Sum: {x + y}")
        \\```
    , std.testing.allocator);
    defer std.testing.allocator.free(res);
    std.debug.print("{s}", .{res});
}
