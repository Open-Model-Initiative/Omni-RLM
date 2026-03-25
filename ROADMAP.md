# Omni-RLM Roadmap 2026

## Future Directions

Omni-RLM project serves as an experimental project that provide a Zig language-based implementation of the RLM paper. Despite the simplicity of the initial version, our team do have a more long term view of how this project could evolve in several exciting directions that might have impact on the overall Agentic Infra open source ecosystem building that is part of the mission on Open Model Initiative.

Of course this is by no means an exhaustive list and community inputs are more than welcomed.

- Develop a host-side long-context runtime ecosystem
- Improve chunk planning and synthesis quality
- Add richer material backends and preprocessing tools
- Explore multimodal long-material support

### Develop a host-side long-context runtime ecosystem

With the growing availability of AI-hardware-accelerated LLM serving, one potential direction for Omni-RLM is a stronger host-side runtime ecosystem for long-context processing. We envision two deployment scenarios:

- Local: running beside an AI hardware server and coordinating chunking, summarization, and answer synthesis close to the model-serving stack.
- Remote: running on an embedded or edge device that performs lightweight preprocessing and calls a remote LLM API.

For the **local** scenario, future work could let serving infrastructure such as [omni-infer](https://github.com/omni-ai-npu/omni-infer), TRT-LLM, or other vLLM/SGL-based systems expose context-window and caching capabilities to Omni-RLM. That information could drive chunk-size policy, batching strategy, and synthesis cadence.

For the **remote** scenario, we will focus on efficient preprocessing so edge devices can still participate in long-material analysis without needing to hold the full reasoning workload locally.

### Improve chunk planning and synthesis quality

The current **Omni-RLM** implementation already provides chunk-by-chunk traversal and cumulative synthesis for very long text. A natural next step is to improve how the system plans chunk boundaries, carries forward evidence, and decides when the running summary is sufficient.

This is not about turning the project back into a code-execution agent. The direction is to make long-context reasoning more faithful, more controllable, and cheaper to run.

#### Phase 1: Better chunk policies

We plan to make chunking adaptive rather than fixed.

Possible improvements include:

- Dynamic chunk sizing based on material structure
- Overlap windows for preserving cross-section continuity
- Section-aware boundaries for documents, logs, and transcripts

This should improve both answer quality and token efficiency.

#### Phase 2: Stronger cumulative summaries

We also want the running summary to preserve evidence more reliably across many chunks.

Possible improvements include:

- Structured intermediate summaries
- Citation or source-span tracking per chunk
- Better final-answer synthesis from accumulated notes

This should reduce information loss in very long materials.

#### Phase 3: Domain-aware preprocessing

Another direction is better preprocessing for different material types.

Examples include:

- Log segmentation and timeline normalization
- PDF / markdown / HTML cleaning pipelines
- Transcript normalization for conversational material

This can make the downstream chunk loop more robust without complicating the core runtime.

#### Architectural Vision Summary

The long-term architecture combines:

- **RLM as a long-context reasoning substrate**
- **Zig as a predictable, efficient systems layer for chunk processing**

This results in a system where:

- Very long materials can be processed incrementally
- Evidence can be carried forward through explicit summaries
- Host-side preprocessing can be tuned for deployment constraints
- Final answers remain grounded in traversed material rather than one-shot prompting

### Explore multimodal long-material support

Longer term, we are also interested in materials that mix text with tables, images, and other structured artifacts. The main requirement is still the same: traverse large material incrementally, preserve evidence between chunks, and synthesize a grounded final answer.
