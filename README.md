<div align="center">

# Omni-RLM

### A High-Performance Recursive Language Model Framework

[![Zig](https://img.shields.io/badge/Zig-0.15.2-orange.svg)](https://ziglang.org/)

*Leverage the power of recursive reasoning in AI agents with type-safe, high-performance Zig*

中文文档: [README_CN.md](README_CN.md)

[Overview](#-overview) •
[Features](#-features) •
[Installation](#installation) •
[Quick Start](#-quick-start) •
[Examples](#-usage-examples) •
[Project Structure](#-project-structure) •
[Documentation](#-documentation) •
[Roadmap](#-roadmap)

</div>

---

## 📖 Overview

Omni-RLM is a **high-performance [recursive language model framework](https://github.com/alexzhang13/rlm)** that enables AI agents to perform complex reasoning tasks through controlled recursive LLM calls. Built with Zig's zero-cost abstractions and memory safety features, it provides a robust foundation for production-grade AI applications.

### Why Omni-RLM?

- 🚀 **Blazing Fast**: Leveraging Zig's zero-cost abstractions and manual memory management for optimal performance
- 🔄 **Recursive Reasoning**: Support for multi-depth language model calls with fine-grained control
- 📝 **Production-Ready Logging**: Comprehensive structured logging for debugging and analysis
- 🔌 **Backend Agnostic**: Works with any OpenAI-compatible API (OpenAI, Qwen, Anthropic, etc.)
- 🎯 **Type-Safe**: Compile-time guarantees prevent runtime errors
- 💾 **Memory Efficient**: Explicit allocator control for predictable resource usage

## ✨ Features

| Feature | Description |
|---------|-------------|
| **Recursive Execution** | Execute language models with configurable recursion depth limits |
| **Query Tracking** | Automatic tracking of context length, type, and metadata |
| **Iteration Logging** | JSON-formatted logs for every iteration with full traceability |
| **Backend Flexibility** | Easy integration with OpenAI, Qwen, or any compatible LLM-API spec |
| **Memory Safety** | Built-in protection against memory leaks and undefined behavior |
| **Custom Prompts** | Override system prompts for specialized agent behaviors |

## Installation

### Prerequisites

- [Zig](https://ziglang.org/download/) 0.15.2 or later
- Python package `dill` for code execution in the 

### Installation Steps
1. Clone the repository:
```bash
git clone https://github.com/Open-Model-Initiative/Omni-RLM.git
cd Omni-RLM
```
2. Install Python dependencies:
```bash
pip install dill # Only needed if executing code in local environment
``` 

3. Copy the template and create your `.env` file:
```bash
cp .env.example .env
```

4. Fill your `.env` values:
```dotenv
OMNIRLM_API_KEY=sk-your-api-key-here
OMNIRLM_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
OMNIRLM_MODEL_NAME=qwen-flash
```

## 🚀 Quick Start

Here's a simple example to get you started:

```bash
zig build run
```

IMPORTANT: `zig build run` now loads backend config from `.env`.

```zig
!src/example/run.zig

const std = @import("std");
const omni = @import("omni-rlm");
const RLM = omni.RLM;
const RLMLogger = omni.RLMLogger;
const config_env = omni.config_env;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var backend_cfg = try config_env.load_backend_env_config(allocator, ".env");
    defer backend_cfg.deinit(allocator);

    // Initialize logger
    const logger = try RLMLogger.init("./logs", "run", allocator);

    // Configure RLM instance
    var rlm: RLM = .{
        .backend = "openai",
        .backend_kwargs = .{
            .base_url = backend_cfg.base_url,
            .api_key = backend_cfg.api_key,
            .model_name = backend_cfg.model_name,
        },
        .environment = "local",
        .environment_kwargs = "{}",
        .max_depth = 1,
        .logger = logger,
        .allocator = allocator,
        .max_iterations = 10,
    };

    try rlm.init();
    defer rlm.deinit();

    // Make a completion request
    const prompt = "Print me the first 100 powers of two, each on a newline.";
    const p = try allocator.dupe(u8, prompt);
    defer allocator.free(p);
    
    const result = try rlm.completion(p, null);
    defer allocator.free(result.response);
    
    std.debug.print("Response: {s}\n", .{result.response});
    std.debug.print("Execution Time: {d}ms\n", .{result.execution_time});
}
``` 

## 💡 Usage Examples

### OpenClaw-style agent in Zig

A dedicated OpenClaw-style entry point is available at `src/example/openclaw.zig`. It wires Omni-RLM with an autonomous system prompt and can be run as:

```bash
export OPENAI_API_KEY="sk-..."
# Optional overrides:
# export OPENAI_BASE_URL="https://api.openai.com/v1/chat/completions"
# export OPENAI_MODEL="gpt-4o-mini"
zig build openclaw -- "Implement a Fibonacci CLI and test it"
```

This gives you an agentic coding loop (plan → execute → reflect → final answer) while reusing Omni-RLM's recursion, logging, and environment tooling.

### Configuring Different Backends

<details>
<summary><b>OpenAI GPT-4</b></summary>

```zig
var rlm: RLM = .{
    .backend = "openai",
    .backend_kwargs = .{
        .base_url = "https://api.openai.com/v1/chat/completions",
        .api_key = "sk-...",
        .model_name = "gpt-4",
    },
    .max_depth = 3,
    .max_iterations = 50,
    .allocator = allocator,
};
```
</details>

<details>
<summary><b>Qwen (Alibaba Cloud)</b></summary>

```zig
var rlm: RLM = .{
    .backend = "openai",
    .backend_kwargs = .{
        .base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
        .api_key = "sk-...",
        .model_name = "qwen-plus",
    },
    .max_depth = 2,
    .allocator = allocator,
};
```
</details>

<details>
<summary><b>Custom Backend</b></summary>

```zig
var rlm: RLM = .{
    .backend = "openai",
    .backend_kwargs = .{
        .base_url = "https://your-custom-api.com/v1/chat/completions",
        .api_key = "sk-...",
        .model_name = "your-model",
    },
    .custom_system_prompt = "You are a specialized coding assistant...",
    .allocator = allocator,
};
```
</details>

### Working with Logs

The logger creates structured JSON logs that include:

```json
{
  "prompt": [{"role":"Your prompt concat with system message"}...],
  "response": "Model response",
    "code_blocks": [
        {
            "code": "extracted code block if any",
            "result": {
                "stdout": "output from code execution",
                "stderr": "error output if any",
                "term": "exit status"
            }
        }
    ],
  "final_answer": "Extracted final answer if any",
  "execution_time": 1234//milliseconds
}
```

## 📁 Project Structure

```
Omni-RLM/
├── src/
│   ├── omni-rlm.zig          # Public exports (RLM, RLMLogger, config_env)
│   ├── core/
│   │   ├── config_env.zig    # .env backend config loader
│   │   ├── rlm.zig           # Core RLM orchestrator
│   │   ├── rlm_logger.zig    # Structured logging system
│   │   ├── types.zig         # Type definitions and structs
│   │   ├── prompt.zig        # Prompt construction utilities
│   │   ├── parsing.zig       # Response parsing (code blocks)
│   │   ├── Model_info.zig    # Model configuration and metadata
│   │   └── environment/
│   │       ├── type.zig      # EnvHandler and env types
│   │       ├── local/        # Local Python environment
│   │       │   └── local.zig # Local runner implementation
│   │       └── daytona/      # Daytona environment
│   │           └── daytona.zig       # Daytona runner
│   │           └── daytona_script.py # Daytona helper script
│   └── example/
│       ├── quickstart.zig    # Example usage (use for debug and testing)
│       └── run.zig           # Example runner
├── API_referance.md     # API reference documentation
├── build.zig
├── build.zig.zon
├── LICENSE
└── README.md            # This file
```

### Key Files

- **`src/omni-rlm.zig`**: Package interface and `config_env` export
- **`src/core/rlm.zig`**: Main entry point with RLM struct and completion logic
- **`src/core/rlm_logger.zig`**: Handles all logging operations with JSON output
- **`src/core/types.zig`**: Shared type definitions (metadata, message, code blocks)
- **`src/core/prompt.zig`**: System prompt building from query metadata
- **`src/core/parsing.zig`**: Utilities to extract structured data from responses
- **`src/core/Model_info.zig`**: Model configurations and capabilities

## 🧪 Test

Run tests：

```bash
zig build test
```

run quickstart example：

```bash
zig build quickstart
```

## 📖 Documentation

- [API Referance](API_referance.md) - Complete API documentation

## 📖 Roadmap

The team has proposed an initial [community roadmap](/ROADMAP.md) and wider community inputs are welcomed.
