# Tasks: Streaming Response in Prompt Mode

**Feature**: 003-streaming-response
**Created**: 2025-12-17

## Implementation Tasks

### Phase 1: PromptViewModel Streaming Integration

- [ ] **Task 1.1**: Update `generate(with:)` to use streaming
  - Replace `provider.generate()` with `provider.generateStream()`
  - Use `for try await chunk in stream` pattern
  - Append chunks to `response` property incrementally
  - Handle cancellation via `Task.isCancelled` check
  - Reference: `summarizeSelection()` already does this correctly

### Phase 2: OpenAI Provider True Streaming

- [ ] **Task 2.1**: Modify request building to enable streaming
  - Add `"stream": true` to request JSON body
  - Use `URLSession.bytes(for:)` instead of `URLSession.data(for:)`

- [ ] **Task 2.2**: Implement SSE parsing for OpenAI format
  - Parse `data: {...}` lines
  - Extract `choices[0].delta.content` field
  - Handle `data: [DONE]` termination signal
  - Handle error events

### Phase 3: Anthropic Provider True Streaming

- [ ] **Task 3.1**: Modify request building to enable streaming
  - Add `"stream": true` to request JSON body
  - Use `URLSession.bytes(for:)` instead of `URLSession.data(for:)`

- [ ] **Task 3.2**: Implement SSE parsing for Anthropic format
  - Parse `event:` and `data:` lines
  - Handle `content_block_delta` events
  - Extract `delta.text` field
  - Handle `message_stop` termination event

### Phase 4: Gemini Provider True Streaming

- [ ] **Task 4.1**: Switch to streaming endpoint
  - Use `streamGenerateContent` endpoint instead of `generateContent`
  - Use `URLSession.bytes(for:)` for NDJSON stream

- [ ] **Task 4.2**: Implement NDJSON parsing for Gemini format
  - Parse newline-delimited JSON objects
  - Extract `candidates[0].content.parts[0].text` field
  - Handle completion signal

### Phase 5: Ollama Provider True Streaming

- [ ] **Task 5.1**: Verify Ollama native streaming
  - Ollama streams by default, verify current implementation
  - Use `URLSession.bytes(for:)` if not already

- [ ] **Task 5.2**: Implement NDJSON parsing for Ollama format
  - Parse `{"response": "..."}` objects
  - Handle `{"done": true}` termination

### Phase 6: Error Handling & Edge Cases

- [ ] **Task 6.1**: Handle mid-stream errors gracefully
  - Preserve partial response on error
  - Show error message without losing content
  - Allow retry that continues from scratch

- [ ] **Task 6.2**: Handle cancellation properly
  - Stop network request immediately
  - Keep partial response visible
  - Reset `isGenerating` state

### Phase 7: Testing & Validation

- [ ] **Task 7.1**: Manual testing with each provider
  - OpenAI: Test with GPT-4, GPT-3.5
  - Anthropic: Test with Claude 3
  - Gemini: Test with Gemini Pro
  - Ollama: Test with local model

- [ ] **Task 7.2**: Test edge cases
  - Long responses (>1000 words)
  - Cancel during stream
  - Network disconnect mid-stream
  - Rate limit during stream

## Dependencies

- All providers already have `generateStream()` method signatures
- ResponseView already handles incremental `response` updates
- `summarizeSelection()` provides reference implementation for streaming pattern

## Estimated Effort

| Phase | Effort | Risk |
|-------|--------|------|
| Phase 1 | 0.5 day | Low (pattern exists in summarization) |
| Phase 2 | 1 day | Medium (SSE parsing) |
| Phase 3 | 1 day | Medium (different SSE format) |
| Phase 4 | 1 day | Medium (NDJSON format) |
| Phase 5 | 0.5 day | Low (native streaming) |
| Phase 6 | 0.5 day | Low |
| Phase 7 | 1 day | Low |

**Total**: ~5.5 days

