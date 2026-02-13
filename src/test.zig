const file_list = [_][]const u8{
    "core/Model_info.zig",
    "core/parsing.zig",
    "core/prompt.zig",
    "core/rlm_logger.zig",
    "core/rlm.zig",
    "core/types.zig",
    "core/environment/type.zig",
    "core/environment/local.zig",
    "core/environment/daytona.zig",
};
test {
    const std = @import("std");
    std.testing.refAllDeclsRecursive(@This());
    _ = @import("core/Model_info.zig");
    _ = @import("core/parsing.zig");
    _ = @import("core/prompt.zig");
    _ = @import("core/rlm_logger.zig");
    _ = @import("core/rlm.zig");
    _ = @import("core/types.zig");
    _ = @import("core/environment/type.zig");
    _ = @import("core/environment/local.zig");
    _ = @import("core/environment/daytona.zig");
}

test "env" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    const api_key = std.process.getEnvVarOwned(allocator, "DASHSCOPE_API_KEY") catch {
        std.debug.print("\nEnvironment variable DASHSCOPE_API_KEY is not set.\n", .{});
        return error.MissingApiKey;
    };
    defer allocator.free(api_key);
}
