# API Reference

## Core Types

## Config Helpers

### `BackendEnvConfig` - `.env` Backend Configuration

Typed backend configuration loaded from a `.env`-style file.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `api_key` | `[]const u8` | API key/token for backend requests |
| `base_url` | `[]const u8` | Chat completion endpoint URL |
| `model_name` | `[]const u8` | Model name to request |

#### Methods

##### `deinit(self: *BackendEnvConfig, allocator: std.mem.Allocator) void`

Frees all allocated fields in the config.

### `load_backend_env_config(allocator: std.mem.Allocator, env_path: []const u8) !BackendEnvConfig`

Loads backend settings from a `.env`-style file.

#### Required keys

- `OMNIRLM_API_KEY` (or `DASHSCOPE_API_KEY` / `OPENAI_API_KEY`)
- `OMNIRLM_BASE_URL`
- `OMNIRLM_MODEL_NAME`

#### Example

```zig
const omni = @import("omni-rlm");
const config_env = omni.config_env;

const allocator = std.heap.page_allocator;
var cfg = try config_env.load_backend_env_config(allocator, ".env");
defer cfg.deinit(allocator);

var rlm: omni.RLM = .{
  .backend = "openai",
  .backend_kwargs = .{
    .api_key = cfg.api_key,
    .base_url = cfg.base_url,
    .model_name = cfg.model_name,
  },
  .allocator = allocator,
};
```

#### Notes

- Supports comments (`# ...`) and empty lines.
- Values wrapped in single or double quotes are unquoted.
- Returns `error.MissingRequiredEnvKey` if any required key is missing.

### `backendKwargs` - Backend Configuration

Typed backend configuration passed to the model handler.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `api_key` | `[]const u8` | API key or token to send in the `Authorization` header |
| `base_url` | `[]const u8` | Chat completion endpoint URL |
| `model_name` | `[]const u8` | Model name to request |

#### Example

```zig
const kwargs = backendKwargs{
  .api_key = "sk-...",
  .base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
  .model_name = "qwen3",
};
```

### `RLMMetadata` - Configuration Metadata

Stores configuration metadata for the RLM session, including model settings, recursion limits, and backend configuration.

#### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `root_model` | `[]const u8` | - | Name of the language model being used |
| `max_depth` | `u32` | `1` | Maximum depth for recursive calls |
| `max_iterations` | `u32` | `10` | Maximum number of iterations allowed per session |
| `backend` | `[]const u8` | `"openai"` | Backend service identifier (only support "openai" now) |
| `backend_kwargs` | `backendKwargs` | - | Typed backend configuration |
| `environment_type` | `?[]const u8` | `null` | Environment type (e.g., "local", "daytona") |
| `environment_kwargs` | `[]const u8` | `"{}"` | JSON string with environment arguments |
| `other_backends` | `?[]const u8` | `null` | Optional alternative backend services(not used for now) |

#### Example

```zig
const metadata = RLMMetadata{
  .root_model = "gpt-4",
  .max_depth = 5,
  .max_iterations = 100,
  .backend = "openai",
  .backend_kwargs = .{
    .api_key = "sk-...",
    .base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
    .model_name = "qwen3",
  },
  .environment_type = "local",
  .environment_kwargs = "{}",
  .other_backends = null,
};
```

### `QueryMetadata` - Query Context Tracking

Stores information for a query, including context length metrics and type information. Must be initialized and deinitialized.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `context_length` | `[]const u32` | Array of lengths for each context segment |
| `context_total_length` | `u32` | Total length across all context segments |
| `context_type` | `[]const u8` | Type of context (currently supports "str") |

#### Methods

##### `init(prompt: []const u8, allocator: std.mem.Allocator) QueryMetadata`

Initializes metadata from a prompt string.

##### `deinit(self: *QueryMetadata, allocator: std.mem.Allocator) void`

Frees allocated resources.

#### Notes

- Currently only supports string context type
- Automatically calculates total length from prompt
- Memory must be freed with `deinit()`

### `Message` - Chat Message

Represents a single message in a chat conversation.

#### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `role` | `[]const u8` | `"user"` | Message role: "user", "assistant", or "system" |
| `content` | `[]const u8` | `""` | Message content text |

#### Example

```zig
const messages = [_]Message{
  .{ .role = "system", .content = "You are a helpful assistant." },
  .{ .role = "user", .content = "What is 2+2?" },
  .{ .role = "assistant", .content = "2+2 equals 4." },
};
```

### `CodeBlock` - Code Execution Result

Stores a code block and its execution result from a REPL-like environment.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `code` | `[]const u8` | The source code that was executed |
| `result` | `std.process.Child.RunResult` | Execution result (stdout, stderr, exit code) |

#### Methods

##### `deinit(self: *CodeBlock, allocator: std.mem.Allocator) void`

Frees all allocated resources including code string and execution outputs.

#### Example

```zig
var code_block = CodeBlock{
  .code = try allocator.dupe(u8, "print('Hello')"),
  .result = execution_result,
};
defer code_block.deinit(allocator);
```

#### Notes

- `result.stdout`: Standard output from code execution
- `result.stderr`: Standard error from code execution
- `result.term`: Process termination status

### `RLMIteration` - Single Iteration Data

Represents a single iteration in the RLM execution loop, including prompt, response, code execution, and timing information.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `prompt` | `std.ArrayList(Message)` | ArrayList of messages forming the conversation prompt |
| `response` | `[]const u8` | REPL-like response from the language model |
| `code_blocks` | `[]CodeBlock` | Extracted and executed code blocks from response |
| `final_answer` | `?[]const u8` | Optional final answer extracted from response |
| `iteration_time` | `i64` | Execution time for this iteration in milliseconds |

#### Methods

##### `format_iteration(self: *RLMIteration, allocator: std.mem.Allocator) !std.ArrayList(Message)`

Formats the iteration into a message ArrayList for the next iteration. Each code block adds a user message containing the executed code and its stdout/stderr.

**Returns:** ArrayList of messages containing assistant response and system feedback

#### Notes

- Final answer extraction is handled by the environment (`EnvHandler.find_final_answer`).

### `RLMChatCompletion` - Completion Result

Represents the final result of an RLM completion request.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `root_model` | `[]const u8` | Name of the model used for completion |
| `prompt` | `[]const u8` | Original input prompt |
| `response` | `[]const u8` | Final response from the model |
| `execution_time` | `i64` | Total execution time in milliseconds |

---

## Environment API

### env_type - Environment Selector

Supported environment backends:

- `local`
- `daytona`

### EnvHandler - Code Execution Environment

Runtime-dispatched environment wrapper. Initialization uses a JSON string for backend-specific arguments.

#### Methods

##### `init(self: *EnvHandler, etype: env_type, kwargs: []const u8, prompt: []const u8, allocator: std.mem.Allocator) !void`

Initializes the selected environment and stores the prompt as context.

##### `execute_code(self: *const EnvHandler, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult`

Executes Python code in the environment and returns stdout/stderr/exit status.

##### `find_final_answer(self: *const EnvHandler, response: []const u8, allocator: std.mem.Allocator) !?[]const u8`

Extracts the final answer from a response using `FINAL(...)` or `FINAL_VAR(...)` patterns.

##### `deinit(self: *EnvHandler, allocator: std.mem.Allocator) !void`

Shuts down the environment and releases resources.

#### Example

```zig
var env: EnvHandler = undefined;
const etype = std.meta.stringToEnum(env_type, "local") orelse env_type.local;
try env.init(etype, "{\"mainfunc\": \"src/core/environment/local/env_init.py\"}", "", allocator);
const result = try env.execute_code("print('hello')", allocator);
defer {
  allocator.free(result.stdout);
  allocator.free(result.stderr);
}
try env.deinit(allocator);
```

### `LocalEnv` - Local Python Runner

#### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mainfunc` | `[]const u8` | `""` | Path to the python entry script |
| `context` | `?[]const u8` | `null` | Execution code passed to the REPL environment |

#### Notes

- Expects `mainfunc` to accept `(code, context)` arguments.
- Uses `src/core/environment/local/env_init.py` in examples/tests.

### `DaytonaEnv` - Remote Daytona Runner

#### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `api_url` | `[]const u8` | `"https://app.daytona.io/api"` | Daytona API base URL |
| `api_key` | `[]const u8` | `""` | Daytona API key |
| `context` | `?[]const u8` | `null` | Execution code passed to the REPL environment |
| `container_id` | `?[]const u8` | `null` | Existing container ID (optional) |

---

## Main API

### `ModelHandler` - HTTP API Client

Handles direct HTTP communication with OpenAI-compatible API endpoints. Low-level client for making chat completion requests.

#### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `base_url` | `[]const u8` | `"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"` | API endpoint URL for chat completions |
| `api_key` | `[]const u8` | `""` | Authentication value for the API |
| `model_name` | `[]const u8` | `"qwen-plus"` | Name of the model to use |

#### Methods

##### `make_request(self: @This(), messages: []Message, allocator: std.mem.Allocator) ![]u8`

Sends a chat completion request to the configured API endpoint.

**Parameters:**

- `messages`: Array of `Message` structs forming the conversation
- `allocator`: Memory allocator

**Returns:** Response text from the model as a string

### `RLM` - Main Orchestrator

#### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `backend` | `[]const u8` | `"openai"` | Backend service identifier |
| `backend_kwargs` | `backendKwargs` | - | Backend configuration (API key, URL, model) |
| `environment` | `[]const u8` | `"local"` | Environment type configuration |
| `environment_kwargs` | `[]const u8` | `"{}"` | JSON config for environment |
| `depth` | `u32` | `0` | Current recursion depth |
| `max_depth` | `u32` | `1` | Maximum allowed recursion depth |
| `max_iterations` | `u32` | `4` | Maximum iterations per completion |
| `custom_system_prompt` | `?[]const u8` | `null` | Override default system prompt |
| `other_backends` | `?[]const u8` | `null` | Fallback backend services |
| `other_backend_kwargs` | `?[]const u8` | `null` | Config for fallback backends |
| `logger` | `?RLMLogger` | `null` | Optional logger instance |
| `allocator` | `std.mem.Allocator` | - | Allocator used by the RLM instance |

#### Methods

##### `init(self: *RLM) !void`

Initializes the RLM instance and logs metadata if a logger is present.

##### `deinit(self: *RLM) void`

Cleans up all resources used by the RLM instance.

##### `completion(self: *RLM, prompt: []u8, root_prompt: ?[]u8) !RLMChatCompletion`

Generates a completion based on input text.

**Parameters:**

- `prompt`: The prompt/query to process
- `root_prompt`: Optional original prompt used in the first user prompt

**Returns:** `RLMChatCompletion` with response and execution time

**Behavior:**

- Builds the system prompt using `QueryMetadata` and `buildSystemPrompt`.
- Iteratively calls the backend, extracts ```repl``` code blocks, and executes them.
- Uses `EnvHandler.find_final_answer` to detect `FINAL(...)` or `FINAL_VAR(...)`.
- If `max_depth` is exceeded, falls back to a single direct call.
- If no final answer is found by `max_iterations`, requests a default final answer.

---

## Prompt Utilities

### Constants

- `RLM_SYSTEM_PROMPT`
- `USER_PROMPT`
- `USER_PROMPT_WITH_ROOT`

### `buildSystemPrompt(custom_system_prompt: ?[]const u8, query_metadata: QueryMetadata, allocator: std.mem.Allocator) !std.ArrayList(Message)`

Constructs the system prompt and context description for the RLM session.

**Returns:** ArrayList of 2 messages (system prompt + assistant info)

**Notes:**

- Must call `ReleaseMessageArray()` to free message content.
- Must call `deinit()` on the ArrayList to free the list itself.

### `buildUserPrompt(input_parameters: struct { root_prompt: ?[]const u8 = null, iteration: u32 = 0, context_count: u32 = 1, history_count: u32 = 0 }, allocator: std.mem.Allocator) !std.ArrayList(Message)`

Builds user prompts that vary based on iteration number, available contexts, and conversation history.

**Example:**

```zig
const allocator = std.heap.page_allocator;

var first_prompt = try buildUserPrompt(.{ .root_prompt = "What is 2+2?", .iteration = 0 }, allocator);
defer first_prompt.deinit(allocator);
defer ReleaseMessageArray(&first_prompt, allocator);

var followup = try buildUserPrompt(.{ .iteration = 1, .context_count = 2 }, allocator);
defer followup.deinit(allocator);
defer ReleaseMessageArray(&followup, allocator);
```

### `ReleaseMessageArray(messages: *std.ArrayList(Message), allocator: std.mem.Allocator) void`

Safely deallocates all message content in the ArrayList. Note: This does NOT deallocate the ArrayList itself - you must call `deinit()` on the ArrayList separately.

---

## Parsing Utilities

### `CodeToBeRun` - Code Block Structure

Represents an extracted code block with its language label and content.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `label` | `[]const u8` | The language tag of the code block (e.g., "python", "bash") |
| `code` | `[]const u8` | The actual code content inside the block |

### `find_code_blocks(input: []const u8, allocator: std.mem.Allocator) !std.ArrayList(CodeToBeRun)`

Extracts fenced code blocks (```language ... ```) from response text.

#### Example

```zig
var blocks = try find_code_blocks(response, allocator);
defer blocks.deinit(allocator);
for (blocks.items) |block| {
  std.debug.print("Language: {s}\n", .{block.label});
  std.debug.print("Code:\n{s}\n", .{block.code});
}
```

#### Notes

- Returns an `ArrayList` of `CodeToBeRun` structs, each containing the language label and code content
- The `label` field contains the language tag specified after the opening backticks (e.g., "python" from ```python)
- Both `label` and `code` slices reference the original `input` buffer
- Handles both Windows (\r\n) and Unix (\n) line endings
- Empty code blocks (consecutive closing backticks) are not included in results

---

## Logging

### `RLMLogger` - Logging System

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `log_dir` | `[]const u8` | Directory for log file storage |
| `log_file_path` | `[]const u8` | Full path to the active log file |
| `iteration_count` | `u32` | Number of logged iterations |
| `metadata_logged` | `bool` | Whether metadata has been written |

#### Methods

##### `init(log_dir: []const u8, file_name: []const u8, allocator: std.mem.Allocator) !RLMLogger`

Creates and initializes a new logger instance.

##### `log_iteration(self: *RLMLogger, iteration_data: RLMIteration, allocator: std.mem.Allocator) !void`

Logs data for a single iteration to the log file, with added `type`, `iteration`, and `timestamp` fields.

##### `log_metadata(self: *RLMLogger, metadata: RLMMetadata, allocator: std.mem.Allocator) !void`

Logs metadata for the RLM session (only once per logger instance).

##### `deinit(self: *RLMLogger, allocator: std.mem.Allocator) void`

Cleans up logger resources.
defer ReleaseMessageArray(next_prompt, allocator);
