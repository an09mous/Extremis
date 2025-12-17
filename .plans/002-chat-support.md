# Feature Plan: Chat Support

## Feature ID
002-chat-support

## Overview
Add conversational chat functionality to the Extremis response window, allowing users to continue interacting with the AI after receiving an initial response (from summarization, generation, or transformation). Instead of a one-shot response view, users can ask follow-up questions, request clarifications, or iterate on the response in the same window.

## Motivation
Currently, Extremis provides a single response to user requests. If users want to refine the output, ask follow-up questions, or explore the topic further, they must close the window and start a new session, losing context. Chat support enables iterative workflows where users can:
- Request clarifications ("Can you explain point 2 in more detail?")
- Refine outputs ("Make it shorter" / "Add more technical details")
- Ask follow-up questions based on the response
- Have natural multi-turn conversations while maintaining full context

## Technologies
- Swift 5.9+ with Swift Concurrency (async/await)
- SwiftUI for chat UI components
- AppKit for window management integration
- Existing LLMProvider protocol for message handling

## Requirements

### Functional Requirements

#### FR-1: Chat Message Model
- Create `ChatMessage` model with: id, role (user/assistant/system), content, timestamp
- Create `ChatConversation` model to hold array of messages and metadata
- Preserve original context (selected text, source app) in conversation metadata

#### FR-2: Chat View UI
- Replace single response text with scrollable chat message list
- Display user messages right-aligned with distinct styling
- Display assistant messages left-aligned with distinct styling  
- Show message timestamps on hover or tap
- Auto-scroll to latest message when new content arrives

#### FR-3: Chat Input Field
- Add persistent text input field at bottom of response view
- Support multi-line input with Shift+Enter for newlines
- Submit on Enter key press
- Clear input after sending
- Disable input while AI is generating response

#### FR-4: Conversation History Management
- Maintain conversation history in PromptViewModel
- Pass full conversation history to LLM on each request
- Limit conversation context window (configurable, default ~10 messages)
- Include original request context in system message

#### FR-5: LLM Provider Chat Integration
- Add `generateChat(messages: [ChatMessage], context: Context)` method to LLMProvider protocol
- Add `generateChatStream(messages: [ChatMessage], context: Context)` streaming variant
- Implement in AnthropicProvider, OpenAIProvider, GeminiProvider, OllamaProvider
- Build proper multi-turn message format for each provider's API

#### FR-6: Transition from Initial Response
- When user enters text in chat input, convert to chat mode
- First message pair: original request/response becomes first assistant message
- Subsequent messages append to conversation
- Show subtle indicator when in "chat mode" vs single response

### Non-Functional Requirements

#### NFR-1: Performance
- Streaming responses should appear with <100ms latency to first chunk
- Chat history should not impact UI responsiveness
- Efficient memory management for long conversations

#### NFR-2: User Experience  
- Smooth scrolling even with many messages
- Clear visual distinction between user/assistant messages
- Keyboard-centric workflow (Enter to send, Escape to close)
- Preserve existing Insert/Copy functionality for latest response

## Architecture

### Component Changes

```
Extremis/Core/Models/
├── ChatMessage.swift (NEW)        # Chat message and conversation models
└── Context.swift                  # Unchanged

Extremis/Core/Protocols/
└── LLMProvider.swift              # Add chat methods to protocol

Extremis/LLMProviders/
├── AnthropicProvider.swift        # Implement chat methods
├── OpenAIProvider.swift           # Implement chat methods  
├── GeminiProvider.swift           # Implement chat methods
├── OllamaProvider.swift           # Implement chat methods
└── PromptBuilder.swift            # Add chat prompt building

Extremis/UI/PromptWindow/
├── ChatView.swift (NEW)           # Chat message list view
├── ChatInputView.swift (NEW)      # Chat input component
├── ChatMessageView.swift (NEW)    # Individual message bubble
├── ResponseView.swift             # Modify to support chat mode
└── PromptWindowController.swift   # Update PromptViewModel for chat
```

### Data Flow

```
User Input → ChatInputView → PromptViewModel.sendChatMessage()
    ↓
Build message array with history → LLMProvider.generateChatStream()
    ↓
Stream response → Append to conversation → Update ChatView
    ↓
User can continue chatting or Insert/Copy latest response
```

## Implementation Plan

### Phase 1: Core Models (Est: 1 hour)
1. Create `ChatMessage` struct with UUID, role enum, content, timestamp
2. Create `ChatConversation` class to manage message array
3. Add conversation state to `PromptViewModel`

### Phase 2: LLM Provider Updates (Est: 2 hours)
1. Add `generateChat` and `generateChatStream` to `LLMProvider` protocol
2. Update `PromptBuilder` with chat prompt building method
3. Implement chat methods in all providers:
   - OpenAI: Use messages array format
   - Anthropic: Use messages array format
   - Gemini: Convert to Gemini's content format
   - Ollama: Use Ollama's chat endpoint

### Phase 3: Chat UI Components (Est: 3 hours)
1. Create `ChatMessageView` - individual message bubble component
2. Create `ChatView` - scrollable message list with auto-scroll
3. Create `ChatInputView` - text input with send button
4. Style components to match existing Extremis design language

### Phase 4: Integration (Est: 2 hours)
1. Modify `ResponseView` to conditionally show chat interface
2. Update `PromptViewModel`:
   - Add conversation state management
   - Add `sendChatMessage()` method
   - Handle streaming responses in chat context
3. Update `PromptContainerView` to pass chat callbacks
4. Ensure Insert/Copy work with latest assistant message

### Phase 5: Polish & Edge Cases (Est: 1 hour)
1. Handle context window limits gracefully
2. Add loading states and error handling for chat
3. Test with all providers
4. Keyboard navigation and accessibility

## API Design

### ChatMessage Model
```swift
enum ChatRole: String, Codable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

@MainActor
class ChatConversation: ObservableObject {
    @Published var messages: [ChatMessage] = []
    let originalContext: Context?
    let initialRequest: String?  // Original instruction or "summarize"

    func addMessage(_ message: ChatMessage)
    func addUserMessage(_ content: String)
    func addAssistantMessage(_ content: String)
    var lastAssistantMessage: ChatMessage?
}
```

### LLMProvider Protocol Extension
```swift
protocol LLMProvider {
    // ... existing methods ...

    /// Generate a chat response (non-streaming)
    func generateChat(
        messages: [ChatMessage],
        context: Context?
    ) async throws -> Generation

    /// Generate a chat response with streaming
    func generateChatStream(
        messages: [ChatMessage],
        context: Context?
    ) -> AsyncThrowingStream<String, Error>
}
```

### PromptViewModel Extensions
```swift
@MainActor
final class PromptViewModel: ObservableObject {
    // ... existing properties ...

    @Published var conversation: ChatConversation?
    @Published var isChatMode: Bool = false
    @Published var chatInput: String = ""

    func initializeConversation(withResponse response: String, context: Context?)
    func sendChatMessage(_ message: String)
    func clearConversation()
}
```

## UI Mockup

```
┌─────────────────────────────────────────────────────────┐
│ ✨ Response                              [⟳ generating] │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │ [Assistant]                                      │   │
│  │ Here's a summary of the selected text:          │   │
│  │ • Point 1: Key insight about the topic          │   │
│  │ • Point 2: Another important detail             │   │
│  │ • Point 3: Conclusion and recommendations       │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│                    ┌───────────────────────────────┐    │
│                    │ [User]                        │    │
│                    │ Can you expand on point 2?   │    │
│                    └───────────────────────────────┘    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │ [Assistant]                                      │   │
│  │ Point 2 refers to...                            │   │
│  │ ████████░░░░ (streaming...)                     │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────┐ [Send] │
│ │ Ask a follow-up question...                 │        │
│ └─────────────────────────────────────────────┘        │
├─────────────────────────────────────────────────────────┤
│ [Re-prompt] [Copy]            [Cancel] [Insert ↵]      │
└─────────────────────────────────────────────────────────┘
```

## Testing Strategy

### Unit Tests
- ChatMessage and ChatConversation model tests
- PromptBuilder chat prompt generation tests
- Message array formatting for each provider

### Integration Tests
- Full chat flow with mock LLM provider
- Conversation state persistence across messages
- Context window limit handling

### Manual Testing
- Test with all 4 LLM providers
- Long conversation handling
- Rapid message sending
- Network error recovery in chat mode
- Insert/Copy functionality with chat history

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Context window overflow | High | Implement sliding window, summarize old messages |
| Provider API differences | Medium | Abstract message format conversion per provider |
| UI complexity increase | Medium | Progressive disclosure - chat input only appears after first response |
| Performance with long chats | Medium | Virtualized list, limit stored messages |

## Success Metrics
- Users can have multi-turn conversations without losing context
- Streaming responses work seamlessly in chat mode
- Insert/Copy still work for the latest response
- No degradation in initial response time

## Dependencies
- Existing LLMProvider implementations
- Current ResponseView and PromptViewModel
- SwiftUI ScrollViewReader for auto-scrolling

## Future Enhancements (Out of Scope)
- Conversation history persistence across sessions
- Export conversation to file
- Branching conversations (edit previous messages)
- Conversation search
- Message reactions/ratings

