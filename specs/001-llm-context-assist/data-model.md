# Data Model: Extremis

**Branch**: `001-llm-context-assist` | **Date**: 2025-12-06

## Core Entities

### Context

Represents the captured state when Extremis is activated.

```swift
struct Context: Codable, Equatable {
    let id: UUID
    let capturedAt: Date
    let source: ContextSource
    let selectedText: String?
    let surroundingText: String?
    let metadata: ContextMetadata
}

struct ContextSource: Codable, Equatable {
    let applicationName: String      // e.g., "Slack", "Google Chrome"
    let bundleIdentifier: String     // e.g., "com.tinyspeck.slackmacgap"
    let windowTitle: String?         // e.g., "#general - Slack"
    let url: URL?                    // For browser-based apps
}

enum ContextMetadata: Codable, Equatable {
    case slack(SlackMetadata)
    case gmail(GmailMetadata)
    case github(GitHubMetadata)
    case generic(GenericMetadata)
}

struct SlackMetadata: Codable, Equatable {
    let channelName: String?         // Channel or DM name
    let channelType: SlackChannelType
    let participants: [String]       // Usernames in conversation
    let recentMessages: [SlackMessage]
    let threadId: String?            // If in a thread
}

enum SlackChannelType: String, Codable {
    case channel, directMessage, groupDM, thread
}

struct SlackMessage: Codable, Equatable {
    let sender: String
    let content: String
    let timestamp: Date?
}

struct GmailMetadata: Codable, Equatable {
    let subject: String?
    let recipients: [String]         // To, CC
    let sender: String?              // For replies
    let threadMessages: [EmailMessage]
    let draftBody: String?
    let isReply: Bool
}

struct EmailMessage: Codable, Equatable {
    let from: String
    let content: String
    let date: Date?
}

struct GitHubMetadata: Codable, Equatable {
    let prTitle: String?
    let prNumber: Int?
    let baseBranch: String?
    let headBranch: String?
    let changedFiles: [String]       // File names
    let existingDescription: String?
    let reviewComments: [ReviewComment]
}

struct ReviewComment: Codable, Equatable {
    let author: String
    let content: String
    let filePath: String?
    let lineNumber: Int?
}

struct GenericMetadata: Codable, Equatable {
    let focusedElementRole: String?  // e.g., "AXTextField"
    let focusedElementLabel: String?
}
```

### Instruction

The user's natural language request.

```swift
struct Instruction: Codable, Equatable {
    let id: UUID
    let text: String                 // User's prompt text
    let createdAt: Date
    let contextId: UUID              // Reference to associated context
}
```

### Generation

The AI-produced response.

```swift
struct Generation: Codable, Equatable {
    let id: UUID
    let instructionId: UUID
    let provider: LLMProviderType
    let content: String              // Generated text
    let createdAt: Date
    let tokenUsage: TokenUsage?
    let latencyMs: Int?
}

struct TokenUsage: Codable, Equatable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

enum LLMProviderType: String, Codable, CaseIterable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case gemini = "Gemini"
}
```

### Preferences

User settings and configuration.

```swift
struct Preferences: Codable, Equatable {
    var hotkey: HotkeyConfiguration
    var activeProvider: LLMProviderType
    var launchAtLogin: Bool
    var appearance: AppearanceSettings
}

struct HotkeyConfiguration: Codable, Equatable {
    var keyCode: UInt32              // Carbon key code
    var modifiers: UInt32            // Carbon modifier flags
    
    static let `default` = HotkeyConfiguration(
        keyCode: 49,                 // Space
        modifiers: 0x100 | 0x200     // Cmd + Shift
    )
}

struct AppearanceSettings: Codable, Equatable {
    var theme: Theme
    var promptWindowWidth: CGFloat
    var promptWindowHeight: CGFloat
    
    enum Theme: String, Codable, CaseIterable {
        case system, light, dark
    }
    
    static let `default` = AppearanceSettings(
        theme: .system,
        promptWindowWidth: 600,
        promptWindowHeight: 400
    )
}
```

---

## Conversation (Phase 2 Ready)

In-memory conversation tracking, ready for persistence in Phase 2.

```swift
struct Conversation: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    var turns: [ConversationTurn]
    var context: Context
}

struct ConversationTurn: Codable {
    let instruction: Instruction
    let generation: Generation?
    let status: TurnStatus
}

enum TurnStatus: String, Codable {
    case pending, generating, completed, failed, cancelled
}
```

---

## Entity Relationships

```
┌─────────────┐         ┌──────────────┐
│   Context   │◄────────│  Instruction │
│             │   1:N   │              │
└─────────────┘         └──────┬───────┘
       │                       │
       │                       │ 1:1
       ▼                       ▼
┌─────────────┐         ┌──────────────┐
│ContextMeta  │         │  Generation  │
│ (Slack/     │         │              │
│  Gmail/     │         └──────────────┘
│  GitHub)    │
└─────────────┘

┌─────────────┐
│ Preferences │ (Singleton - UserDefaults)
└─────────────┘

┌─────────────┐
│Conversation │ (In-memory for Phase 1)
│   Turns[]   │
└─────────────┘
```

---

## Validation Rules

| Entity | Field | Rule |
|--------|-------|------|
| Instruction | text | Non-empty, max 4000 chars |
| Generation | content | May be empty (error state) |
| HotkeyConfiguration | keyCode | Valid Carbon key code |
| SlackMetadata | recentMessages | Max 20 messages for context |
| GmailMetadata | threadMessages | Max 10 messages for context |
| GitHubMetadata | changedFiles | Max 50 files listed |

---

## State Transitions

### Generation Lifecycle

```
[Created] → [Pending] → [Generating] → [Completed]
                │              │
                │              └──→ [Failed]
                │
                └──→ [Cancelled]
```

### Prompt Window States

```
[Hidden] ──hotkey──→ [Visible/Input] ──submit──→ [Visible/Loading]
    ▲                     │                           │
    │                     │ escape                    │
    │                     ▼                           ▼
    └────────────── [Hidden] ←────────── [Visible/Result]
                                              │
                                              │ accept/escape
                                              ▼
                                          [Hidden]
```

