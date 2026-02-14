<div align="center">

# Omni-RLM

### 高性能递归语言模型框架

[![Zig](https://img.shields.io/badge/Zig-0.15.2-orange.svg)](https://ziglang.org/)

*利用 Zig 的类型安全和高性能特性，释放 AI 代理递归推理的强大能力*

English README: [README.md](README.md)

[概述](#-概述) •
[特性](#-特性) •
[安装](#安装) •
[快速开始](#-快速开始) •
[使用示例](#-使用示例) •

</div>

---

## 📖 概述

Omni-RLM 是一个**高性能递归语言模型框架**，使 AI 代理能够通过可控的递归 LLM 调用执行复杂的推理任务。借助 Zig 的零成本抽象和内存安全特性，它为生产级 AI 应用提供了坚实的基础。

### 为什么选择 Omni-RLM？

- 🚀 **极速性能**: 利用 Zig 的零成本抽象和手动内存管理实现最优性能
- 🔄 **递归推理**: 支持多层次语言模型调用，提供精细的控制
- 📝 **生产级日志**: 全面的结构化日志，便于调试和分析
- 🔌 **后端无关**: 兼容任何 OpenAI 兼容的 API（OpenAI、Qwen、Anthropic 等）
- 🎯 **类型安全**: 编译时保证防止运行时错误
- 💾 **内存高效**: 显式分配器控制，资源使用可预测

## ✨ 特性

| 特性 | 描述 |
|---------|-------------|
| **递归执行** | 执行语言模型，支持可配置的递归深度限制 |
| **查询追踪** | 自动追踪上下文长度、类型和元数据 |
| **迭代日志** | 每次迭代的 JSON 格式日志，完全可追溯 |
| **后端灵活性** | 轻松集成 OpenAI、Qwen 或任何兼容 API |
| **内存安全** | 内置保护防止内存泄漏和未定义行为 |
| **自定义提示词** | 可覆盖系统提示词实现专门的代理行为 |

## 安装

### 前置要求

- [Zig](https://ziglang.org/download/) 0.15.2 或更高版本
- Python 包 `dill`（仅在本地环境执行代码时需要）

### 安装步骤

1. 克隆仓库：
```bash
git clone https://github.com/Open-Model-Initiative/Omni-RLM.git
cd Omni-RLM
```

2. 安装 Python 依赖：
```bash
pip install dill # 仅在本地环境执行代码时需要
```

## 🚀 快速开始

以下是一个简单的入门示例：

```bash
zig build run
```

**注意：请更换api_key为你自己的API密钥。**

```zig
const std = @import("std");
const RLM = @import("omni-rlm.zig").RLM;
const RLMLogger = @import("omni-rlm.zig").RLMLogger;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // 初始化日志记录器
    const logger = try RLMLogger.init("./logs", "run", allocator);

    // 配置 RLM 实例
    var rlm: RLM = .{
        .backend = "openai",
        .backend_kwargs = .{
            .base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            .api_key = "Bearer 你的API密钥",
            .model_name = "qwen-plus",
        },
        .environment = "local",
        .environment_kwargs = "{\"mainfunc\": \"src/python_script/env_init.py\"}",
        .max_depth = 1,
        .logger = logger,
        .allocator = allocator,
        .max_iterations = 10,
    };

    try rlm.init();
    defer rlm.deinit();

    // 发起一个补全请求
    const prompt = "打印前 100 个 2 的幂次方，每个占一行。";
    const p = try allocator.dupe(u8, prompt);
    defer allocator.free(p);
    
    const result = try rlm.completion(p, null);
    defer allocator.free(result.response);
    
    std.debug.print("响应: {s}\n", .{result.response});
    std.debug.print("执行时间: {d}ms\n", .{result.execution_time});
}
```

## 💡 使用示例

### 配置不同的后端

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

### 使用自定义系统提示词

```zig
const custom_prompt = "你是一个专业的数学助手，专注于解决复杂的数学问题。";

var rlm: RLM = .{
    .backend = "openai",
    .backend_kwargs = .{
        .base_url = "https://api.openai.com/v1/chat/completions",
        .api_key = "sk-你的密钥",
        .model_name = "gpt-4",
    },
    .custom_system_prompt = custom_prompt,
    .max_depth = 3,
    .allocator = allocator,
};
```

### 启用详细日志记录

```zig
const logger = try RLMLogger.init("./logs", "my_session", allocator);

var rlm: RLM = .{
    .backend = "openai",
    .backend_kwargs = .{
        .base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
        .api_key = "sk-你的密钥",
        .model_name = "qwen-plus",
    },
    .logger = logger,
    .max_depth = 2,
    .max_iterations = 30,
    .allocator = allocator,
};
```

日志将保存在 `./logs/my_session_<时间戳>.json` 文件中。

## 📋 核心概念

### RLM（递归语言模型）

RLM 是框架的核心结构，负责管理语言模型的递归调用流程。

**关键参数：**

- `backend`: 后端服务标识符（如 "openai"）
- `backend_kwargs`: 结构化后端配置（API 密钥、基础 URL、模型名称）
- `environment`: 环境配置类型（如 "local"）
- `max_depth`: 最大递归深度（默认：1）
- `max_iterations`: 每个会话允许的最大迭代次数（默认：4）
- `custom_system_prompt`: 可选的自定义系统提示词
- `logger`: 可选的日志记录器
- `allocator`: 内存分配器

### 递归推理流程

1. **初始化**: 设置后端、环境和日志配置
2. **提示词处理**: 构建包含系统提示词的消息历史
3. **迭代执行**: 
   - 向语言模型发送请求
   - 提取代码块（如果有）
   - 执行代码并收集输出
   - 检查是否有最终答案
   - 如果需要，继续下一次迭代
4. **结果返回**: 返回最终答案、执行时间和元数据

### 日志系统

RLMLogger 提供结构化的 JSON 日志，记录：

- **元数据**: 模型配置、递归限制
- **迭代详情**: 每次迭代的提示词、响应、代码执行结果
- **性能指标**: 执行时间、迭代次数

## 🔧 高级配置

### 配置递归深度

```zig
var rlm: RLM = .{
    .max_depth = 5,        // 允许最多 5 层递归
    .max_iterations = 100,  // 每层最多 100 次迭代
    // ... 其他配置
};
```

## 🧪 测试

运行测试套件：

```bash
zig build test
```

运行快速开始示例：

```bash
zig build quickstart
```

## 🛠️ 项目结构

```
Omni-RLM/
├── src/
│   ├── omni-rlm.zig          # 对外导出 (RLM, RLMLogger)
│   ├── core/
│   │   ├── rlm.zig           # 核心 RLM 调度逻辑
│   │   ├── rlm_logger.zig    # 结构化日志系统
│   │   ├── types.zig         # 类型定义与结构体
│   │   ├── prompt.zig        # 提示词构建工具
│   │   ├── parsing.zig       # 响应解析 (代码块)
│   │   ├── Model_info.zig    # 模型配置与请求
│   │   └── environment/
│   │       ├── type.zig      # EnvHandler 与环境类型
│   │       ├── local.zig     # 本地 Python 运行器
│   │       └── daytona.zig   # Daytona 运行器
│   ├── example/
│   │   ├── quickstart.zig    # 示例 (用于调试与测试)
│   │   └── run.zig           # 示例运行器
│   └── python_script/
│       ├── env_init.py       # 环境初始化脚本
│       ├── find_code_blocks.py
│       └── find_final_answer.py
├── API_referance.md     # API 参考文档
├── build.zig
├── build.zig.zon
├── LICENSE
└── README.md            # 英文文档
```

## 📖 详细文档

- [API 参考](API_referance.md) - 完整的 API 文档