//! Omni-RLM - Recursive Language Model framework for Zig
//!
//! This module provides the core components for building recursive LLM applications
//! with fine-grained execution environment control.
//!
//! ## Main Components
//!
//! - `RLM` - The main orchestrator for recursive LLM completions
//! - `RLMLogger` - Structured JSON logging for RLM iterations
//! - `config_env` - Environment configuration loader for .env files
//!
//! ## Example Usage
//!
//! ```zig
//! const omni_rlm = @import("omni-rlm");
//!
//! var logger = try omni_rlm.RLMLogger.init("./logs", "my_run", allocator);
//! defer logger.deinit(allocator);
//!
//! var rlm: omni_rlm.RLM = .{
//!     .backend_kwargs = .{
//!         .api_key = "sk-...",
//!         .base_url = "https://api.example.com/v1/chat/completions",
//!         .model_name = "gpt-4",
//!     },
//!     .allocator = allocator,
//!     .logger = logger,
//! };
//! ```

pub const RLM = @import("core/rlm.zig").RLM;
pub const RLMLogger = @import("core/rlm_logger.zig").RLMLogger;
pub const config_env = @import("core/config_env.zig");
