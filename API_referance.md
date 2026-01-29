# 📚 API Reference

## Core Types

### RLMMetadata - Configuration Metadata

Stores configuration metadata for the RLM session, including model settings, recursion limits, and backend configuration.

#### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `root_model` | `[]const u8` | - | Name of the language model being used |
| `max_depth` | `u32` | - | Maximum depth for recursive calls |
| `max_iterations` | `u32` | - | Maximum number of iterations allowed per session |
| `backend` | `[]const u8` | - | Backend service identifier (e.g., "openai") |
| `backend_kwargs` | `[]const u8` | - | JSON string with backend configuration (API key, base URL, model name) |
| `environment_type` | `[]const u8` | - | Type of environment configuration (e.g., "local") |
| `environment_kwargs` | `[]const u8` | - | JSON string with additional environment arguments |
| `other_backends` | `?[]const u8` | `null` | Optional alternative backend services for fallback |

#### Example

```zig
const metadata = RLMMetadata{
    .root_model = "gpt-4",
    .max_depth = 5,
    .max_iterations = 100,
    .backend = "openai",
    .backend_kwargs = 
    \\{"api_key":"sk-xxx","base_url":"https://api.openai.com/v1/chat/completions"}
    ,
    .environment_type = "local",
    .environment_kwargs = "{}",
    .other_backends = null,
};
```

### QueryMetadata - Query Context Tracking

Tracks context information for each query, including length metrics and type information. Must be initialized and deinitialized.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `context_length` | `[]const u32` | Array of lengths for each context segment |
| `context_total_length` | `u32` | Total length across all context segments |
| `context_type` | `[]const u8` | Type of context (currently supports "str") |

#### Methods

##### `init(prompt: []const u8, allocator: std.mem.Allocator) QueryMetadata`

Initializes metadata from a prompt string.

**Parameters:**

- `prompt`: The input prompt text
- `allocator`: Memory allocator

**Returns:** Initialized QueryMetadata instance

##### `deinit(self: *QueryMetadata, allocator: std.mem.Allocator) void`

Frees allocated resources.

#### Example

```zig
const allocator = std.heap.page_allocator;
var query_meta = QueryMetadata.init("What is 2+2?", allocator);
defer query_meta.deinit(allocator);

std.debug.print("Context length: {d}\n", .{query_meta.context_total_length});
```

#### Notes

- Currently only supports string context type
- Automatically calculates total length from prompt
- Memory must be freed with `deinit()`

### RLMIteration - Single Iteration Data

Represents a single iteration in the RLM execution loop, including prompt, response, code execution, and timing information.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `prompt` | `[]Message` | Array of messages forming the conversation prompt |
| `response` | `[]const u8` | REPL-like response from the language model |
| `code_blocks` | `CodeBlock` | Extracted and executed code block from response |
| `final_answer` | `?[]const u8` | Optional final answer extracted from response |
| `iteration_time` | `i64` | Execution time for this iteration in milliseconds |

#### Methods

##### `format_iteration(self: *RLMIteration, allocator: std.mem.Allocator) ![]Message`

Formats the iteration into message array for next iteration.

**Returns:** Array of messages containing assistant response and system feedback  
**Errors:** Memory allocation errors

##### `find_final_answer(self: *RLMIteration, allocator: std.mem.Allocator) !void`

Searches for and extracts the final answer from the response using Python regex matching.

**Side Effects:** Sets `self.final_answer` if a final answer is found  
**Pattern:** Matches `FINAL(...)` or `FINAL_VAR(...)` in response text

#### Example

```zig
var iteration = RLMIteration{
    .prompt = &messages,
    .response = "The answer is FINAL(42)",
    .code_blocks = code_block,
    .final_answer = null,
    .iteration_time = 1500,
};

try iteration.find_final_answer(allocator);
if (iteration.final_answer) |answer| {
    std.debug.print("Found answer: {s}\n", .{answer});
}
```

### RLMChatCompletion - Completion Result

Represents the final result of an RLM completion request.

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `root_model` | `[]const u8` | Name of the model used for completion |
| `prompt` | `[]const u8` | Original input prompt |
| `response` | `[]const u8` | Final response from the model |
| `execution_time` | `i64` | Total execution time in milliseconds |

#### Example

```zig
const result = RLMChatCompletion{
    .root_model = "gpt-4",
    .prompt = "Calculate fibonacci(10)",
    .response = "The 10th Fibonacci number is 55",
    .execution_time = 2341,
};
```

### CodeBlock - Code Execution Result

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

### Message - Chat Message

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

#### Common Roles

- **`system`**: System instructions and context
- **`user`**: User queries and inputs
- **`assistant`**: Model responses and outputs

### EnvHandler - Code Execution Environment

Manages Python code execution in a persistent environment using dill session state.

#### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `mainfunc` | `[]const u8` | `"python_script/env_init.py"` | Path to the Python environment initialization script |
| `context` | `?[]const u8` | `null` | Optional additional context for execution |

#### Methods

##### `execute_code(self: *const EnvHandler, code: []const u8, allocator: std.mem.Allocator) !std.process.Child.RunResult`

Executes Python code in the managed environment.

**Parameters:**

- `code`: Python code to execute
- `allocator`: Memory allocator

**Returns:** `RunResult` with stdout, stderr, and exit status  
**Errors:** Process execution errors

#### Example

```zig
const env = EnvHandler{
    .mainfunc = "python_script/env_init.py",
    .context = null,
};

const code = 
\\for i in range(5):
\\    print(f"Iteration {i}")
;

const result = try env.execute_code(code, allocator);
defer allocator.free(result.stdout);
defer allocator.free(result.stderr);

std.debug.print("Output: {s}\n", .{result.stdout});
```

#### Notes

- Requires `python_script/env_init.py` to exist and initialize the Python environment
- Uses `dill` for session persistence across executions
- Code runs in a shared Python interpreter state

---

#### Main API

### ModelHandler - HTTP API Client

Handles direct HTTP communication with OpenAI-compatible API endpoints. Low-level client for making chat completion requests.

#### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `base_url` | `[]const u8` | `"https://dashscope.aliyuncs.com/..."` | API endpoint URL for chat completions |
| `api_key` | `[]const u8` | `""` | Authentication key for the API |
| `model_name` | `[]const u8` | `"qwen-plus"` | Name of the model to use |

#### Methods

##### `make_request(self: @This(), messages: []Message, allocator: std.mem.Allocator) ![]u8`

Sends a chat completion request to the configured API endpoint.

**Parameters:**

- `messages`: Array of `Message` structs forming the conversation
- `allocator`: Memory allocator

**Returns:** Response text from the model as a string  
**Errors:** Network errors, JSON parsing errors, HTTP errors

#### Example

```zig
const allocator = std.heap.page_allocator;

var model_handler = ModelHandler{
    .base_url = "https://api.openai.com/v1/chat/completions",
    .api_key = "sk-your-api-key-here",
    .model_name = "gpt-4",
};

const messages = try allocator.alloc(Message, 2);
defer allocator.free(messages);

messages[0] = Message{
    .role = "system",
    .content = "You are a helpful assistant.",
};
messages[1] = Message{
    .role = "user",
    .content = "What is the capital of France?",
};

const response = try model_handler.make_request(messages, allocator);
defer allocator.free(response);

std.debug.print("Response: {s}\n", .{response});
```

#### Request Format

The handler constructs a JSON request:

```json
{
  "model": "gpt-4",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "What is the capital of France?"}
  ]
}
```

#### Response Parsing

Automatically extracts the content from the API response structure:

```json
{
  "choices": [
    {
      "message": {
        "content": "The capital of France is Paris."
      }
    }
  ]
}
```

#### Notes

- Uses `std.http.Client` for HTTP communication
- Automatically handles JSON serialization and deserialization
- Sets `Content-Type: application/json` and `Authorization` headers
- Response is limited only by available memory (`.unlimited`)
- Compatible with OpenAI, Qwen, and other OpenAI-compatible APIs

### RLM - Main Orchestrator

#### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `backend` | `[]const u8` | `"openai"` | Backend service identifier |
| `backend_kwargs` | `[]const u8` | `"{}"` | JSON config for backend (API key, URL, model) |
| `environment` | `[]const u8` | `"local"` | Environment type configuration |
| `environment_kwargs` | `[]const u8` | `"{}"` | Additional environment arguments |
| `depth` | `u32` | `0` | Current recursion depth |
| `max_depth` | `u32` | `1` | Maximum allowed recursion depth |
| `max_iterations` | `u32` | `30` | Maximum iterations per completion |
| `custom_system_prompt` | `?[]const u8` | `null` | Override default system prompt |
| `other_backends` | `?[]const u8` | `null` | Fallback backend services |
| `other_backend_kwargs` | `?[]const u8` | `null` | Config for fallback backends |
| `logger` | `?RLMLogger` | `null` | Optional logger instance |

#### Methods

##### `init(allocator: std.mem.Allocator) !RLM`

Initializes the RLM instance with configured parameters.

**Returns:** Initialized RLM instance  
**Errors:** `error.OutOfMemory`, initialization errors

##### `deinit(self: *RLM) void`

Cleans up all resources used by the RLM instance.

##### `completion(self: *RLM, input_text: []u8, custom_prompt: ?[]const u8) !CompletionResult`

Generates a completion based on input text.

**Parameters:**

- `input_text`: The prompt/query to process
- `custom_prompt`: Optional override for system prompt

**Returns:** `CompletionResult` with response and execution time  
**Errors:** Network errors, API errors, parsing errors

##### `setup_prompt(self: *RLM, prompt: []u8, allocator: std.mem.Allocator) ![]u8`

Prepares the prompt for submission to the backend.

**Returns:** Formatted prompt string

### RLMLogger - Logging System

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `log_dir` | `[]const u8` | Directory for log file storage |
| `log_file_path` | `[]const u8` | Full path to the active log file |
| `iteration_count` | `u32` | Number of logged iterations |
| `metadata_logged` | `bool` | Whether metadata has been written |

#### Methods

##### `init(log_dir: []const u8, log_file_name: []const u8, allocator: std.mem.Allocator) !RLMLogger`

Creates and initializes a new logger instance.

**Parameters:**

- `log_dir`: Directory to store log files
- `log_file_name`: Base name for the log file
- `allocator`: Memory allocator

**Returns:** Initialized logger  
**Errors:** File I/O errors, `error.OutOfMemory`

##### `log_iteration(self: *RLMLogger, iteration_data: []const u8) !void`

Logs data for a single iteration to the log file.

**Parameters:**

- `iteration_data`: JSON-formatted iteration data

**Errors:** File write errors

##### `log_metadata(self: *RLMLogger, metadata: Metadata) !void`

Logs metadata information about the RLM session.

**Parameters:**

- `metadata`: Metadata structure to log

**Errors:** Serialization errors, file write errors

##### `deinit(self: *RLMLogger, allocator: std.mem.Allocator) void`

Cleans up logger resources.

### QueryMetadata - Context Tracking

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `context_length` | `[]const u32` | Length of each context segment |
| `context_total_length` | `u32` | Total length across all segments |
| `context_type` | `[]const u8` | Type of context (e.g., "str") |

#### Methods

##### `init(prompt: []const u8, allocator: std.mem.Allocator) !QueryMetadata`

Initializes metadata from a prompt.

**Returns:** QueryMetadata instance  
**Errors:** `error.OutOfMemory`

##### `deinit(self: *QueryMetadata, allocator: std.mem.Allocator) void`

Frees allocated resources.

### Prompt Building Utilities

Helper functions for constructing system and user prompts with context awareness and iteration tracking.

#### `buildSystemPrompt(custom_system_prompt: ?[]const u8, query_metadata: QueryMetadata, allocator: std.mem.Allocator) ![]Message`

Constructs the system prompt and context description for the RLM session.

**Parameters:**

- `custom_system_prompt`: Optional custom system prompt (uses default RLM_SYSTEM_PROMPT if null)
- `query_metadata`: Metadata about the query context (length, type)
- `allocator`: Memory allocator

**Returns:** Array of 2 messages (system prompt + assistant info)  
**Errors:** `error.OutOfMemory`

**Notes:**

- Must call `ReleaseMessageArray()` to free allocated memory
- Default system prompt includes REPL instructions and reasoning strategies
- Context info message format: "Your context is a {type} with {length} total characters..."

---

#### `buildUserPrompt(root_prompt: ?[]const u8, iteration: u32, allocator: std.mem.Allocator) ![]Message`

Builds user prompts that vary based on iteration number to guide the model's reasoning process.

**Parameters:**

- `root_prompt`: Optional original user query to include in prompt
- `iteration`: Current iteration number (0-based)
- `allocator`: Memory allocator

**Returns:** Array containing a single user message  
**Errors:** `error.OutOfMemory`

**Behavior:**

- **Iteration 0**: Adds safeguard preventing immediate final answers, encourages exploration
- **Iteration 1+**: Reminds model of previous REPL interactions

**Example:**

```zig
const allocator = std.heap.page_allocator;

// First iteration
const first_prompt = try buildUserPrompt("What is 2+2?", 0, allocator);
defer ReleaseMessageArray(first_prompt, allocator);
// Includes: "You have not interacted with the REPL environment yet..."

// Subsequent iteration
const next_prompt = try buildUserPrompt("What is 2+2?", 1, allocator);
defer ReleaseMessageArray(next_prompt, allocator);
// Includes: "The history before is your previous interactions..."
```

**Notes:**

- Must call `ReleaseMessageArray()` to free allocated memory
- Iteration 0 prevents premature final answers
- Encourages step-by-step thinking and REPL usage

---

#### `ReleaseMessageArray(messages: []Message, allocator: std.mem.Allocator) void`

Safely deallocates a message array and all message content.

**Parameters:**

- `messages`: Array of messages to free
- `allocator`: The allocator used to create the messages

**Usage:**

```zig
const messages = try buildUserPrompt(null, 0, allocator);
defer ReleaseMessageArray(messages, allocator);
```

**Notes:**

- Frees both message content strings and the message array itself
- Should be called for all messages created by prompt building functions

### Parsing Utilities

#### `find_code_blocks(text: []const u8, allocator: std.mem.Allocator) ![]const u8`

Extracts code blocks with repl tag from response text.

**Returns:** code block strings  
