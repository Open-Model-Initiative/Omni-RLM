const file_list = [_][]const u8{
    "core/Model_info.zig",
    "core/config_env.zig",
    "core/parsing.zig",
    "core/prompt.zig",
    "core/rlm_logger.zig",
    "core/rlm.zig",
    "core/types.zig",
    "core/environment/type.zig",
    "core/environment/local/local.zig",
    "core/environment/daytona/daytona.zig",
};
test {
    const std = @import("std");
    std.testing.refAllDeclsRecursive(@This());
    _ = @import("core/Model_info.zig");
    _ = @import("core/config_env.zig");
    _ = @import("core/parsing.zig");
    _ = @import("core/prompt.zig");
    _ = @import("core/rlm_logger.zig");
    _ = @import("core/rlm.zig");
    _ = @import("core/types.zig");
    _ = @import("core/environment/type.zig");
    _ = @import("core/environment/local/local.zig");
    _ = @import("core/environment/daytona/daytona.zig");
}
