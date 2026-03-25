<div align="center">

# Omni-RLM

### 高性能长文本推理框架

[![Zig](https://img.shields.io/badge/Zig-0.15.2-orange.svg)](https://ziglang.org/)

_利用 Zig 的类型安全和高性能特性，对超长材料执行分块推理与汇总_

English README: [README.md](README.md)

[概述](#-概述) •
[特性](#-特性) •
[安装](#安装) •
[快速开始](#-快速开始) •
[使用示例](#-使用示例) •

</div>

---

## 📖 概述

Omni-RLM 是一个**高性能长文本推理框架**，用于围绕根问题对超长材料进行分块遍历、累计摘要和最终回答。借助 Zig 的零成本抽象和内存安全特性，它为生产级 AI 应用提供了坚实的基础。

### 为什么选择 Omni-RLM？

- 🚀 **极速性能**: 利用 Zig 的零成本抽象和手动内存管理实现最优性能
- 🔄 **分块推理**: 按块遍历超长材料并持续更新累计摘要
- 📝 **生产级日志**: 全面的结构化日志，便于调试和分析
- 🔌 **后端无关**: 兼容任何 OpenAI 兼容的 API（OpenAI、Qwen、Anthropic 等）
- 🎯 **类型安全**: 编译时保证防止运行时错误
- 💾 **内存高效**: 显式分配器控制，资源使用可预测

## ✨ 特性

| 特性             | 描述                                 |
| ---------------- | ------------------------------------ |
| **长文本处理**   | 按可配置块大小遍历超长材料           |
| **查询追踪**     | 自动追踪上下文长度、类型和元数据     |
| **迭代日志**     | 每次迭代的 JSON 格式日志，完全可追溯 |
| **后端灵活性**   | 轻松集成 OpenAI、Qwen 或任何兼容 API |
| **内存安全**     | 内置保护防止内存泄漏和未定义行为     |
| **自定义提示词** | 可覆盖系统提示词实现专门的代理行为   |

## 安装

### 前置要求

- [Zig](https://ziglang.org/download/) 0.15.2 或更高版本
- 当前长文本处理流程不需要 Python 运行时

### 安装步骤

1. 克隆仓库：

```bash
git clone https://github.com/Open-Model-Initiative/Omni-RLM.git
cd Omni-RLM
```

2. 复制模板并创建 `.env` 文件：

```bash
cp .env.example .env
```

3. 填写 `.env` 配置：

```dotenv
OMNIRLM_API_KEY=sk-your-api-key-here
OMNIRLM_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
OMNIRLM_MODEL_NAME=qwen-flash
```

## 🚀 快速开始

以下是一个简单的入门示例：

```bash
zig build run
```

**注意：`zig build run` 现在会从 `.env` 读取后端配置。**

```zig
const std = @import("std");
const omni = @import("omni-rlm");
const RLM = omni.RLM;
const RLMLogger = omni.RLMLogger;
const config_env = omni.config_env;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var backend_cfg = try config_env.load_backend_env_config(allocator, ".env");
    defer backend_cfg.deinit(allocator);

    // 初始化日志记录器
    const logger = try RLMLogger.init("./logs", "run", allocator);

    // 配置 RLM 实例
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

    const root = "请将材料总结为 3 句话。";
    const material_path = "README.md";

    const result = try rlm.completion(root, material_path);
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

日志以 JSONL 格式保存到 `./logs/my_session_<时间戳>_<随机ID>.jsonl` 文件中，每一行都是一条独立记录。

## 📋 核心概念

### RLM（长文本推理器）

RLM 是框架的核心结构，负责管理长文本的分块遍历、累计摘要和最终回答流程。

**关键参数：**

- `backend`: 后端服务标识符（如 "openai"）
- `backend_kwargs`: 结构化后端配置（API 密钥、基础 URL、模型名称）
- `environment`: 材料环境类型（当前为 "local"）
- `max_depth`: 最大回退深度（默认：1）
- `max_iterations`: 每次补全允许的最大材料块迭代次数
- `material_chunk_size`: 单个材料块的目标大小
- `custom_system_prompt`: 可选的自定义系统提示词
- `logger`: 可选的日志记录器
- `allocator`: 内存分配器

### 长文本处理流程

1. **初始化**: 设置后端、环境和日志配置
2. **材料建模**: 根据材料长度和 `material_chunk_size` 生成分块信息
3. **迭代执行**:
   - 读取当前材料块
   - 将根问题、当前材料块和已有累计摘要发送给模型
   - 获取更新后的累计摘要
   - 继续处理下一块材料
4. **最终汇总**: 基于累计摘要生成最终答案并返回执行时间与元数据

### 日志系统

RLMLogger 提供结构化的 JSONL 日志，记录：

- **元数据**: 模型配置、块大小和迭代限制
- **迭代详情**: 每次材料块处理的提示词、摘要响应和块索引
- **最终结果**: 最后返回给调用方的 `completion` 结果
- **性能指标**: 执行时间、总迭代次数

最终返回内容会作为 `type: "completion"` 的记录写在日志末尾。如果你在根问题里明确要求“只返回代码，不要 Markdown fence，不要解释”，日志中的 `completion.response` 也会记录这段最终代码。

## 🔧 高级配置

### 配置分块策略

```zig
var rlm: RLM = .{
    .max_depth = 1,
    .max_iterations = 100,      // 最多处理 100 个材料块
    .material_chunk_size = 8192, // 每块目标长度约 8 KB
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
│   ├── omni-rlm.zig          # 对外导出 (RLM, RLMLogger, config_env)
│   ├── core/
│   │   ├── config_env.zig    # .env 后端配置加载器
│   │   ├── rlm.zig           # 核心 RLM 调度逻辑
│   │   ├── rlm_logger.zig    # 结构化日志系统
│   │   ├── types.zig         # 类型定义与结构体
│   │   ├── prompt.zig        # 提示词构建工具
│   │   ├── Model_info.zig    # 模型配置与请求
│   │   └── environment/
│   │       ├── type.zig      # EnvHandler 与环境类型
│   │       ├── local/        # 本地材料存储
│   │       │   └── local.zig # 本地分块读取实现
│   └── example/
│       ├── quickstart.zig    # 示例 (用于调试与测试)
│       ├── run.zig           # 示例运行器
│       └── openclaw.zig      # OpenClaw 风格长文本分析示例
├── API_referance.md     # API 参考文档
├── build.zig
├── build.zig.zon
├── LICENSE
└── README.md            # 英文文档
```

## 📖 详细文档

- [API 参考](API_referance.md) - 完整的 API 文档
