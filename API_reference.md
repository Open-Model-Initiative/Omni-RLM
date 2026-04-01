# API Reference

## Core Types

## Config Helpers

### Backend `.env` Configuration

Typed backend configuration loaded from a `.env`-style file.

#### Fields

| Field        | Type         | Description                        |
| ------------ | ------------ | ---------------------------------- |
| `api_key`    | `[]const u8` | API key/token for backend requests |
| `base_url`   | `[]const u8` | Chat completion endpoint URL       |
| `model_name` | `[]const u8` | Model name to request              |

#### Methods

##### `deinit(self: *backendKwargs, allocator: std.mem.Allocator) void`

Frees all allocated fields in the config.

---

### `backendKwargs.deinit` - Free Backend Configuration

```zig
pub fn deinit(self: *backendKwargs, allocator: std.mem.Allocator) void
```

Frees all allocated string fields (`api_key`, `base_url`, `model_name`).

#### Example

```zig
var kwargs = backendKwargs{
    .api_key = try allocator.dupe(u8, "sk-..."),
    .base_url = try allocator.dupe(u8, "https://api.example.com/v1/chat/completions"),
    .model_name = try allocator.dupe(u8, "gpt-4"),
};
defer kwargs.deinit(allocator);
```

### `load_backend_env_config(allocator: std.mem.Allocator, env_path: []const u8) !backendKwargs`

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
- Supports `${VAR}` and `$VAR` environment-variable substitution.
- Returns `error.MissingRequiredEnvKey` if any required key is missing.

### `backendKwargs` - Backend Configuration

Typed backend configuration passed to the model handler.

#### Fields

| Field        | Type         | Description                                            |
| ------------ | ------------ | ------------------------------------------------------ |
| `api_key`    | `[]const u8` | API key or token to send in the `Authorization` header |
| `base_url`   | `[]const u8` | Chat completion endpoint URL                           |
| `model_name` | `[]const u8` | Model name to request                                  |

#### Example

```zig
const kwargs = backendKwargs{
  .api_key = "sk-...",
  .base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
  .model_name = "qwen3",
};
```

### `RLMMetadata` - Configuration Metadata

Stores configuration metadata for the RLM session, including model settings, chunk-processing limits, and backend configuration.

#### Fields

| Field                | Type            | Default    | Description                                             |
| -------------------- | --------------- | ---------- | ------------------------------------------------------- |
| `root_model`         | `[]const u8`    | -          | Name of the language model being used                   |
| `max_depth`          | `u32`           | `1`        | Maximum depth for fallback behavior                     |
| `max_iterations`     | `u32`           | `10`       | Maximum number of chunk-processing iterations           |
| `backend`            | `[]const u8`    | `"openai"` | Backend service identifier (only support "openai" now)  |
| `backend_kwargs`     | `backendKwargs` | -          | Typed backend configuration                             |
| `environment_type`   | `?[]const u8`   | `null`     | Environment type (currently `"local"`)                  |
| `environment_kwargs` | `[]const u8`    | `"{}"`     | JSON string with environment arguments                  |
| `other_backends`     | `?[]const u8`   | `null`     | Optional alternative backend services(not used for now) |

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

| Field                  | Type          | Description                                              |
| ---------------------- | ------------- | -------------------------------------------------------- |
| `context_length`       | `[]const u32` | Array of lengths for each context segment                |
| `context_total_length` | `u32`         | Total length across all context segments                 |
| `context_type`         | `[]const u8`  | Type of context (for example `"str"` or `"chunked_str"`) |

#### Methods

##### `init(prompt: []const u8, allocator: std.mem.Allocator) QueryMetadata`

Initializes metadata from a prompt string.

##### `initChunked(material: []const u8, chunk_size: usize, allocator: std.mem.Allocator) !QueryMetadata`

Initializes metadata for chunked long-form material.

##### `deinit(self: *QueryMetadata, allocator: std.mem.Allocator) void`

Frees allocated resources.

#### Notes

- `init()` is useful for single-string metadata.
- `initChunked()` is used by the long-text pipeline to describe chunked material.
- Memory must be freed with `deinit()`.

### `Message` - Chat Message

Represents a single message in a chat conversation.

#### Fields

| Field     | Type         | Default  | Description                                    |
| --------- | ------------ | -------- | ---------------------------------------------- |
| `role`    | `[]const u8` | `"user"` | Message role: "user", "assistant", or "system" |
| `content` | `[]const u8` | `""`     | Message content text                           |

#### Example

```zig
const messages = [_]Message{
  .{ .role = "system", .content = "You are a helpful assistant." },
  .{ .role = "user", .content = "What is 2+2?" },
  .{ .role = "assistant", .content = "2+2 equals 4." },
};
```

### `RLMIteration` - Single Iteration Data

Represents a single iteration in the long-text execution loop, including prompt, response, chunk metadata, and timing information.

#### Fields

| Field             | Type                     | Description                                            |
| ----------------- | ------------------------ | ------------------------------------------------------ |
| `prompt`          | `std.ArrayList(Message)` | ArrayList of messages forming the conversation prompt  |
| `response`        | `[]const u8`             | Updated running summary returned by the language model |
| `chunk_index`     | `u32`                    | Index of the processed material chunk                  |
| `total_chunks`    | `u32`                    | Total number of material chunks                        |
| `chunk_length`    | `u32`                    | Character length of the processed chunk                |
| `running_summary` | `[]const u8`             | Cumulative summary after this iteration                |
| `iteration_time`  | `i64`                    | Execution time for this iteration in milliseconds      |

### `RLMChatCompletion` - Completion Result

Represents the final result of an RLM completion request.

#### Fields

| Field            | Type         | Description                           |
| ---------------- | ------------ | ------------------------------------- |
| `root_model`     | `[]const u8` | Name of the model used for completion |
| `prompt`         | `[]const u8` | Original input prompt                 |
| `response`       | `[]const u8` | Final response from the model         |
| `execution_time` | `i64`        | Total execution time in milliseconds  |

---

## Environment API

### env_type - Environment Selector

Supported environment backends:

- `local`

### EnvHandler - Material Access Environment

Runtime-dispatched environment wrapper. Initialization stores the long material and exposes chunked reads.

#### Methods

##### `init(self: *EnvHandler, etype: env_type, kwargs: []const u8, material: []const u8, allocator: std.mem.Allocator) !void`

Initializes the selected environment and stores the material as context.

##### `count_chunks(self: *const EnvHandler, chunk_size: usize) usize`

Returns the number of chunks for the stored material.

##### `read_chunk(self: *const EnvHandler, chunk_index: usize, chunk_size: usize, allocator: std.mem.Allocator) ![]u8`

Reads a single chunk of material from the stored source text. Uses smart boundary alignment (sentence-aware chunking).

##### `read_chunk_with_overlap(self: *const EnvHandler, chunk_index: usize, chunk_size: usize, overlap_size: usize, allocator: std.mem.Allocator) ![]u8`

Reads a chunk with overlap from the previous chunk for context preservation.

**Parameters:**
- `chunk_index`: Index of the chunk to read
- `chunk_size`: Target size of the chunk
- `overlap_size`: Number of bytes to include from the previous chunk
- `allocator`: Memory allocator

**Returns:** Combined content with overlap from previous chunk

##### `set_overlap(self: *EnvHandler, overlap: usize) void`

Sets the default overlap size for the environment.

##### `deinit(self: *EnvHandler, allocator: std.mem.Allocator) !void`

Shuts down the environment and releases resources.

#### Example

```zig
var env: EnvHandler = undefined;
const etype = std.meta.stringToEnum(env_type, "local") orelse env_type.local;
try env.init(etype, "{}", "very long source material", allocator);
const chunk = try env.read_chunk(0, 1024, allocator);
defer allocator.free(chunk);
try env.deinit(allocator);
```

### `LocalEnv` - Local Material Store

#### Fields

| Field           | Type          | Default | Description                                              |
| --------------- | ------------- | ------- | -------------------------------------------------------- |
| `context`       | `?[]const u8` | `null`  | Source material stored for chunked reading               |
| `overlap_size`  | `usize`       | `100`   | Overlap size in bytes between consecutive chunks         |

#### Smart Chunking Features

**Sentence Boundary Alignment**

The `LocalEnv` now supports intelligent chunking that automatically aligns chunk boundaries to sentence boundaries:

- **Supported punctuation**: `.` `!` `?` (English) and `。` `！` `？` (Chinese)
- **Behavior**: When a raw chunk boundary falls mid-sentence, the system searches forward (up to chunk size or 1000 bytes) for the next sentence boundary
- **Fallback**: If no boundary is found ahead, searches backward within the same range
- **Benefit**: Prevents cutting sentences in half, improving coherence of processed chunks

**Overlap Support**

Chunks can include overlap from the previous chunk to preserve context:

- **Configuration**: Set `overlap_size` (default: 100 bytes)
- **Method**: Use `read_chunk_with_overlap()` instead of `read_chunk()`
- **Benefit**: Ensures context continuity across chunk boundaries, especially useful when a sentence spans across chunks

#### Methods

##### `setOverlap(self: *LocalEnv, overlap: usize) void`

Sets the overlap size for context preservation between chunks.

##### `read_chunk_with_overlap(self: *const LocalEnv, chunk_index: usize, chunk_size: usize, allocator: std.mem.Allocator) ![]u8`

Reads a chunk including overlap content from the previous chunk.

**Returns:** Combined content of `[overlap_from_previous] + [current_chunk]`

#### Notes

- The local environment stores the full material string in memory.
- Chunks are read lazily via `read_chunk` or `read_chunk_with_overlap` during iteration.
- Smart boundary alignment is applied automatically to both regular and overlap-enabled chunk reading.

---

## Main API

### `ModelHandler` - HTTP API Client

Handles direct HTTP communication with OpenAI-compatible API endpoints. Low-level client for making chat completion requests.

#### Fields

| Field        | Type         | Default | Description                              |
| ------------ | ------------ | ------- | ---------------------------------------- |
| `base_url`   | `[]const u8` | -       | API base URL or full chat completion URL |
| `api_key`    | `[]const u8` | -       | Authentication value for the API         |
| `model_name` | `[]const u8` | -       | Name of the model to use                 |

#### `RequestConfig` - Request Runtime Options

| Field             | Type   | Default | Description                                                                 |
| ----------------- | ------ | ------- | --------------------------------------------------------------------------- |
| `stream`          | `bool` | `false` | Enables server-sent-event style streaming responses                         |
| `enable_thinking` | `bool` | `false` | Prints `reasoning_content` (when provided by backend) before answer content |

#### Methods

##### `make_request(self: @This(), messages: std.ArrayList(Message), allocator: std.mem.Allocator, config: RequestConfig) ![]u8`

Sends a chat completion request to the configured API endpoint.

**Parameters:**

- `messages`: `std.ArrayList(Message)` conversation payload (request body uses `messages.items`)
- `allocator`: Memory allocator
- `config`: Runtime flags for streaming and thinking output

**Returns:** Response text from the model as a string (caller owns memory)

**Behavior:**

- If `base_url` does not end with `/chat/completions`, the suffix is appended automatically.
- If `api_key` does not start with `Bearer `, the prefix is added automatically.
- When `config.stream = true`, streamed deltas are parsed from `data: ...` lines and concatenated into the returned answer.
- When `config.enable_thinking = true`, `reasoning_content` is printed to stdout, but only `content` is returned.

**Errors:** Returns errors for request/transport failures (`error.HttpRequestFailed`) and invalid non-stream JSON responses (`error.InvalidResponse`).

### `RLM` - Main Orchestrator

#### Fields

| Field                  | Type                | Default    | Description                                 |
| ---------------------- | ------------------- | ---------- | ------------------------------------------- |
| `backend`              | `[]const u8`        | `"openai"` | Backend service identifier                  |
| `backend_kwargs`       | `backendKwargs`     | -          | Backend configuration (API key, URL, model) |
| `environment`          | `[]const u8`        | `"local"`  | Material environment configuration          |
| `environment_kwargs`   | `[]const u8`        | `"{}"`     | JSON config for environment                 |
| `depth`                | `u32`               | `0`        | Current processing depth                    |
| `max_depth`            | `u32`               | `1`        | Maximum allowed fallback depth              |
| `max_iterations`       | `u32`               | `8`        | Maximum chunk iterations per completion     |
| `material_chunk_size`  | `usize`             | `16384`    | Preferred size of each material chunk       |
| `chunk_overlap`        | `usize`             | `0`        | Overlap bytes between chunks for context preservation |
| `custom_system_prompt` | `?[]const u8`       | `null`     | Override default system prompt              |
| `other_backends`       | `?[]const u8`       | `null`     | Fallback backend services                   |
| `other_backend_kwargs` | `?[]const u8`       | `null`     | Config for fallback backends                |
| `logger`               | `?RLMLogger`        | `null`     | Optional logger instance                    |
| `allocator`            | `std.mem.Allocator` | -          | Allocator used by the RLM instance          |

#### Methods

##### `init(self: *RLM) !void`

Initializes the RLM instance and logs metadata if a logger is present.

##### `deinit(self: *RLM) void`

Cleans up all resources used by the RLM instance.

##### `completion(self: *RLM, root_prompt: []const u8, material_path: []const u8) !RLMChatCompletion`

Generates a final answer by loading material from a file path and traversing it chunk by chunk.

**Parameters:**

- `root_prompt`: The root question to answer
- `material_path`: Path to the long-form material file used as evidence

**Returns:** `RLMChatCompletion` with response and execution time

**Behavior:**

- Builds the system prompt using `QueryMetadata` and `buildSystemPrompt`.
- Reads the material from `material_path` inside the RLM execution flow.
- Splits material into chunks using **smart boundary alignment** (sentence-aware chunking).
- **Smart Chunking**: Automatically aligns chunk boundaries to sentence boundaries (supports English `. ! ?` and Chinese `。！？` punctuation).
- **Overlap Support**: When `chunk_overlap > 0`, each chunk (except the first) includes `chunk_overlap` bytes from the previous chunk for context preservation.
- Iteratively updates a running summary across all chunks.
- Iterative calls use streaming mode (`stream = true`) and disable thinking output (`enable_thinking = false`).
- Produces the final answer from the accumulated running summary.
- If `max_depth` is exceeded, falls back to a single direct call over the full material.

**Output format:**

- The final output format is driven by `root_prompt`.
- If `root_prompt` explicitly asks for executable code, the final response will try to return code rather than prose.
- For best results, state the constraint directly in the root question, for example: `Return code only, no Markdown fences, no explanation.`

**Example:**

```zig
const root = "What conclusion does the report support?";
const material_path = "report.txt";

const result = try rlm.completion(root, material_path);
defer allocator.free(result.response);
```

---

## Prompt Utilities

### Constants

- `RLM_SYSTEM_PROMPT`

### `buildSystemPrompt(custom_system_prompt: ?[]const u8, query_metadata: QueryMetadata, allocator: std.mem.Allocator) !std.ArrayList(Message)`

Constructs the system prompt and context description for the RLM session.

**Returns:** ArrayList of 2 messages (system prompt + assistant info)

**Notes:**

- Must call `ReleaseMessageArray()` to free message content.
- Must call `deinit()` on the ArrayList to free the list itself.

### `buildUserPrompt(input_parameters: struct { root_prompt: []const u8, chunk: []const u8, chunk_index: u32, total_chunks: u32, running_summary: ?[]const u8 = null }, allocator: std.mem.Allocator) !std.ArrayList(Message)`

Builds the per-chunk prompt used for incremental synthesis.

**Example:**

```zig
const allocator = std.heap.page_allocator;

var first_prompt = try buildUserPrompt(.{
  .root_prompt = "What is 2+2?",
  .chunk = "The document states that 2+2 equals 4.",
  .chunk_index = 0,
  .total_chunks = 1,
}, allocator);
defer first_prompt.deinit(allocator);
defer ReleaseMessageArray(first_prompt, allocator);
```

### `buildFinalPrompt(root_prompt: []const u8, running_summary: []const u8, allocator: std.mem.Allocator) !std.ArrayList(Message)`

Builds the final aggregation prompt used after all chunks have been processed.

**Example:**

```zig
var final_prompt = try buildFinalPrompt(
  "What is the report's conclusion?",
  "Across all chunks, the report attributes the outage to a failed migration.",
  allocator,
);
defer final_prompt.deinit(allocator);
defer ReleaseMessageArray(final_prompt, allocator);
```

### `ReleaseMessageArray(messages: std.ArrayList(Message), allocator: std.mem.Allocator) void`

Safely deallocates all message content in the ArrayList. Note: This does NOT deallocate the ArrayList itself - you must call `deinit()` on the ArrayList separately.

---

## Logging

### `RLMLogger` - Logging System

#### Fields

| Field             | Type         | Description                       |
| ----------------- | ------------ | --------------------------------- |
| `log_dir`         | `[]const u8` | Directory for log file storage    |
| `log_file_path`   | `[]const u8` | Full path to the active log file  |
| `iteration_count` | `u32`        | Number of logged iterations       |
| `metadata_logged` | `bool`       | Whether metadata has been written |

#### Methods

##### `init(log_dir: []const u8, file_name: []const u8, allocator: std.mem.Allocator) !RLMLogger`

Creates and initializes a new logger instance.

Creates the log directory if it doesn't exist and generates a unique log filename with timestamp and random ID in the format: `{file_name}_{timestamp}_{random_id}.jsonl`

##### `log_iteration(self: *RLMLogger, iteration_data: RLMIteration, allocator: std.mem.Allocator) !void`

Logs data for a single iteration to the log file, with added `type`, `iteration`, and `timestamp` fields.

**Typical log fields:**

```json
{
  "type": "iteration",
  "iteration": 3,
  "chunk_index": 2,
  "total_chunks": 12,
  "chunk_length": 8192,
  "response": "Updated running summary for chunk 3.",
  "running_summary": "Current cumulative summary after chunk 3.",
  "iteration_time": 428,
  "timestamp": "2026-03-25T11:30:00.000000"
}
```

##### `log_metadata(self: *RLMLogger, metadata: RLMMetadata, allocator: std.mem.Allocator) !void`

Logs metadata for the RLM session (only once per logger instance).

**Security Note**: The API key is automatically stripped from the logged output for security.

**Typical metadata fields:**

```json
{
  "type": "metadata",
  "root_model": "qwen-plus",
  "backend": "openai",
  "max_depth": 1,
  "max_iterations": 16,
  "environment_type": "local",
  "timestamp": "2026-03-25T11:30:00.000000"
}
```

##### `log_completion(self: *RLMLogger, completion: RLMChatCompletion, allocator: std.mem.Allocator) !void`

Logs the final completion returned to the caller.

This entry is written after all chunk iterations complete, or after fallback mode returns a direct answer.

**Typical completion fields:**

```json
{
  "type": "completion",
  "root_model": "qwen3.5-plus",
  "prompt": "Based on this API reference, return a minimal directly executable Zig example showing how to call buildFinalPrompt.",
  "response": "const std = @import(\"std\");\n...",
  "execution_time": 14121,
  "timestamp": "2026-03-25T16:14:36.147378"
}
```

##### `deinit(self: *RLMLogger, allocator: std.mem.Allocator) void`

Cleans up logger resources.
