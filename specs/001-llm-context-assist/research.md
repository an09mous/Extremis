# Research: Extremis - Context-Aware LLM Writing Assistant

**Branch**: `001-llm-context-assist` | **Date**: 2025-12-06

## Research Areas

### 1. macOS Global Hotkey Registration

**Decision**: Use Carbon's `RegisterEventHotKey` API wrapped in Swift

**Rationale**:
- Most reliable method for system-wide hotkeys on macOS
- Works regardless of which app has focus
- Used by established apps (Alfred, Raycast, Spotlight)
- AppKit's `NSEvent.addGlobalMonitorForEvents` doesn't capture all key events

**Alternatives Considered**:
| Alternative | Why Rejected |
|-------------|--------------|
| NSEvent global monitor | Doesn't work for all key combinations, less reliable |
| CGEvent tap | Requires more permissions, complex setup |
| MASShortcut library | External dependency, Carbon wrapper works fine |

**Implementation Notes**:
- Wrap Carbon APIs in Swift-friendly `HotkeyManager` class
- Handle hotkey conflicts gracefully
- Default: ⌘+Shift+Space (avoid conflicts with Spotlight ⌘+Space)

---

### 2. Accessibility APIs for Context Extraction

**Decision**: Use `AXUIElement` APIs from ApplicationServices framework

**Rationale**:
- Direct access to UI element hierarchy without screenshots
- Can read text content, labels, values from focused elements
- Works with native apps and most Electron apps (Slack desktop)
- Respects user privacy - only accesses what's needed

**Key APIs**:
```swift
AXUIElementCopyAttributeValue()  // Get element properties
AXUIElementCopyAttributeNames()  // Discover available attributes
kAXFocusedUIElementAttribute     // Get currently focused element
kAXValueAttribute                // Text content
kAXSelectedTextAttribute         // User-selected text
kAXChildrenAttribute             // Navigate element tree
```

**Permissions Required**:
- Accessibility permission in System Preferences > Privacy & Security
- Must guide user to grant permission on first launch

---

### 3. Browser DOM Access Strategy

**Decision**: Use AppleScript (Safari) and Chrome DevTools Protocol/AppleScript (Chrome)

**Rationale**:
- No browser extension required - works immediately
- AppleScript can execute JavaScript in browser tabs
- Avoids screenshot + OCR complexity
- Targeted extraction of specific DOM elements

**Safari Approach**:
```applescript
tell application "Safari"
    do JavaScript "document.querySelector('.message-input').innerText" in current tab of front window
end tell
```

**Chrome Approach**:
```applescript
tell application "Google Chrome"
    execute front window's active tab javascript "..."
end tell
```

**App-Specific Selectors** (to be refined during implementation):
| App | Key Selectors |
|-----|---------------|
| Slack | `.p-message_pane`, `.c-message_kit__text`, `[data-qa="message_input"]` |
| Gmail | `.editable`, `.a3s.aiL` (email body), `.gD` (sender) |
| GitHub | `.comment-form-textarea`, `.diff-table`, `.gh-header-title` |

---

### 4. Text Insertion Strategy

**Decision**: Use Accessibility APIs with clipboard fallback

**Rationale**:
- `AXUIElementSetAttributeValue` with `kAXValueAttribute` is cleanest
- Falls back to clipboard paste (⌘V) if AX fails
- Must preserve original clipboard content

**Flow**:
1. Try `AXUIElementSetAttributeValue` on focused element
2. If fails: Save clipboard → Copy generated text → Paste → Restore clipboard
3. Return focus to original application

---

### 5. LLM Provider Integration

**Decision**: Protocol-based abstraction with async/await

**Rationale**:
- Clean separation allows adding providers without changing core code
- Swift's async/await provides clean API for network calls
- Streaming support for real-time response display

**Provider Comparison**:
| Provider | API Style | Streaming | Notes |
|----------|-----------|-----------|-------|
| OpenAI | REST | SSE | Most mature, GPT-4 Turbo recommended |
| Anthropic | REST | SSE | Claude 3 Sonnet/Opus, excellent for writing |
| Google Gemini | REST | SSE | Gemini Pro, good free tier |

**Common Protocol**:
```swift
protocol LLMProvider {
    var name: String { get }
    var isConfigured: Bool { get }
    func generate(prompt: String, context: Context) async throws -> Generation
    func generateStream(prompt: String, context: Context) -> AsyncThrowingStream<String, Error>
}
```

---

### 6. Menu Bar App Architecture

**Decision**: NSStatusItem with SwiftUI popover/window

**Rationale**:
- Standard macOS pattern for background utilities
- `LSUIElement = true` in Info.plist hides Dock icon
- SwiftUI for modern, maintainable UI code

**Key Components**:
- `NSStatusItem` for menu bar icon
- `NSPanel` (floating window) for prompt - allows focus without activating app
- SwiftUI views embedded in AppKit hosting

---

### 7. Secure API Key Storage

**Decision**: macOS Keychain via Security framework

**Rationale**:
- Industry standard for sensitive data on macOS
- Encrypted at rest, protected by user login
- Survives app updates and reinstalls

**Implementation**:
```swift
// Store
SecItemAdd([kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: "openai-api-key",
            kSecValueData: keyData])

// Retrieve
SecItemCopyMatching([kSecClass: kSecClassGenericPassword,
                     kSecAttrAccount: "openai-api-key",
                     kSecReturnData: true])
```

---

### 8. Conversation History (Phase 2 Preparation)

**Decision**: In-memory array for Phase 1, protocol ready for persistence

**Rationale**:
- User specified: don't persist conversations now, but make extensible
- Protocol allows swapping storage backend later

**Extensibility Interface**:
```swift
protocol ConversationStore {
    func save(_ conversation: Conversation) async throws
    func load(id: UUID) async throws -> Conversation?
    func recent(limit: Int) async throws -> [Conversation]
}

// Phase 1: InMemoryConversationStore
// Phase 2: CoreDataConversationStore or SQLiteConversationStore
```

---

## Technology Stack Summary

| Component | Technology | Justification |
|-----------|------------|---------------|
| Language | Swift 5.9+ | Native macOS, type-safe, async/await |
| UI Framework | SwiftUI + AppKit | Modern UI with system integration |
| Hotkeys | Carbon APIs | Most reliable for global hotkeys |
| Context Extraction | AXUIElement | Privacy-respecting, no screenshots |
| Browser Integration | AppleScript + JS | No extension required |
| Secure Storage | Keychain | Standard macOS secure storage |
| Preferences | UserDefaults | Simple, appropriate for settings |
| Networking | URLSession | Native, async/await support |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Accessibility permission denied | Medium | High | Clear onboarding flow with instructions |
| Browser DOM structure changes | Medium | Medium | Graceful degradation to selected text |
| LLM API rate limits | Low | Medium | Retry with backoff, user notification |
| Hotkey conflict with other apps | Medium | Low | Customizable hotkey, conflict detection |
| Electron apps with custom accessibility | Medium | Medium | Test with Slack desktop, fallback to clipboard |

