# Omni-RLM Roadmap 2026

## Future Directions

Omni-RLM project servers as an experimental project that provide a ziglangg based implementation of the RLM paper. Despite the simplicity of the initial version, our team do have a more long term view of how this project could evolve in several exciting directions that might have impact on the overall Agentic Infra open source ecosystem building that is part of the mission on Open Model Initiative. 

Of course this is by no means an exhaustive list and community inputs are more than welcomed.

- Develop a host-side agentic runtime ecosystem
- Grow RLM to support Plan-and-ReAct agent system
- Agent Sandbox support
- Better REPL support in Zig

### Develop a host-side agentic runtime ecosystem

With all the concentration of AI hardwared accelerated support of LLMs, one of the potential directions of RLM is that we might grow a strong "host-side" runtime ecosystem. We envision that for Omni-RLM there will be two deployment scenarios:

- Local: running on the host side of an AI hardware server that could interact with the general LLM serving infrastructure.
- Remote: remotely running on an embedded device (where both Zig and Rust will shine) that talks to a LLM provider via public API.

For the **local** scenario, we might have future feature enhancement that could have the LLM Serving infra (e.g [omni-infer](https://github.com/omni-ai-npu/omni-infer) or TRT-LLM or any other vLLM/SGL based oss serving infra) report/expose their context acceleration capability to Omni-RLM and get turned into a policy like module. This will become more important when multi-modal/omni-modal models based agentic system getting deployed.

For the **remote** scenario, we will concentrate on a more performant pre-processing of the large context so that even edge devices could be powerful.

### Grow RLM to support Plan-and-ReAct agent system

The current **Omni-RLM** implementation establishes a foundation for *recursive, programmatic reasoning*, where complex tasks are solved through iterative interaction with an execution environment rather than a single, monolithic prompt. Another interesting future direction is to evolve Omni-RLM toward an something like the proposed **[EZBlender-style Plan-and-ReAct agent system](https://github.com/Aztech-Lab/EZ_Blender)**, enabling efficient, scalable, and semantically faithful 3D editing workflows.

This evolution is not a shift in application domain alone, but a transition in **system organization**: from a single recursive reasoner to a **distributed, agentic control architecture** built on top of RLM.

#### Phase 1: RLM-Driven Planner (Semantic Control Plane)

We plan to extend Omni-RLM into a **recursive planning layer** that serves as the global control plane of the system.

Instead of mapping user prompts directly to executable code, the RLM-Planner will:

* Recursively analyze user intent (text and optional visual references)
* Disentangle high-level semantics across editing domains (geometry, materials, lighting, camera, background)
* Produce **domain-level semantic directives** rather than Blender-specific API calls

This allows planning to remain stable, interpretable, and adaptable, while leveraging RLM’s ability to iteratively refine task structure under ambiguity or long-range dependencies.

#### Phase 2: Domain-Specialized RLM Sub-Agents (Execution Plane)

Each editing domain will be handled by a **specialized sub-agent**, implemented as a lightweight RLM execution environment.

These RLM Sub-Agents will:

* Receive semantic directives from the planner
* Recursively decompose them into hard constraints and implementation choices
* Generate and execute Blender Python code locally
* Perform bounded self-verification and refinement without triggering global re-planning

This design localizes errors, enables parallel execution, and significantly reduces end-to-end latency compared to monolithic or fully sequential agent designs.

#### Phase 3: RLM-Based Debug and Recovery

We plan to generalize the current debugging logic into an **RLM-powered Debug Agent**.

Rather than relying on fixed repair rules, the Debug Agent will:

* Recursively analyze execution failures
* Generate and test alternative repair strategies
* Validate fixes through controlled re-execution

Importantly, debugging remains decoupled from the planner, ensuring that local failures do not cascade into system-wide replanning.

#### Architectural Vision Summary

The long-term architecture combines:

* **RLM as the reasoning substrate**
* **Plan-and-ReAct as the agent orchestration model**

This results in a system where:

* Planning and execution are cleanly separated
* Reasoning is distributed across autonomous agents
* Errors are absorbed locally
* Long-horizon, multi-objective editing tasks remain responsive and stable

### Agent Sandbox support

Omni-RLM could also benifit from the burgeoning evolution of agent sandbox ecosystem like the recent [daytona support for RLM](https://www.daytona.io/docs/en/guides/recursive-language-models/)

### Better REPL support in Zig

The team will take a look at what Tigerbeetle has developed for [Zig REPL](https://github.com/tigerbeetle/tigerbeetle/tree/main/src/repl) for a more Zig native REPL env implmentation.


