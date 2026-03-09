const std = @import("std");
const config_env = @import("../../config_env.zig");
const Client = std.http.Client;
const Request = Client.Request;

const ExecuteResponse = struct {
    exitCode: i32,
    result: []const u8,
};

const WrappedPythonResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: i32,
};

/// Daytona sandbox environment handler
///
/// Manages code execution in Daytona sandbox containers via API calls.
/// Provides isolated execution environment with automatic container lifecycle management.
///
/// ## Fields
/// - `api_url`: Daytona API endpoint URL
/// - `api_key`: API key for Daytona authentication
/// - `context`: The user prompt/context for the session
/// - `container_id`: ID of the created sandbox container
///
/// ## Example
/// ```zig
/// var env = DaytonaEnv{};
/// try env.init(
///     "{\"api_url\": \"https://app.daytona.io/api\", \"api_key\": \"key\"}",
///     "What is 2+2?",
///     allocator
/// );
/// defer env.deinit(allocator) catch {};
///
/// const result = try env.execute_code("print(2+2)", allocator);
/// defer allocator.free(result.stdout);
/// defer allocator.free(result.stderr);
/// ```
pub const DaytonaEnv = struct {
    api_url: []const u8 = "https://app.daytona.io/api",
    api_key: []const u8 = "",
    context: ?[]const u8 = null,
    container_id: ?[]const u8 = null,
    api_url_owned: bool = false,
    api_key_owned: bool = false,

    fn extractFinalFallback(text: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
        const tag_var = "FINAL_VAR(";
        const tag_final = "FINAL(";

        const var_idx_opt = std.mem.lastIndexOf(u8, text, tag_var);
        const final_idx_opt = std.mem.lastIndexOf(u8, text, tag_final);

        var start_idx: usize = 0;
        if (var_idx_opt == null and final_idx_opt == null) return null;
        if (var_idx_opt != null and (final_idx_opt == null or var_idx_opt.? > final_idx_opt.?)) {
            start_idx = var_idx_opt.? + tag_var.len;
        } else {
            start_idx = final_idx_opt.? + tag_final.len;
        }

        const remain = text[start_idx..];
        const close_rel = std.mem.indexOfScalar(u8, remain, ')') orelse return null;
        const raw_arg = remain[0..close_rel];
        const trimmed = std.mem.trim(u8, raw_arg, " \t\r\n\"'");
        if (trimmed.len == 0) return null;
        return try allocator.dupe(u8, trimmed);
    }

    fn postJson(self: *const DaytonaEnv, endpoint: []const u8, body: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const uri = try std.Uri.parse(endpoint);
        var client: Client = .{ .allocator = allocator };
        defer client.deinit();

        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
        defer allocator.free(auth_header);

        const headers: Request.Headers = .{
            .accept_encoding = .{ .override = "identity" },
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = auth_header },
        };

        var request: Request = try client.request(.POST, uri, .{ .headers = headers });
        defer request.deinit();

        const body_mut = try allocator.dupe(u8, body);
        defer allocator.free(body_mut);
        _ = try request.sendBodyComplete(body_mut);
        var redirect_buffer: [1024]u8 = undefined;
        var response = try request.receiveHead(&redirect_buffer);
        const reader = response.reader(&.{});
        return try reader.allocRemaining(allocator, .unlimited);
    }

    fn deleteNoBody(self: *const DaytonaEnv, endpoint: []const u8, allocator: std.mem.Allocator) !void {
        const uri = try std.Uri.parse(endpoint);
        var client: Client = .{ .allocator = allocator };
        defer client.deinit();

        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
        defer allocator.free(auth_header);

        const headers: Request.Headers = .{
            .accept_encoding = .{ .override = "identity" },
            .authorization = .{ .override = auth_header },
        };

        var request: Request = try client.request(.DELETE, uri, .{ .headers = headers });
        defer request.deinit();

        try request.sendBodiless();
        var redirect_buffer: [1024]u8 = undefined;
        var response = try request.receiveHead(&redirect_buffer);
        const reader = response.reader(&.{});
        const body = try reader.allocRemaining(allocator, .unlimited);
        defer allocator.free(body);
    }

    fn executeSandboxCommand(self: *const DaytonaEnv, command: []const u8, allocator: std.mem.Allocator) !ExecuteResponse {
        const sandbox_id = self.container_id orelse return error.MissingContainerId;
        const endpoint = try std.fmt.allocPrint(
            allocator,
            "{s}/toolbox/{s}/toolbox/process/execute",
            .{ self.api_url, sandbox_id },
        );
        defer allocator.free(endpoint);

        const request_body = try std.fmt.allocPrint(
            allocator,
            "{f}",
            .{std.json.fmt(.{ .command = command }, .{})},
        );
        defer allocator.free(request_body);

        const response_text = try self.postJson(endpoint, request_body, allocator);
        defer allocator.free(response_text);

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_text, .{});
        defer parsed.deinit();

        const obj = parsed.value.object;
        const exit_code = obj.get("exitCode") orelse return error.InvalidDaytonaResponse;
        const result = obj.get("result") orelse return error.InvalidDaytonaResponse;

        return .{
            .exitCode = @intCast(exit_code.integer),
            .result = try allocator.dupe(u8, result.string),
        };
    }

    fn executeWrappedPython(self: *const DaytonaEnv, code: []const u8, allocator: std.mem.Allocator) !WrappedPythonResult {
        const text_encoder = std.base64.standard.Encoder;

        const code_b64_len = text_encoder.calcSize(code.len);
        const code_b64 = try allocator.alloc(u8, code_b64_len);
        defer allocator.free(code_b64);
        _ = text_encoder.encode(code_b64, code);

        const context_text = self.context orelse "";
        const context_b64_len = text_encoder.calcSize(context_text.len);
        const context_b64 = try allocator.alloc(u8, context_b64_len);
        defer allocator.free(context_b64);
        _ = text_encoder.encode(context_b64, context_text);

        const runner_script = try std.fmt.allocPrint(
            allocator,
            \\import base64
            \\import base64
            \\import contextlib
            \\import io
            \\import json
            \\import os
            \\import pickle
            \\import re
            \\import traceback
            \\
            \\state_path = "/tmp/omni_rlm_state.pkl"
            \\stored = {{}}
            \\if os.path.exists(state_path):
            \\    try:
            \\        with open(state_path, "rb") as f:
            \\            stored = pickle.load(f)
            \\    except Exception:
            \\        stored = {{}}
            \\
            \\if "context" not in stored:
            \\    stored["context"] = base64.b64decode("{s}").decode("utf-8", errors="ignore")
            \\
            \\final_var_pattern = r"^\\s*FINAL(_VAR)?\\((.*?)\\)"
            \\def FINAL_VAR(name):
            \\    variable_name = str(name).strip().strip("\"'")
            \\    return str(scope[variable_name]) if variable_name in scope else None
            \\
            \\def FINAL(name):
            \\    return str(name)
            \\
            \\scope = dict(stored)
            \\scope["FINAL"] = FINAL
            \\scope["FINAL_VAR"] = FINAL_VAR
            \\scope["re"] = re
            \\scope["final_var_pattern"] = final_var_pattern
            \\
            \\source = base64.b64decode("{s}").decode("utf-8", errors="ignore")
            \\stdout_io = io.StringIO()
            \\stderr_io = io.StringIO()
            \\exit_code = 0
            \\with contextlib.redirect_stdout(stdout_io), contextlib.redirect_stderr(stderr_io):
            \\    try:
            \\        exec(source, scope)
            \\    except Exception:
            \\        traceback.print_exc()
            \\        exit_code = 1
            \\
            \\persisted = {{}}
            \\for key, value in scope.items():
            \\    if key.startswith("__"):
            \\        continue
            \\    if key in ("FINAL", "FINAL_VAR", "re", "final_var_pattern"):
            \\        continue
            \\    try:
            \\        pickle.dumps(value)
            \\        persisted[key] = value
            \\    except Exception:
            \\        pass
            \\
            \\with open(state_path, "wb") as f:
            \\    pickle.dump(persisted, f)
            \\
            \\print(json.dumps({{"stdout": stdout_io.getvalue(), "stderr": stderr_io.getvalue(), "exit_code": exit_code}}))
        ,
            .{ context_b64, code_b64 },
        );

        const runner_b64_len = text_encoder.calcSize(runner_script.len);
        const runner_b64 = try allocator.alloc(u8, runner_b64_len);
        defer allocator.free(runner_b64);
        _ = text_encoder.encode(runner_b64, runner_script);

        const command = try std.fmt.allocPrint(
            allocator,
            "python3 -c \"import base64;exec(base64.b64decode('{s}').decode('utf-8'))\"",
            .{runner_b64},
        );
        defer {
            allocator.free(command);
            allocator.free(runner_script);
        }

        const response = try self.executeSandboxCommand(command, allocator);
        defer allocator.free(response.result);

        if (response.exitCode != 0) {
            return error.DaytonaCommandFailed;
        }

        const parsed = std.json.parseFromSlice(WrappedPythonResult, allocator, response.result, .{}) catch |err| {
            std.debug.print("\nDaytona wrapped execution parse failed. Raw result:\n{s}\n", .{response.result});
            return err;
        };
        defer parsed.deinit();

        return .{
            .stdout = try allocator.dupe(u8, parsed.value.stdout),
            .stderr = try allocator.dupe(u8, parsed.value.stderr),
            .exit_code = parsed.value.exit_code,
        };
    }

    /// Initialize the Daytona environment
    ///
    /// Creates a new sandbox container via the Daytona API.
    /// The container ID is stored for subsequent operations.
    ///
    /// ## Parameters
    /// - `kwargs`: JSON string with configuration (api_url, api_key)
    /// - `prompt`: The user prompt/context
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Errors
    /// Returns error if container creation fails
    pub fn init(self: *DaytonaEnv, kwargs: []const u8, prompt: []const u8, allocator: std.mem.Allocator) !void {
        const init_code =
            \\import re
            \\final_var_pattern = r"^\\s*FINAL(_VAR)?\\((.*?)\\)"
            \\def FINAL_VAR(name):
            \\    variable_name = name.strip().strip("\"'")
            \\    if variable_name in globals():
            \\        return str(globals()[variable_name])
            \\    return None
            \\
            \\def FINAL(name):
            \\    return str(name)
        ;

        const parsed: std.json.Parsed(DaytonaEnv) = try std.json.parseFromSlice(DaytonaEnv, allocator, kwargs, .{});
        defer parsed.deinit();
        self.* = parsed.value;
        self.context = prompt;

        errdefer {
            if (self.container_id) |id| {
                allocator.free(id);
                self.container_id = null;
            }
            if (self.api_key_owned) {
                allocator.free(self.api_key);
                self.api_key_owned = false;
            }
            if (self.api_url_owned) {
                allocator.free(self.api_url);
                self.api_url_owned = false;
            }
        }

        if (self.api_key.len == 0) {
            var daytona_cfg = config_env.load_daytona_env_config(allocator, ".env") catch return error.MissingDaytonaApiKey;
            defer daytona_cfg.deinit(allocator);
            self.api_key = try allocator.dupe(u8, daytona_cfg.api_key);
            self.api_key_owned = true;
            if (std.mem.eql(u8, self.api_url, "https://app.daytona.io/api")) {
                self.api_url = try allocator.dupe(u8, daytona_cfg.api_url);
                self.api_url_owned = true;
            }
        }

        const endpoint = try std.fmt.allocPrint(allocator, "{s}/sandbox", .{self.api_url});
        defer allocator.free(endpoint);

        const response_text = try self.postJson(endpoint, "{}", allocator);
        defer allocator.free(response_text);

        const parsed_response = try std.json.parseFromSlice(std.json.Value, allocator, response_text, .{});
        defer parsed_response.deinit();

        const response_id = parsed_response.value.object.get("id") orelse return error.InvalidDaytonaResponse;
        self.container_id = try allocator.dupe(u8, response_id.string);

        const setup_result = try self.executeWrappedPython(init_code, allocator);
        defer allocator.free(setup_result.stdout);
        defer allocator.free(setup_result.stderr);

        std.debug.print("\nContainer: {s} created\n", .{self.container_id.?});
    }

    /// Deinitialize the Daytona environment
    ///
    /// Deletes the sandbox container and frees associated resources.
    ///
    /// ## Parameters
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Errors
    /// Returns error if container deletion fails
    pub fn deinit(self: *DaytonaEnv, allocator: std.mem.Allocator) !void {
        if (self.container_id) |id| {
            const endpoint = try std.fmt.allocPrint(allocator, "{s}/sandbox/{s}", .{ self.api_url, id });
            defer allocator.free(endpoint);
            try self.deleteNoBody(endpoint, allocator);
            std.debug.print("\nContainer: {s} deleted\n", .{id});
            allocator.free(id);
            self.container_id = null;
        }
        if (self.api_key_owned) {
            allocator.free(self.api_key);
            self.api_key_owned = false;
        }
        if (self.api_url_owned) {
            allocator.free(self.api_url);
            self.api_url_owned = false;
        }
    }

    /// Execute code in the Daytona sandbox
    ///
    /// Runs the code in the sandbox container via API call.
    ///
    /// ## Parameters
    /// - `code`: Source code to execute
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// Process execution result with stdout, stderr, and exit status
    ///
    /// ## Errors
    /// Returns error if code execution fails
    pub fn execute_code(self: *const DaytonaEnv, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult {
        const result = try self.executeWrappedPython(code, allocator);
        const exit_code = std.math.clamp(result.exit_code, 0, 255);
        return .{
            .term = .{ .Exited = @intCast(exit_code) },
            .stdout = result.stdout,
            .stderr = result.stderr,
        };
    }

    /// Find final answer in model response
    ///
    /// Uses Daytona sandbox to parse FINAL() or FINAL_VAR() markers from text.
    ///
    /// ## Parameters
    /// - `text`: The model response text to parse
    /// - `allocator`: Memory allocator for allocations
    ///
    /// ## Returns
    /// The extracted final answer, or null if not found
    ///
    /// ## Errors
    /// Returns error if parsing fails
    pub fn find_final_answer(self: *const DaytonaEnv, text: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
        const text_encoder = std.base64.standard.Encoder;
        const text_b64_len = text_encoder.calcSize(text.len);
        const text_b64 = try allocator.alloc(u8, text_b64_len);
        defer allocator.free(text_b64);
        _ = text_encoder.encode(text_b64, text);

        const parser_code = try std.fmt.allocPrint(
            allocator,
            \\import base64
            \\find_final_answer_string = base64.b64decode("{s}").decode("utf-8", errors="ignore")
            \\matches = list(re.finditer(r"FINAL(_VAR)?\\((.*?)\\)", find_final_answer_string, re.DOTALL))
            \\if matches:
            \\    match = matches[-1]
            \\    variable_name = match.group(2).strip().strip('"').strip("'")
            \\    if variable_name in globals():
            \\        final_answer = FINAL_VAR(variable_name)
            \\    else:
            \\        final_answer = FINAL(variable_name)
            \\    if final_answer is not None:
            \\        final_answer = final_answer.strip()
            \\    print(final_answer if final_answer else None)
            \\else:
            \\    print(None)
        ,
            .{text_b64},
        );
        defer allocator.free(parser_code);

        const run_result = try self.executeWrappedPython(parser_code, allocator);
        defer allocator.free(run_result.stdout);
        defer allocator.free(run_result.stderr);

        const trimmed = std.mem.trim(u8, run_result.stdout, " \t\r\n");
        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "None")) {
            return try extractFinalFallback(text, allocator);
        } else {
            return try allocator.dupe(u8, trimmed);
        }
    }
};

test "DaytonaEnv execute_code" {
    const allocator = std.testing.allocator;
    var daytona_cfg = config_env.load_daytona_env_config(allocator, ".env") catch {
        std.debug.print("\nSkipping DaytonaEnv execute_code test due to missing daytona api_key.\n", .{});
        return error.SkipZigTest;
    };
    defer daytona_cfg.deinit(allocator);

    const kwargs = try std.fmt.allocPrint(
        allocator,
        "{{\"api_url\": \"{s}\", \"api_key\": \"{s}\"}}",
        .{ daytona_cfg.api_url, daytona_cfg.api_key },
    );
    defer allocator.free(kwargs);

    var env = DaytonaEnv{};
    try env.init(kwargs, "This is a prompt", allocator);
    const code = "print(context)\nprint('Hello from DaytonaEnv')";
    const result = try env.execute_code(code, allocator);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try std.testing.expectEqualStrings("This is a prompt\nHello from DaytonaEnv\n", result.stdout);
    try env.deinit(allocator);
}
