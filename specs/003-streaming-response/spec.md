# Feature Specification: Streaming Response in Prompt Mode

**Feature Branch**: `003-streaming-response`
**Created**: 2025-12-17
**Status**: Draft
**Last Updated**: 2025-12-17
**Input**: User request to stream generated responses in prompt mode instead of waiting for full response

## Design Philosophy

**Core Insight**: Users perceive faster response times when they see text appearing incrementally. Streaming provides immediate feedback and reduces perceived latency significantly.

**Current State**: The prompt mode currently uses non-streaming `provider.generate()` which waits for the complete LLM response before displaying anything. Summarization already uses streaming via `generateRawStream()`.

**Key Change**: Replace the non-streaming `generate()` call with the streaming `generateStream()` in PromptViewModel's `generate(with:)` method, similar to how `summarizeSelection()` already works.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Streaming Generation in Prompt Mode (Priority: P1) 🎯 MVP

As a user entering an instruction in the prompt window, I want to see the AI response appear word-by-word/chunk-by-chunk as it's generated, so I get immediate feedback and can start reading before generation completes.

**Why this priority**: Improves perceived performance dramatically. Users see first tokens in ~500ms instead of waiting 3-10 seconds for full response.

**Independent Test**: Open prompt window → Type instruction → Press Enter → See response text appearing incrementally

**Acceptance Scenarios**:

1. **Given** user submits an instruction, **When** generation starts, **Then** response text begins appearing within 1-2 seconds (first token)
2. **Given** generation is streaming, **When** new chunks arrive, **Then** response view updates in real-time with each chunk
3. **Given** generation is in progress, **When** user presses Cancel/Escape, **Then** streaming stops immediately and partial response remains visible
4. **Given** network error occurs mid-stream, **When** error is detected, **Then** partial response remains visible with error message appended
5. **Given** generation completes, **When** last chunk is received, **Then** Insert/Copy buttons become enabled

---

### User Story 2 - True SSE Streaming in All Providers (Priority: P1) 🎯 MVP

As a user, I want all LLM providers (OpenAI, Anthropic, Gemini, Ollama) to stream responses using Server-Sent Events (SSE), so I get real-time token-by-token output regardless of which provider I'm using.

**Why this priority**: Currently `generateStream()` in all providers is "fake streaming" - it waits for full response then yields it all at once.

**Independent Test**: Switch between providers → Generate response → All should stream incrementally

**Acceptance Scenarios**:

1. **Given** OpenAI is selected, **When** generating, **Then** response streams via SSE (`stream: true` parameter)
2. **Given** Anthropic is selected, **When** generating, **Then** response streams via SSE (`stream: true` parameter)
3. **Given** Gemini is selected, **When** generating, **Then** response streams via SSE (streaming endpoint)
4. **Given** Ollama is selected, **When** generating, **Then** response streams via SSE (native streaming)
5. **Given** any provider, **When** API returns error mid-stream, **Then** error is surfaced without losing partial content

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: PromptViewModel MUST use `generateStream()` instead of `generate()` for all instruction-based generation
- **FR-002**: All LLM providers MUST implement true SSE streaming (not fake streaming that waits for full response)
- **FR-003**: ResponseView MUST update in real-time as chunks arrive
- **FR-004**: Cancel button MUST stop the stream immediately when pressed
- **FR-005**: Partial responses MUST be preserved if generation is cancelled or errors occur
- **FR-006**: Loading indicator MUST show during streaming until completion
- **FR-007**: Insert/Copy buttons MUST remain disabled until streaming completes
- **FR-008**: System MUST handle SSE parsing for each provider's format (OpenAI, Anthropic, Gemini, Ollama)

### Non-Functional Requirements

- **NFR-001**: First token MUST appear within 2 seconds of request for 90% of generations
- **NFR-002**: UI MUST remain responsive during streaming (no blocking main thread)
- **NFR-003**: Memory usage MUST NOT grow unbounded during long streams

## Technical Design

### Current Architecture (Non-Streaming)

```
PromptViewModel.generate(with:)
    └── provider.generate(instruction:, context:)  ← Waits for full response
            └── URLSession.data(for:)              ← Blocking HTTP call
                    └── Response arrives (3-10 sec)
                            └── viewModel.response = generation.content
```

### Target Architecture (Streaming)

```
PromptViewModel.generate(with:)
    └── provider.generateStream(instruction:, context:)  ← Returns AsyncThrowingStream
            └── URLSession.bytes(for:)                   ← SSE stream
                    └── for await chunk in stream:
                            └── viewModel.response += chunk  ← Real-time updates
```

### Provider-Specific SSE Formats

#### OpenAI Format
```
data: {"id":"...","choices":[{"delta":{"content":"Hello"}}]}
data: {"id":"...","choices":[{"delta":{"content":" world"}}]}
data: [DONE]
```

#### Anthropic Format
```
event: content_block_delta
data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" world"}}

event: message_stop
data: {"type":"message_stop"}
```

#### Gemini Format
```
{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}
{"candidates":[{"content":{"parts":[{"text":" world"}]}}]}
```

#### Ollama Format (Native Streaming)
```
{"response":"Hello"}
{"response":" world"}
{"done":true}
```

### Files to Modify

| File | Changes |
|------|---------|
| `Extremis/UI/PromptWindow/PromptWindowController.swift` | Change `generate()` to use streaming loop |
| `Extremis/LLMProviders/OpenAIProvider.swift` | Implement true SSE streaming in `generateStream()` |
| `Extremis/LLMProviders/AnthropicProvider.swift` | Implement true SSE streaming in `generateStream()` |
| `Extremis/LLMProviders/GeminiProvider.swift` | Implement true SSE streaming in `generateStream()` |
| `Extremis/LLMProviders/OllamaProvider.swift` | Implement true SSE streaming in `generateStream()` |

### Code Changes

#### 1. PromptViewModel.generate(with:) - Use Streaming

```swift
// BEFORE (current - waits for full response)
let generation = try await RetryHelper.withRetry(configuration: .default) {
    try await provider.generate(instruction: self.instructionText, context: context)
}
response = generation.content

// AFTER (streaming)
let stream = provider.generateStream(instruction: self.instructionText, context: context)
for try await chunk in stream {
    guard !Task.isCancelled else { return }
    response += chunk
}
```

#### 2. Provider SSE Implementation Pattern

```swift
func generateStream(instruction: String, context: Context) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        Task {
            guard let apiKey = apiKey else {
                continuation.finish(throwing: LLMProviderError.notConfigured(provider: .openai))
                return
            }

            let prompt = PromptBuilder.shared.buildPrompt(instruction: instruction, context: context)
            var request = try buildRequest(apiKey: apiKey, prompt: prompt)
            // Add stream: true to request body

            let (bytes, response) = try await session.bytes(for: request)

            for try await line in bytes.lines {
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                // Parse SSE line and extract content delta
                if let content = parseSSELine(line) {
                    continuation.yield(content)
                }
            }

            continuation.finish()
        }
    }
}
```

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: First token appears within 2 seconds of request in 90% of generations
- **SC-002**: Response view updates at least every 100ms during active streaming
- **SC-003**: Cancellation stops network request within 500ms
- **SC-004**: All 4 providers (OpenAI, Anthropic, Gemini, Ollama) support true streaming
- **SC-005**: No UI jank or freezing during streaming (main thread stays responsive)
- **SC-006**: Partial responses are preserved on cancel/error

