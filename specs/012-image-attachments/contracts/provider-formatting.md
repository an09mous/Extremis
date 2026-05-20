# Contract: Provider Multimodal Message Formatting

**Module**: Each provider in `LLMProviders/`
**Coordination**: `LLMProviders/PromptBuilder.swift`

## PromptBuilder Extension

```swift
extension PromptBuilder {
    /// Format a ChatMessage's content for multimodal API requests.
    /// Returns structured content when images are present, plain string when not.
    /// - Parameters:
    ///   - message: The ChatMessage to format
    /// - Returns: Either a String (text-only) or [[String: Any]] (multimodal)
    func formatMessageContent(_ message: ChatMessage) -> Any

    /// Format all chat messages, handling multimodal content.
    /// Returns [[String: Any]] where "content" may be String or Array.
    func formatChatMessagesMultimodal(messages: [ChatMessage]) -> [[String: Any]]
}
```

## Per-Provider Content Block Formats

### OpenAI

```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "Describe this image"},
    {
      "type": "image_url",
      "image_url": {
        "url": "data:image/jpeg;base64,{base64data}",
        "detail": "auto"
      }
    }
  ]
}
```

**Notes**: When content is text-only, continues to use `"content": "string"` format (backward compatible). The `detail` parameter defaults to `"auto"`.

### Anthropic

```json
{
  "role": "user",
  "content": [
    {
      "type": "image",
      "source": {
        "type": "base64",
        "media_type": "image/jpeg",
        "data": "{base64data}"
      }
    },
    {"type": "text", "text": "Describe this image"}
  ]
}
```

**Notes**: Images should be placed BEFORE text in the content array for best results (per Anthropic docs). System prompt remains separate (not in messages array).

### Gemini

```json
{
  "role": "user",
  "parts": [
    {
      "inlineData": {
        "mimeType": "image/jpeg",
        "data": "{base64data}"
      }
    },
    {"text": "Describe this image"}
  ]
}
```

**Notes**: Gemini uses `parts` array instead of `content`. Each part is either `text` or `inlineData`.

### Ollama

```json
{
  "role": "user",
  "content": "Describe this image",
  "images": ["{raw_base64_no_prefix}"]
}
```

**Notes**: Ollama uses a separate `images` field (not content blocks). Base64 data must NOT include the `data:image/...;base64,` prefix. Content remains a plain string. Multiple images go as separate array elements.

## Behavior Contract

1. **Backward compatibility**: Text-only messages MUST use the existing format (string content) — no content arrays for text-only.
2. **Image ordering**: Images placed before text in content blocks (Anthropic best practice, works for all providers).
3. **Multiple images**: All images from `message.imageAttachments` are included as separate content blocks/parts.
4. **Image-only messages**: When text is empty and images are present, omit the text content block entirely (per FR-018 + clarification: no injected prompt).
5. **Non-vision models**: If model lacks `supportsVision`, image attachments are silently stripped from the message before formatting (defense in depth — UI should prevent this).
6. **Base64 encoding**: Use `ImageProcessor.base64Encode()` for consistent encoding.
