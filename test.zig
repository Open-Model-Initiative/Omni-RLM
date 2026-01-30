const file_list = [_][]const u8{
    "Model_info.zig",
    "parsing.zig",
    "prompt.zig",
    "rlm_logger.zig",
    "rlm.zig",
    "types.zig",
};
test {
    const std = @import("std");
    std.testing.refAllDeclsRecursive(@This());
    _ = @import("Model_info.zig");
    _ = @import("parsing.zig");
    _ = @import("prompt.zig");
    _ = @import("rlm_logger.zig");
    _ = @import("rlm.zig");
    _ = @import("types.zig");
}
