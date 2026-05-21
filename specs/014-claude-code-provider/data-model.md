# Data Model: Claude Code CLI Provider

**Feature**: 014-claude-code-provider
**Date**: 2026-05-21

## Entities

### LLMProviderType (Extension)

Add new case to existing enum in `Generation.swift`:

```swift
case claudeCode = "Claude Code"
```

**New properties**:
- `displayName`: "Claude Code (CLI)"
- `requiresAPIKey`: `false`
- `availableModels`: Loaded from `models.json` under `"claudecode"` key
- `defaultModel`: `sonnet`

### ClaudeCodeProvider

New `@MainActor` class implementing `LLMProvider`:

```swift
@MainActor
final class ClaudeCodeProvider: LLMProvider, ObservableObject {
    let providerType: LLMProviderType = .claudeCode

    @Published private(set) var currentModel: LLMModel
    @Published private(set) var cliAvailable: Bool = false
    @Published private(set) var cliAuthenticated: Bool = false

    var isConfigured: Bool { cliAvailable && cliAuthenticated }
    var displayName: String { "\(providerType.displayName) (\(currentModel.name))" }

    private var cliBinaryPath: String  // Default: "claude", configurable
    private var allowedTools: [String] = []  // User-configured tool approvals
    private var processManager: ClaudeCodeProcessManager?  // Persistent process
}
```

**State**:
- `cliAvailable`: Whether `claude` binary is found at configured path
- `cliAuthenticated`: Whether CLI is authenticated (has valid session)
- `cliBinaryPath`: Path to claude binary (default: "claude", resolved via PATH)
- `allowedTools`: List of tool names user has approved for auto-execution
- `currentModel`: Currently selected model alias

**Persistence (UserDefaults)**:
- `claudecode_model`: Selected model ID (String)
- `claudecode_binary_path`: Custom binary path (String, optional)
- `claudecode_allowed_tools`: Approved tool names (JSON-encoded [String])

### ClaudeCodeProcessManager

Manages the persistent CLI process lifecycle:

```swift
@MainActor
final class ClaudeCodeProcessManager {
    @Published private(set) var processState: ProcessState = .stopped

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    enum ProcessState {
        case stopped
        case starting
        case ready       // Process running, waiting for messages
        case generating  // Currently processing a message
        case error(String)
    }

    /// Launch the persistent claude process (no-op if already running)
    func start(binaryPath: String, model: String, allowedTools: [String], systemPrompt: String?) async throws

    /// Send a user message; lazily restarts process if it crashed
    func sendMessage(_ content: String) -> AsyncThrowingStream<CLIStreamEvent, Error>

    /// Terminate the process and close all pipes; safe to call multiple times
    func stop()

    /// Cleanup helper — registered in NSApplication.willTerminateNotification
    func forceCleanup()
}
```

**Lifecycle**:
- `start()` called when Claude Code provider is activated; no-op if already `.ready`/`.starting`
- `stop()` called on provider switch or app quit; closes pipes, terminates process
- On crash: state → `.stopped`; next `sendMessage()` triggers lazy restart (no restart loops)
- `forceCleanup()` registered in `NSApplication.willTerminateNotification` to prevent dangling processes
- Process reference is sole strong ref — no leaked closures or notification handlers holding refs

### CLIStreamEvent

Parsed representation of a single JSONL line from `--output-format stream-json`:

```swift
struct CLIStreamEvent: Decodable {
    let type: String  // "system", "stream_event", "assistant", "result"
    let event: StreamEventPayload?  // For stream_event type
    let subtype: String?  // For system/result types (e.g., "init", "success", "error")
    let sessionId: String?
    let totalCostUsd: Double?
}

struct StreamEventPayload: Decodable {
    let type: String  // "content_block_start", "content_block_delta", "content_block_stop"
    let index: Int?
    let contentBlock: ContentBlock?  // For content_block_start
    let delta: ContentDelta?  // For content_block_delta
}

struct ContentBlock: Decodable {
    let type: String  // "text", "tool_use", "tool_result"
    let id: String?  // For tool_use
    let name: String?  // For tool_use
    let toolUseId: String?  // For tool_result
    let content: String?  // For tool_result
}

struct ContentDelta: Decodable {
    let type: String  // "text_delta", "input_json_delta"
    let text: String?  // For text_delta
    let partialJson: String?  // For input_json_delta
}
```

### CLIToolInfo

Represents a tool available in the Claude Code CLI (captured from system/init events):

```swift
struct CLIToolInfo: Codable, Identifiable, Hashable {
    let name: String  // e.g., "Bash", "Read", "Edit"
    var isApproved: Bool  // User's approval state

    var id: String { name }
}
```

## models.json Entry

Add to `Extremis/Resources/models.json` under `providers`:

```json
"claudecode": {
    "models": [
        {
            "id": "sonnet",
            "name": "Sonnet",
            "description": "Recommended daily model — fast, capable",
            "capabilities": {
                "supportsTools": false,
                "supportsVision": false
            }
        },
        {
            "id": "opus",
            "name": "Opus",
            "description": "Maximum capability — complex reasoning, extended thinking",
            "capabilities": {
                "supportsTools": false,
                "supportsVision": false
            }
        },
        {
            "id": "haiku",
            "name": "Haiku",
            "description": "Fast, lightweight — 3x cost savings",
            "capabilities": {
                "supportsTools": false,
                "supportsVision": false
            }
        }
    ],
    "default": "sonnet"
}
```

**Note**: `supportsTools` is `false` because Extremis does NOT execute tools for this provider (display-only). `supportsVision` is `false` because passing images via CLI stdin is not supported in `-p` mode.

## State Transitions

### Provider Lifecycle

```
[Not Detected] → checkCLI() → [CLI Found] → activate() → [Starting Process]
  [Starting Process] → system/init event → [Ready]
  [Starting Process] → error/timeout → [Error] → retry → [Starting Process]
                → checkCLI() → [CLI Not Found]
```

### Process Lifecycle

```
[Stopped] → start() → [Starting] → system/init received → [Ready]
  [Ready] → sendMessage() → [Generating]
  [Generating] → text_delta events → yield chunks → [Generating]
  [Generating] → result/success → [Ready] (waiting for next message)
  [Generating] → result/error → [Ready] (report error, process stays alive)
  [Ready/Generating] → process crash → [Error] → auto-restart → [Starting]
  [Ready/Generating] → stop() → [Stopped]
```

### Provider Deactivation

```
[Any State] → user switches provider → stop() → [Stopped]
[Any State] → Extremis quits → stop() → [Stopped]
```

## Relationships

```
LLMProviderRegistry
  └── ClaudeCodeProvider (implements LLMProvider)
        ├── LLMModel (from models.json "claudecode" section)
        ├── ClaudeCodeProcessManager (persistent process lifecycle)
        │     ├── Process (Foundation, one persistent instance)
        │     ├── Pipe × 3 (stdin, stdout, stderr)
        │     └── CLIStreamParser (JSONL line parser)
        ├── CLIStreamEvent (parsed from subprocess stdout)
        └── CLIToolInfo[] (available tools, user-configurable)
```
