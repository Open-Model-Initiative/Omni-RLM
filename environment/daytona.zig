const std = @import("std");
pub const DaytonaEnv = struct {
    api_url: []const u8 = "https://app.daytona.io/api",
    api_key: []const u8 = "",
    context: ?[]const u8 = null,
    container_id: ?[]const u8 = null,

    pub fn init(self: *DaytonaEnv, kwargs: []const u8, prompt: []const u8, allocator: std.mem.Allocator) !void {
        const parsed: std.json.Parsed(DaytonaEnv) = try std.json.parseFromSlice(DaytonaEnv, allocator, kwargs, .{});
        defer parsed.deinit();
        self.* = parsed.value;
        self.context = prompt;
        const run_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "environment/daytona_script.py",
                self.api_key,
                "--api-url",
                self.api_url,
                "--container-id",
                self.container_id orelse "",
                "--prompt",
                prompt,
            },
        });
        defer {
            allocator.free(run_result.stdout);
            allocator.free(run_result.stderr);
        }
        std.debug.print("\nContainer: {s} created\n", .{run_result.stdout});
        self.container_id = try allocator.dupe(u8, run_result.stdout);
    }

    pub fn deinit(self: *DaytonaEnv, allocator: std.mem.Allocator) !void {
        const run_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "environment/daytona_script.py",
                self.api_key,
                "--api-url",
                self.api_url,
                "--container-id",
                self.container_id orelse "",
                "delete",
            },
        });
        defer {
            allocator.free(run_result.stdout);
            allocator.free(run_result.stderr);
        }
        std.debug.print("\nContainer: {s} deleted\n", .{run_result.stdout});
        if (self.container_id) |id| {
            allocator.free(id);
            self.container_id = null;
        }
    }

    pub fn execute_code(self: *const DaytonaEnv, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        const run_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "environment/daytona_script.py",
                self.api_key,
                "--api-url",
                self.api_url,
                "--container-id",
                self.container_id orelse "",
                "--code",
                code,
            },
        });
        return run_result;
    }

    pub fn find_final_answer(self: *const DaytonaEnv, text: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
        const run_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "python",
                "environment/daytona_script.py",
                self.api_key,
                "--api-url",
                self.api_url,
                "--container-id",
                self.container_id orelse "",
                "--find_final_answer",
                text,
            },
        });
        defer {
            allocator.free(run_result.stdout);
            allocator.free(run_result.stderr);
        }
        if (std.mem.eql(u8, run_result.stdout, "None") or run_result.stderr.len != 0 or run_result.stdout.len == 0) {
            return null;
        } else {
            return try allocator.dupe(u8, run_result.stdout);
        }
    }
};

test "DaytonaEnv execute_code" {
    const allocator = std.testing.allocator;
    const kwargs = "{\"api_url\": \"https://app.daytona.io/api\", \"api_key\": \"\"}";
    var env = DaytonaEnv{};
    try env.init(kwargs, "This is a prompt", allocator);
    const code = "print(context)\nprint('Hello from DaytonaEnv')";
    const result = try env.execute_code(code, allocator);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expectEqualStrings("This is a prompt\nHello from DaytonaEnv\n", result.stdout);
    try env.deinit(allocator);
}
