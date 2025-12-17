# Tasks: Chat Support (002-chat-support)

## Phase 1: Core Models

### 1.1 Create ChatMessage Model
- [ ] Create `Extremis/Core/Models/ChatMessage.swift`
- [ ] Define `ChatRole` enum with cases: `system`, `user`, `assistant`
- [ ] Create `ChatMessage` struct with: `id: UUID`, `role: ChatRole`, `content: String`, `timestamp: Date`
- [ ] Make `ChatMessage` conform to `Identifiable`, `Codable`, `Equatable`
- [ ] Add convenience initializer that auto-generates `id` and `timestamp`

### 1.2 Create ChatConversation Model
- [ ] Create `ChatConversation` class in same file
- [ ] Add `@Published var messages: [ChatMessage]` property
- [ ] Add `originalContext: Context?` property for initial context preservation
- [ ] Add `initialRequest: String?` property to track original instruction
- [ ] Implement `addMessage(_ message: ChatMessage)` method
- [ ] Implement `addUserMessage(_ content: String)` convenience method
- [ ] Implement `addAssistantMessage(_ content: String)` convenience method
- [ ] Add computed property `lastAssistantMessage: ChatMessage?`
- [ ] Add computed property `lastAssistantContent: String` for Insert/Copy
- [ ] Make class `@MainActor` and conform to `ObservableObject`

## Phase 2: LLM Provider Updates

### 2.1 Update LLMProvider Protocol
- [ ] Add `generateChat(messages: [ChatMessage], context: Context?) async throws -> Generation`
- [ ] Add `generateChatStream(messages: [ChatMessage], context: Context?) -> AsyncThrowingStream<String, Error>`
- [ ] Document that `context` is optional and used for system message enrichment

### 2.2 Update PromptBuilder for Chat
- [ ] Add `buildChatSystemPrompt(context: Context?) -> String` method
- [ ] Add `formatMessagesForProvider(messages: [ChatMessage], provider: LLMProviderType) -> [[String: Any]]` helper
- [ ] Ensure system prompt includes original context (app, window, selected text summary)

### 2.3 Implement Chat in OpenAIProvider
- [ ] Implement `generateChat` using `/chat/completions` with messages array
- [ ] Implement `generateChatStream` with SSE streaming
- [ ] Format messages as `[{"role": "...", "content": "..."}]`
- [ ] Include system message with context at start of array

### 2.4 Implement Chat in AnthropicProvider
- [ ] Implement `generateChat` using `/messages` endpoint
- [ ] Implement `generateChatStream` with SSE streaming
- [ ] Format messages per Anthropic API (system separate from messages)
- [ ] Handle Anthropic's alternating user/assistant requirement

### 2.5 Implement Chat in GeminiProvider
- [ ] Implement `generateChat` using Gemini's `contents` format
- [ ] Implement `generateChatStream` with NDJSON streaming
- [ ] Convert ChatMessage roles to Gemini's `user`/`model` roles
- [ ] Include system instruction in generation config

### 2.6 Implement Chat in OllamaProvider
- [ ] Implement `generateChat` using OpenAI-compatible `/chat/completions`
- [ ] Implement `generateChatStream` with streaming
- [ ] Format similar to OpenAI provider

## Phase 3: Chat UI Components

### 3.1 Create ChatMessageView
- [ ] Create `Extremis/UI/PromptWindow/ChatMessageView.swift`
- [ ] Accept `ChatMessage` as input
- [ ] Style user messages: right-aligned, accent background color
- [ ] Style assistant messages: left-aligned, secondary background color
- [ ] Show timestamp on hover (use `.help()` modifier)
- [ ] Support text selection with `.textSelection(.enabled)`
- [ ] Handle streaming state (show cursor/loading for incomplete assistant message)

### 3.2 Create ChatView
- [ ] Create `Extremis/UI/PromptWindow/ChatView.swift`
- [ ] Accept `[ChatMessage]` binding and `isGenerating` state
- [ ] Use `ScrollViewReader` for programmatic scrolling
- [ ] Implement auto-scroll to bottom when new message arrives
- [ ] Use `LazyVStack` for performance with many messages
- [ ] Add empty state when no messages yet
- [ ] Show generating placeholder for streaming response

### 3.3 Create ChatInputView
- [ ] Create `Extremis/UI/PromptWindow/ChatInputView.swift`
- [ ] Accept `@Binding var text: String` and `onSend: () -> Void`
- [ ] Use `SubmittableTextEditor` pattern (Enter to send, Shift+Enter for newline)
- [ ] Add Send button with icon
- [ ] Disable input and button when `isGenerating` is true
- [ ] Clear text field after successful send
- [ ] Placeholder text: "Ask a follow-up question..."
- [ ] Style to match existing PromptInputView aesthetic

## Phase 4: Integration

### 4.1 Update PromptViewModel for Chat
- [ ] Add `@Published var conversation: ChatConversation?` property
- [ ] Add `@Published var isChatMode: Bool = false` property
- [ ] Add `@Published var chatInput: String = ""` property
- [ ] Implement `initializeConversation(withResponse:context:)` method
  - Creates conversation with initial assistant message
  - Stores original context
- [ ] Implement `sendChatMessage(_ message: String)` method
  - Adds user message to conversation
  - Calls `generateChatStream` on active provider
  - Streams response into new assistant message
  - Handles errors gracefully
- [ ] Implement `clearConversation()` method for reset
- [ ] Update `reset()` to also clear conversation state

### 4.2 Update ResponseView for Chat Mode
- [ ] Modify ResponseView to accept `conversation: ChatConversation?`
- [ ] Add `onSendChat: (String) -> Void` callback
- [ ] Add `chatInput: Binding<String>` binding
- [ ] Conditionally show:
  - Single response text when `conversation == nil`
  - ChatView when `conversation != nil`
- [ ] Always show ChatInputView at bottom when response is complete
- [ ] Update Insert button to use `conversation?.lastAssistantContent ?? response`
- [ ] Update Copy button similarly

### 4.3 Update PromptContainerView
- [ ] Pass conversation from viewModel to ResponseView
- [ ] Pass chatInput binding
- [ ] Pass onSendChat callback that calls `viewModel.sendChatMessage`
- [ ] Ensure Re-prompt clears conversation and goes back to input

### 4.4 Update PromptWindowController
- [ ] Update `updateContentView()` to pass new chat parameters
- [ ] Ensure conversation persists across view updates
- [ ] Update `hidePrompt()` to clear conversation

## Phase 5: Polish & Edge Cases

### 5.1 Context Window Management
- [ ] Add `maxMessages` constant (default: 20 messages)
- [ ] Implement message trimming when limit exceeded
- [ ] Keep system message + recent N messages
- [ ] Log when messages are trimmed

### 5.2 Error Handling in Chat
- [ ] Handle network errors during chat - show error in conversation
- [ ] Allow retry of failed message
- [ ] Handle provider not configured error
- [ ] Handle rate limiting gracefully

### 5.3 UI Polish
- [ ] Add subtle "Chat mode" indicator in header
- [ ] Smooth scroll animation when new messages arrive
- [ ] Focus chat input after response completes
- [ ] Keyboard shortcut: Escape to close, Enter to send
- [ ] Visual feedback when sending message

### 5.4 Testing
- [ ] Create `Extremis/Tests/Core/ChatMessageTests.swift`
  - Test ChatMessage creation and encoding
  - Test ChatConversation add/remove operations
  - Test lastAssistantMessage computed property
- [ ] Create `Extremis/Tests/LLMProviders/ChatProviderTests.swift`
  - Test message formatting for each provider
  - Test system prompt generation with context
- [ ] Manual testing checklist:
  - [ ] Test chat flow with OpenAI
  - [ ] Test chat flow with Anthropic
  - [ ] Test chat flow with Gemini
  - [ ] Test chat flow with Ollama
  - [ ] Test long conversation (20+ messages)
  - [ ] Test Insert with latest response
  - [ ] Test Copy with latest response
  - [ ] Test Re-prompt clears conversation
  - [ ] Test Cancel closes window

## Summary

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| Phase 1: Core Models | 10 | 1 hour |
| Phase 2: LLM Providers | 18 | 2 hours |
| Phase 3: Chat UI | 14 | 3 hours |
| Phase 4: Integration | 14 | 2 hours |
| Phase 5: Polish | 16 | 1 hour |
| **Total** | **72 tasks** | **~9 hours** |

## Dependencies Graph

```
Phase 1 (Models)
    ↓
Phase 2 (Providers) ←──┐
    ↓                  │
Phase 3 (UI) ──────────┘
    ↓
Phase 4 (Integration)
    ↓
Phase 5 (Polish)
```

Note: Phase 2 and Phase 3 can be worked on in parallel after Phase 1 is complete.

