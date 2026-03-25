# Omni-RLM - Agent Development Guide

## Project Overview

**Omni-RLM** is a high-performance long-text reasoning framework written in Zig. It answers root questions by traversing large material incrementally and synthesizing a final answer.

This is a Zig implementation of the [RLM paper](https://github.com/alexzhang13/rlm), providing a robust foundation for production-grade AI applications with type-safe, memory-efficient operations.

### Key Characteristics

- **Language**: Zig 0.15.2
- **License**: Apache License 2.0
- **Architecture**: Modular library with executable examples
- **Primary Use Case**: Long-text question answering with chunked material traversal

## Technology Stack

- **Build System**: Zig build system (`build.zig`, `build.zig.zon`)
- **Package Manager**: Zig package manager (zon file)
- **HTTP Client**: Zig standard library HTTP client
- **JSON**: Zig standard library JSON parsing/stringifying
- **External Dependencies**:
  - OpenAI-compatible backend API credentials

## Project Structure

```
Omni-RLM/
├── src/
│   ├── omni-rlm.zig                 # Public API exports (RLM, RLMLogger, config_env)
│   ├── test.zig                     # Test suite entry point
│   ├── core/                        # Core library implementation
│   │   ├── rlm.zig                  # Main RLM orchestrator struct and logic
│   │   ├── rlm_logger.zig           # Structured JSON logging system
│   │   ├── types.zig                # Type definitions (Message, RLMIteration, etc.)
│   │   ├── prompt.zig               # System prompt construction utilities
│   │   ├── Model_info.zig           # LLM API client (ModelHandler)
│   │   ├── config_env.zig           # .env configuration loader
│   │   └── environment/             # Material environments
│   │       ├── type.zig             # EnvHandler union and env_type enum
│   │       ├── local/               # Local material storage
│   │       │   └── local.zig        # LocalEnv implementation
│   └── example/                     # Example applications
│       ├── run.zig                  # Basic example runner
│       ├── quickstart.zig           # Quickstart test example
│       └── openclaw.zig             # OpenClaw-style autonomous agent
├── build.zig                        # Build configuration
├── build.zig.zon                    # Package manifest
├── .env.example                     # Environment configuration template
├── API_referance.md                 # Detailed API documentation
├── ROADMAP.md                       # Future development roadmap
└── README.md / README_CN.md         # User documentation
```

## Build Commands

```bash
# Build the project
zig build

# Run tests
zig build test

# Run specific test with filter
zig build test -- -Dtest-filter="test_name"

# Run the main example (requires .env file)
zig build run

# Run quickstart test
zig build quickstart

# Run OpenClaw example with custom prompt
zig build openclaw -- "Your task prompt here"

# Build in release mode (optimized)
zig build -Doptimize=ReleaseFast
```

## Testing Strategy

Tests are distributed across source files using Zig's built-in test framework:

1. **Unit tests**: Embedded in each source file
2. **Integration test**: `src/test.zig` serves as the test entry point, importing all modules
3. **Example tests**: `src/example/quickstart.zig` contains a test for end-to-end functionality

### Running Tests

```bash
# Run all tests
zig build test

# Run quickstart integration test only
zig build quickstart
```

### Test Requirements

- Some tests require environment variables (e.g., `DASHSCOPE_API_KEY`) and will skip if not present
- Tests use `std.testing.allocator` for memory leak detection

## Configuration

The framework uses a `.env` file for configuration. Copy `.env.example` to `.env` and fill in:

```bash
cp .env.example .env
```

### Required Environment Variables

```bash
# LLM Backend Configuration (OpenAI-compatible)
OMNIRLM_API_KEY=sk-your-api-key-here        # Or DASHSCOPE_API_KEY / OPENAI_API_KEY
OMNIRLM_BASE_URL=https://api.example.com/v1/chat/completions
OMNIRLM_MODEL_NAME=gpt-4

```

The `config_env.zig` module supports:

- Variable substitution: `${VAR}` or `$VAR`
- Quoted values
- Comments (lines starting with `#`)
- Multiple key aliases (e.g., `OMNIRLM_API_KEY`, `OPENAI_API_KEY`)

## Code Organization

### Module System

- **Public API**: Exported through `src/omni-rlm.zig` using `@import`
- **Core modules**: Located in `src/core/`, imported relatively
- **Example binaries**: Located in `src/example/`, import via module `omni-rlm`

### Key Types and Structs

1. **RLM** (`src/core/rlm.zig`): Main orchestrator struct
   - Manages chunk-by-chunk completion loop
   - Handles material setup and final synthesis
   - Configurable max_depth, max_iterations, and material_chunk_size

2. **RLMLogger** (`src/core/rlm_logger.zig`): Structured logging
   - JSON-lines format
   - Automatic timestamp and run ID generation
   - API key stripping for security

3. **EnvHandler** (`src/core/environment/type.zig`): Material access wrapper
   - Supports `local` material storage
   - Unified interface via chunk-read methods

4. **Message** (`src/core/types.zig`): OpenAI-compatible message format
   - Fields: `role` ("system" | "user" | "assistant"), `content`

## Development Conventions

### Code Style

- Use explicit allocators - never use `std.heap.page_allocator` in library code
- Document all public functions with doc comments (`///`)
- Use `defer` for resource cleanup immediately after allocation
- Follow Zig naming conventions:
  - `snake_case` for variables and functions
  - `PascalCase` for types and structs
  - `SCREAMING_SNAKE_CASE` for constants

### Memory Management

```zig
// Pattern: Allocate -> defer free immediately
const data = try allocator.alloc(u8, 100);
defer allocator.free(data);

// For structs with deinit:
var rlm: RLM = .{ ... };
try rlm.init();
defer rlm.deinit();
```

### Error Handling

- Use Zig's error union type (`!Type`)
- Define custom error sets where appropriate
- Return early on errors with `try`

### Testing Patterns

```zig
test "descriptive test name" {
    const allocator = std.testing.allocator;

    // Test code here
    // Memory leaks are automatically detected
}
```

## Security Considerations

1. **API Keys**:
   - Never commit `.env` files (listed in `.gitignore`)
   - RLMLogger automatically strips API keys from metadata logs
   - Keys are loaded from environment or `.env` file at runtime

2. **Material Handling**:
   - Local environment stores long text in memory for chunked processing
   - Material is read incrementally during the summarization loop

3. **File Operations**:
   - Log files are created in `./logs/` directory
   - Example runners may read source material such as `README.md` from the workspace

## Common Tasks

### Adding a New Example

1. Create file in `src/example/my_example.zig`
2. Add to `build.zig` as a new executable target
3. Import using `const RLM = @import("omni-rlm").RLM;`

### Adding a New Backend

Currently only OpenAI-compatible APIs are supported. To add a new backend:

1. Extend `Model_info.zig` or create new handler in `core/`
2. Update backend type handling in `RLM` struct

### Adding a New Environment

1. Create new directory under `src/core/environment/`
2. Implement required interface: `init`, `count_chunks`, `read_chunk`, `deinit`
3. Add variant to `env_type` enum in `type.zig`
4. Add case to `EnvHandler` union

## Important Notes for AI Agents

1. **Material Model**: The current architecture is centered on chunked traversal of long material rather than code execution.

2. **Build Cache**: If encountering strange build issues, clean with `rm -rf .zig-cache zig-out/`

3. **Zig Version**: This project requires Zig 0.15.2. Check version with `zig version`.

4. **Async/Await**: This codebase uses synchronous I/O. The Zig standard library HTTP client is synchronous.

5. **Chunking Strategy**: `material_chunk_size` and `max_iterations` together determine how aggressively material is split.

## Reference Documentation

- Detailed API reference: `API_referance.md`
- User guide: `README.md` / `README_CN.md`
- Future roadmap: `ROADMAP.md`
