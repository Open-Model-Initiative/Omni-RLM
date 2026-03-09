const std = @import("std");
const Metadata = @import("types.zig").RLMMetadata;
const RLMIteration = @import("types.zig").RLMIteration;

/// Format a timestamp as ISO 8601 format with microseconds
///
/// ## Parameters
/// - `allocator`: Memory allocator for the result string
/// - `seconds`: Unix timestamp in seconds
///
/// ## Returns
/// Formatted timestamp string (e.g., "2024-01-15T10:30:45.123456")
fn formatTimestampUtc(allocator: std.mem.Allocator, seconds: i64) ![]const u8 {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(seconds + 60 * 60 * 8) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
        @as(u64, @intCast(@mod(std.time.microTimestamp(), 1000_000))),
    });
}
test "time" {
    const allocator = std.testing.allocator;
    const timestamp_str = try formatTimestampUtc(allocator, std.time.timestamp());
    defer allocator.free(timestamp_str);
    std.debug.print("\nCurrent UTC time: {s}\n", .{timestamp_str});
}

/// Format a timestamp for use in filenames
///
/// ## Parameters
/// - `allocator`: Memory allocator for the result string
/// - `seconds`: Unix timestamp in seconds
///
/// ## Returns
/// Filename-safe timestamp string (e.g., "20240115_10-30-45")
fn formatTimestampUtcForFilename(allocator: std.mem.Allocator, seconds: i64) ![]const u8 {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(seconds + 60 * 60 * 8) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    return std.fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}_{d:0>2}-{d:0>2}-{d:0>2}", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

/// Logger for RLM iterations
///
/// Writes RLM iteration data and metadata to JSON-lines files for analysis and debugging.
/// Each log entry is written as a separate JSON line with timestamp and type information.
///
/// ## Fields
/// - `log_dir`: Directory path for log files
/// - `log_file_path`: Full path to the current log file
/// - `iteration_count`: Number of iterations logged so far
/// - `metadata_logged`: Whether metadata has been written
///
/// ## Example
/// ```zig
/// var logger = try RLMLogger.init("./logs", "my_run", allocator);
/// defer logger.deinit(allocator);
///
/// // Log session metadata
/// try logger.log_metadata(metadata, allocator);
///
/// // Log each iteration
/// try logger.log_iteration(iteration_data, allocator);
/// ```
pub const RLMLogger = struct {
    // Placeholder for logger fields
    log_dir: []const u8,
    log_file_path: []const u8,
    iteration_count: u32,
    metadata_logged: bool,

    /// Initialize a new RLMLogger
    ///
    /// Creates the log directory if it doesn't exist and generates a unique
    /// log filename with timestamp and random ID.
    ///
    /// ## Parameters
    /// - `log_dir`: Directory path for log files (created if needed)
    /// - `file_name`: Base name for the log file
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// Initialized RLMLogger ready for logging
    ///
    /// ## Errors
    /// Returns error if directory creation or path allocation fails
    pub fn init(
        log_dir: []const u8,
        file_name: []const u8,
        allocator: std.mem.Allocator,
    ) !RLMLogger {
        // Create log directory if it doesn't exist
        std.fs.Dir.makeDir(std.fs.cwd(), log_dir) catch {};

        const timestamp_str = try formatTimestampUtcForFilename(allocator, std.time.timestamp());
        defer allocator.free(timestamp_str);

        // Generate random 8-character hex ID
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        const random = prng.random();
        var random_bytes: [4]u8 = undefined;
        random.bytes(&random_bytes);
        const run_id = try std.fmt.allocPrint(allocator, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            random_bytes[0], random_bytes[1], random_bytes[2], random_bytes[3],
        });
        defer allocator.free(run_id);

        const log_file_path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}_{s}_{s}.jsonl",
            .{ log_dir, file_name, timestamp_str, run_id },
        );

        std.debug.print("\nLogger initialized with log file path: {s}\n", .{log_file_path});

        return RLMLogger{
            .log_dir = log_dir,
            .log_file_path = log_file_path,
            .iteration_count = 0,
            .metadata_logged = false,
        };
    }

    /// Deinitialize the logger
    ///
    /// Frees the log file path memory.
    ///
    /// ## Parameters
    /// - `allocator`: Memory allocator used for allocations
    pub fn deinit(self: *RLMLogger, allocator: std.mem.Allocator) void {
        allocator.free(self.log_file_path);
        self.* = undefined;
    }

    /// Log a single RLM iteration
    ///
    /// Writes iteration data to the log file as a JSON line with
    /// timestamp, iteration number, and type marker.
    ///
    /// ## Parameters
    /// - `iteration_data`: The RLMIteration to log
    /// - `allocator`: Memory allocator for temporary allocations
    ///
    /// ## Errors
    /// Returns error if JSON serialization or file write fails
    pub fn log_iteration(self: *RLMLogger, iteration_data: RLMIteration, allocator: std.mem.Allocator) !void {
        self.iteration_count += 1;
        const data_string = try std.json.Stringify.valueAlloc(allocator, iteration_data, .{});
        defer allocator.free(data_string);

        var entry: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(std.json.Value, allocator, data_string, .{});
        defer entry.deinit();

        const timestamp_str = try formatTimestampUtc(allocator, std.time.timestamp());
        defer allocator.free(timestamp_str);

        try entry.value.object.put("type", std.json.Value{ .string = "iteration" });
        try entry.value.object.put("iteration", std.json.Value{ .integer = @intCast(self.iteration_count) });
        try entry.value.object.put("timestamp", std.json.Value{ .string = timestamp_str });

        const json_iteration = std.json.fmt(entry.value, .{});
        const str = try std.fmt.allocPrint(allocator, "{f}", .{json_iteration});
        defer allocator.free(str);
        try self.log(str);
    }

    /// Log session metadata
    ///
    /// Writes RLM configuration metadata to the log file.
    /// The API key is automatically stripped from the logged output for security.
    /// Only logs metadata once per session.
    ///
    /// ## Parameters
    /// - `metadata`: The RLMMetadata to log
    /// - `allocator`: Memory allocator for temporary allocations
    ///
    /// ## Errors
    /// Returns error if JSON serialization or file write fails
    pub fn log_metadata(self: *RLMLogger, metadata: Metadata, allocator: std.mem.Allocator) !void {
        if (self.metadata_logged) return;

        const data_string = try std.json.Stringify.valueAlloc(allocator, metadata, .{});
        defer allocator.free(data_string);

        var entry: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(std.json.Value, allocator, data_string, .{});
        defer entry.deinit();

        // process environment_kwargs to be json object
        var env_kwargs_entry: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            metadata.environment_kwargs,
            .{},
        );
        defer env_kwargs_entry.deinit();
        try entry.value.object.put("environment_kwargs", env_kwargs_entry.value);

        const timestamp_str = try formatTimestampUtc(allocator, std.time.timestamp());
        defer allocator.free(timestamp_str);

        try entry.value.object.put("type", std.json.Value{ .string = "metadata" });
        try entry.value.object.put("timestamp", std.json.Value{ .string = timestamp_str });
        if (entry.value.object.getPtr("backend_kwargs")) |backend_kwargs| {
            _ = backend_kwargs.object.swapRemove("api_key");
        }

        const json_metadata = std.json.fmt(entry.value, .{});
        const str = try std.fmt.allocPrint(allocator, "{f}", .{json_metadata});
        defer allocator.free(str);
        try self.log(str);

        self.metadata_logged = true;
    }

    /// Write a line to the log file
    ///
    /// Internal method to append data to the log file.
    /// Creates the file if it doesn't exist, otherwise appends.
    ///
    /// ## Parameters
    /// - `data`: String to write to the log
    ///
    /// ## Errors
    /// Returns error if file operations fail
    fn log(self: *RLMLogger, data: []const u8) !void {
        var file: std.fs.File = undefined;
        file = std.fs.cwd().createFile(self.log_file_path, .{
            .exclusive = true,
            .lock = .exclusive,
        }) catch try std.fs.cwd().openFile(self.log_file_path, .{
            .mode = .read_write,
            .lock = .exclusive,
        });
        try file.seekFromEnd(0);
        defer file.close();
        try file.writeAll(data);
        try file.writeAll("\n");
    }
};

test "RLMLogger initialization" {
    const allocator = std.testing.allocator;
    var logger = try RLMLogger.init("./logs", "Test initialization", allocator);
    defer logger.deinit(allocator);

    try std.testing.expectEqualStrings(logger.log_dir, "./logs");
    try std.testing.expect(logger.iteration_count == 0);
    try std.testing.expect(!logger.metadata_logged);
}

test "RLMLogger log_iteration" {
    const Message = @import("types.zig").Message;
    const CodeBlock = @import("types.zig").CodeBlock;
    const allocator = std.testing.allocator;
    var logger = try RLMLogger.init("./logs", "Test rlmiteration", allocator);
    defer logger.deinit(allocator);

    var prompt: std.ArrayList(Message) = .empty;
    try prompt.append(allocator, Message{ .role = "user", .content = try allocator.dupe(u8, "Calculate 1+1") });

    var iteration_data: RLMIteration = .{
        .prompt = prompt,
        .response = "1+1=2",
        .code_blocks = allocator.dupe(CodeBlock, &.{CodeBlock{
            .code = "print(1+1)",
            .result = .{
                .stdout = "",
                .stderr = "",
                .term = .{ .Exited = 0 },
            },
        }}) catch unreachable,
        .final_answer = "2",
        .iteration_time = 10,
    };
    defer {
        for (iteration_data.prompt.items) |msg| {
            allocator.free(msg.content);
        }
        iteration_data.prompt.deinit(allocator);
        allocator.free(iteration_data.code_blocks);
    }

    try logger.log_iteration(iteration_data, allocator);
}

test "RLMLogger log_metadata" {
    const allocator = std.testing.allocator;
    var logger = try RLMLogger.init("./logs", "Test rlmmetadata", allocator);
    defer logger.deinit(allocator);
    const metadata: Metadata = .{
        .root_model = "TestModel",
        .max_depth = 5,
        .max_iterations = 100,
        .backend = "openai",
        .backend_kwargs = .{
            .api_key = "sk-scret",
            .base_url = "www.test.com",
            .model_name = "qwen",
        },
        .environment_type = "local",
        .environment_kwargs = "{}",
        .other_backends = null,
    };

    try logger.log_metadata(metadata, allocator);
}
