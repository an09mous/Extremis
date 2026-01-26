# Tool Execution Flow

This document describes how Extremis handles tool calling with LLMs, including the multi-round execution loop, message formatting, and persistence.

## Overview

When an LLM uses tools, the conversation follows a multi-turn pattern:
1. User sends a message
2. LLM responds with text and/or tool calls
3. Tools are executed
4. Results are fed back to the LLM
5. LLM continues (may call more tools or provide final response)

This loop continues until:
- LLM returns no tool calls (generation complete)
- Maximum rounds reached (50 rounds, then forced summarization)
- User cancels generation
- An error occurs

## Data Models

### ToolExecutionRound
Represents a single round of tool execution:

```swift
struct ToolExecutionRound {
    let toolCalls: [LLMToolCall]      // Tools the LLM requested
    let results: [ToolResult]          // Results from executing those tools
    let assistantResponse: String?     // Text LLM streamed BEFORE issuing tool calls
}
```

### ToolExecutionRoundRecord (Persistence)
Codable version for storage:

```swift
struct ToolExecutionRoundRecord: Codable {
    let toolCalls: [ToolCallRecord]
    let results: [ToolResultRecord]
    let assistantResponse: String?     // Partial text from this round
}
```

### ChatMessage with Tool Rounds
Messages store tool history compactly:

```swift
ChatMessage {
    role: .assistant
    content: String                           // ONLY the final response (after all tools)
    toolRounds: [ToolExecutionRoundRecord]?   // History of tool executions
}
```

## Execution Flow

### 1. Initial Request
```
User: "What's the weather in Tokyo?"
```

### 2. LLM Response with Tool Call
```
LLM streams: "Let me check the weather for you..."
LLM requests: weather_lookup(city: "Tokyo")
```

### 3. Tool Execution
```
Tool executes → Returns: { temp: 22, condition: "sunny" }
```

### 4. Round Recorded
```swift
Round 1: {
    assistantResponse: "Let me check the weather for you...",
    toolCalls: [weather_lookup(city: "Tokyo")],
    results: [{ temp: 22, condition: "sunny" }]
}
```

### 5. LLM Continues
LLM receives results, may:
- Call more tools → Go to step 2
- Provide final response → Generation complete

### 6. Final Response
```
LLM streams: "The weather in Tokyo is 22°C and sunny!"
```

### 7. Message Persisted
```swift
ChatMessage {
    role: .assistant
    content: "The weather in Tokyo is 22°C and sunny!"  // Final response only
    toolRounds: [Round 1]                                // Tool history
}
```

## Multi-Round Example

```
User: "Find the top GitHub repo for Swift and star it"

Round 1:
  assistantResponse: "I'll search for the top Swift repository..."
  toolCalls: [github_search(query: "language:swift", sort: "stars")]
  results: [{ repos: [{name: "swift", owner: "apple", stars: 65000}] }]

Round 2:
  assistantResponse: "Found it! Now let me star it for you..."
  toolCalls: [github_star(owner: "apple", repo: "swift")]
  results: [{ success: true }]

Final Response: "Done! I've starred apple/swift - it has 65,000 stars!"
```

Persisted as:
```swift
ChatMessage {
    content: "Done! I've starred apple/swift - it has 65,000 stars!",
    toolRounds: [Round 1, Round 2]
}
```

## Synthetic Messages for LLM API

When continuing a conversation, tool rounds must be expanded into the format each LLM API expects.

### Why Synthetic Messages?

LLM APIs require a specific message sequence:
```
assistant message → with tool_calls
tool message      → with results
assistant message → with response
```

We store compactly but expand for API calls.

### Expansion Algorithm

```swift
func formatMessagesWithToolRounds(messages: [ChatMessage]) -> [APIMessage] {
    var result: [APIMessage] = []

    for message in messages {
        if message.role == .assistant, let toolRounds = message.toolRounds {
            // Expand each round
            for round in toolRounds {
                // 1. Partial text BEFORE tool calls (if any)
                if let response = round.assistantResponse, !response.isEmpty {
                    result.append(AssistantMessage(content: response))
                }

                // 2. Assistant message with tool_calls
                result.append(AssistantMessage(toolCalls: round.toolCalls))

                // 3. Tool results
                for toolResult in round.results {
                    result.append(ToolMessage(result: toolResult))
                }
            }

            // 4. Final response AFTER all tool rounds
            if !message.content.isEmpty {
                result.append(AssistantMessage(content: message.content))
            }
        } else {
            // Regular message (no tools)
            result.append(message.toAPIFormat())
        }
    }
    return result
}
```

### Expanded Format by Provider

#### OpenAI / Ollama
```json
[
  {"role": "assistant", "content": "Let me check..."},
  {"role": "assistant", "tool_calls": [{"id": "call_1", "function": {...}}]},
  {"role": "tool", "tool_call_id": "call_1", "content": "{...}"},
  {"role": "assistant", "content": "Here's what I found..."}
]
```

#### Anthropic
```json
[
  {"role": "assistant", "content": "Let me check..."},
  {"role": "assistant", "content": [{"type": "tool_use", "id": "...", ...}]},
  {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "...", ...}]},
  {"role": "assistant", "content": "Here's what I found..."}
]
```

#### Gemini
```json
[
  {"role": "model", "parts": [{"text": "Let me check..."}]},
  {"role": "model", "parts": [{"functionCall": {...}}]},
  {"role": "function", "parts": [{"functionResponse": {...}}]},
  {"role": "model", "parts": [{"text": "Here's what I found..."}]}
]
```

## Key Design Decisions

### 1. Separate Storage vs API Format
- **Storage**: Compact (tool rounds attached to message)
- **API Calls**: Expanded (separate messages per round)

This minimizes storage while maintaining API compatibility.

### 2. assistantResponse vs message.content
- `assistantResponse`: Partial text streamed BEFORE tool calls in each round
- `message.content`: Final response AFTER all tools complete

This prevents duplication when expanding for API calls.

### 3. UI Display
- During streaming: Show all text as it arrives (chunks)
- After completion: Show tool history (collapsed) + final response
- Tool history shows `assistantResponse` for each round

### 4. Maximum Rounds (50)
Prevents infinite loops. When reached:
1. Final summarization call made without tools
2. LLM forced to provide text response based on gathered data

## File Locations

| Component | File |
|-----------|------|
| Execution Loop | `Connectors/Services/ToolEnabledChatService.swift` |
| Message Formatting | `LLMProviders/*Provider.swift` (formatMessagesWithToolRounds) |
| Data Models | `Connectors/Models/ToolExecutionRound.swift` |
| Persistence Models | `Connectors/Models/ToolCallRecord.swift` |
| UI Display | `UI/PromptWindow/ChatMessageView.swift` |

## Debugging

Enable logging to trace tool execution:
```
🔧 Tool round 1 starting...
🔧 Round 1: No tool calls, generation complete
```

Or with tools:
```
🔧 Tool round 1 starting...
🔧 Tool calls started: [weather_lookup]
🔧 Tool result ready: ✅ weather_lookup
🔧 Round 1 complete: executed 1 tools
🔧 Tool round 2 starting...
🔧 Round 2: No tool calls, generation complete
🔧 Generation finished after 2 round(s), 1 new tool rounds
```
