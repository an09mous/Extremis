# Implementation Plan: Streaming Response in Prompt Mode

**Feature**: 003-streaming-response
**Created**: 2025-12-17
**Status**: Planning

## Overview

Add true streaming support to prompt mode generation, so users see AI responses appearing word-by-word instead of waiting for the complete response. This dramatically improves perceived performance.

## Current State Analysis

### What Works
- `LLMProvider` protocol already defines `generateStream()` method
- All 4 providers implement the method signature
- `summarizeSelection()` already uses streaming pattern correctly
- ResponseView already handles incremental response updates

### What Needs Change
- **PromptViewModel.generate()**: Uses non-streaming `provider.generate()`
- **All providers**: `generateStream()` is "fake streaming" - waits for full response then yields all at once
- **Request building**: Need to add `stream: true` parameter
- **Response parsing**: Need SSE/NDJSON parsers for each provider format

## Implementation Order

### Step 1: Quick Win - PromptViewModel (30 mins)

Change `generate(with:)` to use the existing `generateStream()` method. This will work immediately even with "fake streaming" - no visible change but sets up the infrastructure.

```swift
// Change from:
let generation = try await provider.generate(...)
response = generation.content

// Change to:
let stream = provider.generateStream(...)
for try await chunk in stream {
    response += chunk
}
```

### Step 2: OpenAI True Streaming (2-3 hours)

1. Modify `buildRequest()` to add `"stream": true`
2. Create `buildStreamRequest()` variant
3. Replace `URLSession.data(for:)` with `URLSession.bytes(for:)`
4. Parse SSE format: `data: {"choices":[{"delta":{"content":"..."}}]}`

### Step 3: Anthropic True Streaming (2-3 hours)

1. Add `"stream": true` to request body
2. Parse SSE with events: `event: content_block_delta`
3. Extract from: `{"delta":{"text":"..."}}`

### Step 4: Gemini True Streaming (2-3 hours)

1. Switch endpoint to `streamGenerateContent`
2. Parse NDJSON format
3. Extract from: `{"candidates":[{"content":{"parts":[{"text":"..."}]}}]}`

### Step 5: Ollama True Streaming (1-2 hours)

1. Ollama streams by default - verify/fix implementation
2. Parse: `{"response":"..."}` objects
3. Handle: `{"done":true}` termination

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| SSE parsing complexity | Start with OpenAI (most common), reuse patterns |
| Provider API differences | Handle each provider separately, don't over-abstract |
| Rate limiting during stream | Existing RetryHelper can be adapted for stream errors |
| Memory leaks from unclosed streams | Ensure proper `continuation.finish()` on all paths |

## Rollback Plan

If streaming causes issues:
1. Keep non-streaming `generate()` methods intact
2. Add feature flag to switch between streaming/non-streaming
3. Default to non-streaming if provider doesn't support it properly

## Success Metrics

- [ ] First token appears within 2 seconds
- [ ] All 4 providers stream correctly
- [ ] Cancel stops streaming immediately
- [ ] No UI freezing during streaming
- [ ] Partial responses preserved on error

