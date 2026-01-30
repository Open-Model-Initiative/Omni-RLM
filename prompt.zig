const std = @import("std");
const json = std.json;
const QueryMetadata = @import("types.zig").QueryMetadata;
const Message = @import("types.zig").Message;

/// System prompt for the REPL environment with explicit final answer checking
pub const RLM_SYSTEM_PROMPT: []const u8 =
    \\You are tasked with answering a query with associated context. You can access, transform, and analyze this context interactively in a REPL environment that can recursively query sub-LLMs, which you are strongly encouraged to use as much as possible. You will be queried iteratively until you provide a final answer.
    \\
    \\The REPL environment is initialized with:
    \\1. A `context` variable that contains extremely important information about your query. You should check the content of the `context` variable to understand what you are working with. Make sure you look through it sufficiently as you answer your query.
    \\2. A `llm_query` function that allows you to query an LLM (that can handle around 500K chars) inside your REPL environment.
    \\3. A `llm_query_batched` function that allows you to query multiple prompts concurrently: `llm_query_batched(prompts: List[str]) -> List[str]`. This is much faster than sequential `llm_query` calls when you have multiple independent queries. Results are returned in the same order as the input prompts.
    \\4. The ability to use `print()` statements to view the output of your REPL code and continue your reasoning.
    \\
    \\You will only be able to see truncated outputs from the REPL environment, so you should use the query LLM function on variables you want to analyze. You will find this function especially useful when you have to analyze the semantics of the context. Use these variables as buffers to build up your final answer.
    \\Make sure to explicitly look through the entire context in REPL before answering your query. An example strategy is to first look at the context and figure out a chunking strategy, then break up the context into smart chunks, and query an LLM per chunk with a particular question and save the answers to a buffer, then query an LLM with all the buffers to produce your final answer.
    \\
    \\You can use the REPL environment to help you understand your context, especially if it is huge. Remember that your sub LLMs are powerful -- they can fit around 500K characters in their context window, so don't be afraid to put a lot of context into them. For example, a viable strategy is to feed 10 documents per sub-LLM query. Analyze your input data and see if it is sufficient to just fit it in a few sub-LLM calls!
    \\
    \\When you want to execute Python code in the REPL environment, wrap it in triple backticks with 'repl' language identifier. For example, say we want our recursive model to search for the magic number in the context (assuming the context is a string), and the context is very long, so we want to chunk it:
    \\```repl
    \\chunk = context[:10000]
    \\answer = llm_query(f"What is the magic number in the context? Here is the chunk: {chunk}")
    \\print(answer)
    \\```
    \\
    \\As an example, suppose you're trying to answer a question about a book. You can iteratively chunk the context section by section, query an LLM on that chunk, and track relevant information in a buffer.
    \\```repl
    \\query = "In Harry Potter and the Sorcerer's Stone, did Gryffindor win the House Cup because they led?"
    \\for i, section in enumerate(context):
    \\    if i == len(context) - 1:
    \\        buffer = llm_query(f"You are on the last section of the book. So far you know that: {buffers}. Gather from this last section to answer {query}. Here is the section: {section}")
    \\        print(f"Based on reading iteratively through the book, the answer is: {buffer}")
    \\    else:
    \\        buffer = llm_query(f"You are iteratively looking through a book, and are on section {i} of {len(context)}. Gather information to help answer {query}. Here is the section: {section}")
    \\        print(f"After section {i} of {len(context)}, you have tracked: {buffer}")
    \\```
    \\
    \\As another example, when the context isn't that long (e.g. >100M characters), a simple but viable strategy is, based on the context chunk lengths, to combine them and recursively query an LLM over chunks. For example, if the context is a List[str], we ask the same query over each chunk using `llm_query_batched` for concurrent processing:
    \\```repl
    \\query = "A man became famous for his book "The Great Gatsby". How many jobs did he have?"
    \\# Suppose our context is ~1M chars, and we want each sub-LLM query to be ~0.1M chars so we split it into 10 chunks
    \\chunk_size = len(context) // 10
    \\chunks = []
    \\for i in range(10):
    \\    if i < 9:
    \\        chunk_str = "\n".join(context[i*chunk_size:(i+1)*chunk_size])
    \\    else:
    \\        chunk_str = "\n".join(context[i*chunk_size:])
    \\    chunks.append(chunk_str)
    \\
    \\# Use batched query for concurrent processing - much faster than sequential calls!
    \\prompts = [f"Try to answer the following query: {query}. Here are the documents:\n{chunk}. Only answer if you are confident in your answer based on the evidence." for chunk in chunks]
    \\answers = llm_query_batched(prompts)
    \\for i, answer in enumerate(answers):
    \\    print(f"I got the answer from chunk {i}: {answer}")
    \\final_answer = llm_query(f"Aggregating all the answers per chunk, answer the original query about total number of jobs: {query}\n\nAnswers:\n" + "\n".join(answers))
    \\```
    \\
    \\As a final example, after analyzing the context and realizing its separated by Markdown headers, we can maintain state through buffers by chunking the context by headers, and iteratively querying an LLM over it:
    \\```repl
    \\# After finding out the context is separated by Markdown headers, we can chunk, summarize, and answer
    \\import re
    \\sections = re.split(r'### (.+)', context["content"])
    \\buffers = []
    \\for i in range(1, len(sections), 2):
    \\    header = sections[i]
    \\    info = sections[i+1]
    \\    summary = llm_query(f"Summarize this {header} section: {info}")
    \\    buffers.append(f"{header}: {summary}")
    \\final_answer = llm_query(f"Based on these summaries, answer the original query: {query}\n\nSummaries:\n" + "\n".join(buffers))
    \\```
    \\In the next step, we can return FINAL_VAR(final_answer).
    \\
    \\IMPORTANT: When you are done with the iterative process, you MUST provide a final answer inside a FINAL function when you have completed your task, NOT in code. Do not use these tags unless you have completed your task. You have two options:
    \\1. Use FINAL(your final answer here) to provide the answer directly
    \\2. Use FINAL_VAR(variable_name) to return a variable you have created in the REPL environment as your final output
    \\
    \\Think step by step carefully, plan, and execute this plan immediately in your response -- do not just say "I will do this" or "I will do that". Output to the REPL environment and recursive LLMs as much as possible. Remember to explicitly answer the original query in your final answer.
;

pub const USER_PROMPT: []const u8 =
    \\Think step-by-step on what to do using the REPL environment (which contains the context) to answer the prompt.
    \\
    \\Continue using the REPL environment, which has the `context` variable, and querying sub-LLMs by writing to ```repl``` tags, and determine your answer. Your next action:
;

pub const USER_PROMPT_WITH_ROOT: []const u8 =
    \\Think step-by-step on what to do using the REPL environment (which contains the context) to answer the original prompt: {s}.
    \\
    \\Continue using the REPL environment, which has the `context` variable, and querying sub-LLMs by writing to ```repl``` tags, and determine your answer. Your next action:
;

/// Build user prompt based on root_prompt and iteration number
pub fn buildUserPrompt(root_prompt: ?[]const u8, iteration: u32, allocator: std.mem.Allocator) ![]Message {
    var prompt: []const u8 = undefined;

    if (iteration == 0) {
        const safeguard = "You have not interacted with the REPL environment or seen your prompt / context yet. Your next action should be to look through and figure out how to answer the prompt, so don't just provide a final answer yet.\n\n";
        if (root_prompt != null) {
            const plug_in_root_prompt = try std.fmt.allocPrint(allocator, USER_PROMPT_WITH_ROOT, .{root_prompt.?});
            defer allocator.free(plug_in_root_prompt);
            prompt = try std.fmt.allocPrint(allocator, "{s}{s}", .{ safeguard, plug_in_root_prompt });
        } else {
            prompt = try std.fmt.allocPrint(allocator, "{s}{s}", .{ safeguard, USER_PROMPT });
        }
    } else {
        prompt = try std.fmt.allocPrint(allocator, "{s}{s}", .{ "The history before is your previous interactions with the REPL environment. ", USER_PROMPT });
    }
    const message = Message{
        .role = "user",
        .content = prompt,
    };
    const result = try allocator.alloc(Message, 1);
    result[0] = message;
    return result;
}

test "buildUserPrompt works" {
    const allocator = std.testing.allocator;
    {
        const prompt_no_root = try buildUserPrompt(null, 0, allocator);
        defer ReleaseMessageArray(prompt_no_root, allocator);
        const formatter = std.json.fmt(.{ .message = prompt_no_root }, .{});
        std.debug.print("\nTESTING:\nUser Prompt without root:(iteration 0)\n{f}\n", .{formatter});
    }
    {
        const prompt_with_root = try buildUserPrompt("What is the capital of France?", 0, allocator);
        defer ReleaseMessageArray(prompt_with_root, allocator);
        const formatter = std.json.fmt(.{ .message = prompt_with_root }, .{});
        std.debug.print("\nTESTING:\nUser Prompt with root:\n{f}\n", .{formatter});
    }
    {
        const prompt_without_root = try buildUserPrompt(null, 1, allocator);
        defer ReleaseMessageArray(prompt_without_root, allocator);
        const formatter = std.json.fmt(.{ .message = prompt_without_root }, .{});
        std.debug.print("\nTESTING:\nUser Prompt without root:(iteration 1)\n{f}\n", .{formatter});
    }
}

///you need to release the `system_prompt` and `system_prompt[1].content` after use
pub fn buildSystemPrompt(custom_system_prompt: ?[]const u8, query_metadata: QueryMetadata, allocator: std.mem.Allocator) ![]Message {
    const tes: []u8 = try std.fmt.allocPrint(allocator, "Your context is a {s} with {d} total characters, and is broken up into chunks of char lengths: {any}.", .{ query_metadata.context_type, query_metadata.context_total_length, query_metadata.context_length });
    var system_content: []u8 = undefined;
    if (custom_system_prompt != null) {
        system_content = try std.fmt.allocPrint(allocator, "{s}", .{custom_system_prompt.?});
    } else {
        system_content = try std.fmt.allocPrint(allocator, "{s}", .{RLM_SYSTEM_PROMPT});
    }

    const Msg = [2]Message{ Message{ .role = "system", .content = system_content }, Message{ .role = "assistant", .content = tes } };
    const system_prompt = try allocator.dupe(Message, &Msg);
    return system_prompt;
}

test "buildSystemPrompt works" {
    const allocator = std.testing.allocator;
    const query_metadata: QueryMetadata = .{
        .context_length = &[1]u32{16},
        .context_total_length = 16,
        .context_type = "str",
    };
    const system_prompt = try buildSystemPrompt(null, query_metadata, allocator);
    defer ReleaseMessageArray(system_prompt, allocator);
    const formatter = std.json.fmt(.{ .message = system_prompt }, .{});
    // const out = try std.fmt.allocPrint(allocator, "{f}", .{formatter});

    std.debug.print("\nTESTING:System Prompt\n{f}\n", .{formatter});
}

pub fn ReleaseMessageArray(messages: []Message, allocator: std.mem.Allocator) void {
    for (messages) |msg| {
        allocator.free(msg.content);
    }
    allocator.free(messages);
}
