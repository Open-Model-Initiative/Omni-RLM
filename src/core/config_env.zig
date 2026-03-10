const std = @import("std");
const backendKwargs = @import("types.zig").backendKwargs;

pub const DaytonaEnvConfig = struct {
    api_key: []const u8,
    api_url: []const u8,

    pub fn deinit(self: *DaytonaEnvConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.api_key);
        allocator.free(self.api_url);
    }
};

fn trim_quotes(value: []const u8) []const u8 {
    if (value.len >= 2 and
        ((value[0] == '"' and value[value.len - 1] == '"') or
            (value[0] == '\'' and value[value.len - 1] == '\'')))
    {
        return value[1 .. value.len - 1];
    }
    return value;
}

fn resolve_env_value(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    if (value.len >= 4 and value[0] == '$' and value[1] == '{' and value[value.len - 1] == '}') {
        const env_name = value[2 .. value.len - 1];
        return std.process.getEnvVarOwned(allocator, env_name) catch error.MissingReferencedEnvVar;
    }

    if (value.len >= 2 and value[0] == '$') {
        const env_name = value[1..];
        return std.process.getEnvVarOwned(allocator, env_name) catch error.MissingReferencedEnvVar;
    }

    return allocator.dupe(u8, value);
}

fn parse_backend_from_content(allocator: std.mem.Allocator, content: []const u8) !backendKwargs {
    var api_key_raw: ?[]const u8 = null;
    var base_url_raw: ?[]const u8 = null;
    var model_name_raw: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq_idx], " \t");
        const value_part = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");
        const value = trim_quotes(value_part);

        if (std.mem.eql(u8, key, "OMNIRLM_API_KEY") or
            std.mem.eql(u8, key, "DASHSCOPE_API_KEY") or
            std.mem.eql(u8, key, "OPENAI_API_KEY"))
        {
            api_key_raw = value;
        } else if (std.mem.eql(u8, key, "OMNIRLM_BASE_URL")) {
            base_url_raw = value;
        } else if (std.mem.eql(u8, key, "OMNIRLM_MODEL_NAME")) {
            model_name_raw = value;
        }
    }

    if (api_key_raw == null or base_url_raw == null or model_name_raw == null) {
        return error.MissingRequiredEnvKey;
    }

    const api_key = try resolve_env_value(allocator, api_key_raw.?);
    errdefer allocator.free(api_key);
    const base_url = try resolve_env_value(allocator, base_url_raw.?);
    errdefer allocator.free(base_url);
    const model_name = try resolve_env_value(allocator, model_name_raw.?);
    errdefer allocator.free(model_name);

    return .{ .api_key = api_key, .base_url = base_url, .model_name = model_name };
}

fn parse_daytona_from_content(allocator: std.mem.Allocator, content: []const u8) !DaytonaEnvConfig {
    var api_key_raw: ?[]const u8 = null;
    var api_url_raw: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq_idx], " \t");
        const value_part = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");
        const value = trim_quotes(value_part);

        if (std.mem.eql(u8, key, "DAYTONA_API_KEY") or std.mem.eql(u8, key, "OMNIRLM_DAYTONA_API_KEY")) {
            api_key_raw = value;
        } else if (std.mem.eql(u8, key, "DAYTONA_API_URL") or std.mem.eql(u8, key, "OMNIRLM_DAYTONA_API_URL")) {
            api_url_raw = value;
        }
    }

    if (api_key_raw == null) {
        return error.MissingRequiredEnvKey;
    }

    const api_key = try resolve_env_value(allocator, api_key_raw.?);
    errdefer allocator.free(api_key);

    const api_url = if (api_url_raw) |raw_url|
        try resolve_env_value(allocator, raw_url)
    else
        try allocator.dupe(u8, "https://app.daytona.io/api");
    errdefer allocator.free(api_url);

    return .{ .api_key = api_key, .api_url = api_url };
}

/// Load backend config from a .env-like file.
///
/// Required keys:
/// - OMNIRLM_API_KEY (or DASHSCOPE_API_KEY / OPENAI_API_KEY)
/// - OMNIRLM_BASE_URL
/// - OMNIRLM_MODEL_NAME
pub fn load_backend_env_config(allocator: std.mem.Allocator, env_path: []const u8) !backendKwargs {
    const content = std.fs.cwd().readFileAlloc(allocator, env_path, 1024 * 1024) catch {
        std.debug.print("Failed to load backend config from .env. Required keys: OMNIRLM_API_KEY (or DASHSCOPE_API_KEY/OPENAI_API_KEY), OMNIRLM_BASE_URL, OMNIRLM_MODEL_NAME.\n", .{});
        return error.MissingBackendConfig;
    };
    defer allocator.free(content);

    return parse_backend_from_content(allocator, content);
}

/// Load Daytona environment config from a .env-like file.
///
/// Required keys:
/// - DAYTONA_API_KEY (or OMNIRLM_DAYTONA_API_KEY)
///
/// Optional keys:
/// - DAYTONA_API_URL (or OMNIRLM_DAYTONA_API_URL), defaults to https://app.daytona.io/api
pub fn load_daytona_env_config(allocator: std.mem.Allocator, env_path: []const u8) !DaytonaEnvConfig {
    const content = std.fs.cwd().readFileAlloc(allocator, env_path, 1024 * 1024) catch {
        std.debug.print("Failed to load daytona config from .env. Required keys: DAYTONA_API_KEY (or OMNIRLM_DAYTONA_API_KEY).\n", .{});
        return error.MissingDaytonaConfig;
    };
    defer allocator.free(content);

    return parse_daytona_from_content(allocator, content);
}

test "parse backend config from dotenv content" {
    const allocator = std.testing.allocator;
    const content =
        \\OMNIRLM_API_KEY=sk-test
        \\OMNIRLM_BASE_URL=https://example.com/v1/chat/completions
        \\OMNIRLM_MODEL_NAME=qwen-plus
    ;

    var cfg = try parse_backend_from_content(allocator, content);
    defer cfg.deinit(allocator);

    try std.testing.expectEqualStrings("sk-test", cfg.api_key);
    try std.testing.expectEqualStrings("https://example.com/v1/chat/completions", cfg.base_url);
    try std.testing.expectEqualStrings("qwen-plus", cfg.model_name);
}

test "parse backend config with env reference" {
    const allocator = std.testing.allocator;
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return error.SkipZigTest;
    defer allocator.free(home);

    const content =
        \\OMNIRLM_API_KEY=${HOME}
        \\OMNIRLM_BASE_URL=https://example.com/v1/chat/completions
        \\OMNIRLM_MODEL_NAME=qwen-plus
    ;

    var cfg = try parse_backend_from_content(allocator, content);
    defer cfg.deinit(allocator);

    try std.testing.expectEqualStrings(home, cfg.api_key);
}

test "parse daytona config from dotenv content" {
    const allocator = std.testing.allocator;
    const content =
        \\DAYTONA_API_KEY=dt-test
        \\DAYTONA_API_URL=https://app.daytona.io/api
    ;

    var cfg = try parse_daytona_from_content(allocator, content);
    defer cfg.deinit(allocator);

    try std.testing.expectEqualStrings("dt-test", cfg.api_key);
    try std.testing.expectEqualStrings("https://app.daytona.io/api", cfg.api_url);
}

test "parse daytona config default api url" {
    const allocator = std.testing.allocator;

    var cfg = try load_daytona_env_config(allocator, ".env");
    defer cfg.deinit(allocator);

    try std.testing.expectEqualStrings("https://app.daytona.io/api", cfg.api_url);
}
