# Implementation Plan: Connectors (MCP Support)

**Branch**: `010-mcp-support` | **Date**: 2026-01-18 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/010-mcp-support/spec.md`

## Summary

Implement Connectors support in Extremis to enable users to integrate with external tools and services. The system supports two types:

1. **Built-in Connectors** - Pre-configured integrations (GitHub, Web Search, Jira) that users enable with minimal setup
2. **Custom MCP Servers** - User-configured MCP servers for advanced use cases

Both appear in a unified "Connectors" preferences tab. The LLM can invoke tools from connected connectors, with support for parallel and sequential tool execution.

## Implementation Phases

**Phase 1 (Current)**: Custom MCP Servers
- Foundation models and configuration
- Transport layer (STDIO and HTTP/SSE)
- Connector registry and lifecycle management
- Tool execution and LLM integration
- Preferences UI for custom MCP servers

**Phase 2 (Requires Approval)**: Built-in Connectors
- Built-in connector implementations (GitHub, Brave Search, Jira)
- Dependency detection (npx availability)
- Enhanced preferences UI for built-in connectors
- *Will start only after Phase 1 is complete and approved*

## Technical Context

**Language/Version**: Swift 5.9+
**Primary Dependencies**: Foundation, SwiftUI, AppKit, MCP Swift SDK (modelcontextprotocol/swift-sdk 0.10.0+)
**Storage**: JSON file (`~/Library/Application Support/Extremis/connectors.json`) + existing Keychain for secrets + MCP packages (`~/Library/Application Support/Extremis/mcp/`) for built-in connectors (Phase 2)
**Testing**: Standalone Swift test files (existing pattern via `./scripts/run-tests.sh`)
**Target Platform**: macOS 13.0+ (Ventura)
**Project Type**: Single macOS application (menu bar app)
**Performance Goals**: Tool execution timeout 30s, connection within 5s, tool discovery within 3s
**Constraints**: Non-blocking UI, background connections, graceful degradation when no connectors configured
**Scale/Scope**: Support multiple concurrent connector connections, parallel tool execution

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Modularity & Separation of Concerns | ✅ PASS | Connectors module isolated in `Connectors/` directory, protocol-based design with `Connector` protocol, registry pattern matching existing `LLMProviderRegistry` |
| II. Code Quality & Best Practices | ✅ PASS | Follows existing Swift patterns, uses Swift Concurrency (async/await), protocol conformance for extensibility |
| III. Extensibility & Testability | ✅ PASS | Protocol-based design enables mocking, transport layer abstracted, built-in connectors easily added |
| IV. User Experience Excellence | ✅ PASS | Non-blocking connections, inline tool indicators, clear error messages, unified Connectors UI in Preferences |
| V. Documentation Synchronization | ✅ PASS | README update planned, CLAUDE.md update required for new patterns |
| VI. Testing Discipline | ✅ PASS | Unit tests for config parsing, connection state, tool schema conversion |
| VII. Regression Prevention | ✅ PASS | Chat works normally without connectors, existing provider patterns preserved |

**Quality Gates**:
- [ ] Build succeeds without warnings
- [ ] All existing tests pass
- [ ] Connectors module has unit tests for complex logic
- [ ] Manual QA of connector flows complete

## Project Structure

### Documentation (this feature)

```text
specs/010-mcp-support/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Task breakdown (via /speckit.tasks)
```

### Application Support (runtime data)

```text
~/Library/Application Support/Extremis/
├── connectors.json      # Connector configurations (no secrets)
├── sessions/            # Existing session persistence
└── mcp/                 # Phase 2: Built-in connector MCP packages
    ├── github/
    ├── brave-search/
    └── jira/
```

### Source Code (repository root)

```text
Extremis/
├── App/
│   └── AppDelegate.swift              # Add Connectors initialization on startup
├── Core/
│   ├── Models/
│   │   └── ChatMessage.swift          # Extend with toolCalls/toolResults fields
│   ├── Protocols/
│   │   ├── LLMProvider.swift          # Extend with tool-aware generation methods
│   │   └── Connector.swift            # NEW: Connector protocol
│   └── Services/
│       └── SessionManager.swift       # No changes needed
├── Connectors/                        # NEW: Connectors module
│   ├── Models/
│   │   ├── ConnectorConfig.swift      # Persistent config model
│   │   ├── BuiltInConnectorType.swift # Enum of built-in connectors
│   │   ├── ConnectorTool.swift        # Discovered tool model
│   │   ├── ToolCall.swift             # Tool invocation request
│   │   └── ToolResult.swift           # Tool execution result
│   ├── Services/
│   │   ├── ConnectorRegistry.swift    # Connector management (like LLMProviderRegistry)
│   │   ├── ConnectorConfigStorage.swift # JSON config persistence
│   │   └── ToolExecutor.swift         # Tool execution orchestration
│   ├── Transport/
│   │   ├── MCPTransport.swift         # Transport protocol
│   │   ├── StdioTransport.swift       # Local server via subprocess
│   │   └── HTTPTransport.swift        # Remote server via HTTP/SSE
│   ├── BuiltIn/                       # NEW: Built-in connector implementations
│   │   ├── GitHubConnector.swift      # GitHub integration
│   │   ├── WebSearchConnector.swift   # Web search integration
│   │   └── JiraConnector.swift        # Jira integration
│   └── Conversion/
│       └── ToolSchemaConverter.swift  # MCP schema → OpenAI/Anthropic format
├── LLMProviders/
│   ├── OpenAIProvider.swift           # Add tool calling support
│   ├── AnthropicProvider.swift        # Add tool calling support
│   └── PromptBuilder.swift            # Add tool-aware message building
├── UI/
│   ├── Preferences/
│   │   └── ConnectorsTab.swift        # NEW: Connectors configuration UI
│   └── PromptWindow/
│       ├── ChatMessageView.swift      # Add tool indicator display
│       └── ToolIndicatorView.swift    # NEW: "Using tool..." indicator
├── Resources/
│   └── PromptTemplates/
│       └── tool_context.hbs           # NEW: Tool-aware system prompt additions
└── Tests/
    └── Connectors/
        ├── ConnectorConfigStorageTests.swift
        ├── ToolSchemaConverterTests.swift
        └── ToolExecutorTests.swift
```

**Structure Decision**: Single macOS app with new `Connectors/` module following existing patterns. Uses same singleton/registry pattern as `LLMProviderRegistry` for consistency.

## Key Design Decisions

### 1. Connector Architecture

**Decision**: Protocol-based design with two concrete implementations

```swift
/// Base protocol for all connectors
protocol Connector: AnyObject, Identifiable {
    var id: String { get }
    var name: String { get }
    var state: ConnectorState { get }
    var tools: [ConnectorTool] { get }

    func connect() async throws
    func disconnect() async
    func executeTool(_ call: ToolCall) async throws -> ToolResult
}

/// Built-in connector with pre-configured settings
final class BuiltInConnector: Connector {
    let type: BuiltInConnectorType  // .github, .webSearch, .jira
    // Internally wraps an MCP server or direct API
}

/// Custom user-configured MCP server
final class CustomMCPConnector: Connector {
    let config: CustomMCPServerConfig
    // Uses MCP transport layer
}
```

**Rationale**:
- Unified interface for both connector types
- Built-in connectors can wrap MCP servers or use direct APIs
- Easy to add new built-in connectors

### 2. Configuration Storage

**Decision**: Single JSON file at `~/Library/Application Support/Extremis/connectors.json`

**Rationale**:
- Single source of truth for all connector config
- Separates connector config from general preferences (UserDefaults)
- Allows easy manual editing/backup
- **Secrets NEVER in config file** - all API keys, tokens stored in macOS Keychain

**Config Format** (no secrets):
```json
{
  "version": 1,
  "builtIn": {
    "github": {
      "enabled": true
    },
    "braveSearch": {
      "enabled": false
    },
    "jira": {
      "enabled": false,
      "settings": {
        "baseUrl": "https://mycompany.atlassian.net"
      }
    }
  },
  "custom": [
    {
      "id": "uuid-string",
      "name": "My Tool Server",
      "type": "stdio",
      "command": "/usr/local/bin/my-mcp-server",
      "args": ["--port", "3000"],
      "env": {
        "DEBUG_MODE": "true"
      },
      "enabled": true
    }
  ]
}
```

**Note**: `env` contains only non-sensitive values. All secrets (API keys, tokens) are stored in Keychain under `connector.custom.{uuid}` and merged at runtime. Users enter secrets via dedicated "API Keys" section in the UI.

### 3. Secrets & Authentication

**Decision**: All secrets stored in macOS Keychain, never in config file. Authentication layer is extensible for future OAuth support.

**Why not follow Claude Desktop pattern?**
Claude Desktop stores API keys in plain text in `claude_desktop_config.json`. This is insecure. Extremis uses Keychain for:
- Encrypted storage
- macOS security best practices
- No accidental exposure when sharing configs

**Current Implementation (API Keys)**:
1. **Built-in connectors**: Each type defines auth requirements via `ConnectorAuthMethod.apiKey`
2. **Custom MCP servers**: User marks env vars as "secret" in UI; values stored in Keychain
3. **At runtime**: Secrets retrieved from Keychain and injected as env vars when spawning process

**Keychain Keys**:
- Built-in: `connector.builtin.github`, `connector.builtin.webSearch`, etc.
- Custom: `connector.custom.{uuid}`

**Extensibility for OAuth**:
The authentication layer uses a protocol-based design (`ConnectorAuthHandler`) that can be extended:

```swift
protocol ConnectorAuthHandler {
    func isAuthenticated(for connector: BuiltInConnectorType) async -> Bool
    func getCredentials(for connector: BuiltInConnectorType) async throws -> ConnectorCredentials
    func saveCredentials(_ credentials: ConnectorCredentials, for connector: BuiltInConnectorType) async throws
    func clearCredentials(for connector: BuiltInConnectorType) async throws
}

enum ConnectorCredentials {
    case apiKey([String: String])
    // case oauth(accessToken: String, refreshToken: String?, expiresAt: Date?)  // Future
}
```

To add OAuth for a connector (e.g., GitHub):
1. Add `.oauth(OAuthConfig)` case to `ConnectorAuthMethod`
2. Implement `OAuthAuthHandler` conforming to `ConnectorAuthHandler`
3. Update UI to show "Login with GitHub" button
4. Connection logic unchanged - calls `getCredentials()` and gets token

See [data-model.md](./data-model.md#authentication-configuration) for detailed models.

### 4. Built-in Connectors (Phase 2)

**Decision**: All built-in connectors communicate via MCP protocol (not direct APIs). This ensures consistent architecture and easier maintenance.

**Initial Built-in Connectors**:
| Connector | Implementation | Auth Method | OAuth Ready | Dependency |
|-----------|----------------|-------------|-------------|------------|
| GitHub | MCP server via npx | API Key (PAT) | Yes | npx required |
| Brave Search | MCP server via npx | API Key | No | npx required |
| Jira | MCP server via npx | API Key + Email | Yes | npx required |

**npx Dependency Handling**:

Based on research of how Claude Desktop, Cursor IDE, and other AI assistants handle this:

**Common Issue**: The `spawn npx ENOENT` error occurs when apps can't find npx because macOS applications inherit system `$PATH` but miss paths added via shell config (.bashrc, .zshrc).

**Extremis Approach**:
1. **Detection**: Check multiple common paths for npx/node at startup:
   - `/usr/local/bin/npx`
   - `/opt/homebrew/bin/npx`
   - `~/.nvm/versions/node/*/bin/npx`
   - System PATH resolution

2. **When npx not found**:
   - Show built-in connector as "Unavailable" with 🔴 indicator
   - Display clear message: "Requires Node.js. [Install from nodejs.org](https://nodejs.org)"
   - Provide "Check Again" button to retry detection
   - Log detailed error for debugging

3. **When npx found but in non-standard location**:
   - Cache the discovered path
   - Use full path in Process spawn (don't rely on PATH)

4. **Platform-specific considerations** (future):
   - macOS: Check Homebrew, nvm, fnm paths
   - Future Windows support: Use `cmd /c npx` wrapper

**Reference**: Claude Desktop shows similar `ENOENT` errors when npx path is not accessible, requiring users to symlink or use full paths.

**MCP Package Storage** (Phase 2):
Built-in connector MCP servers are downloaded and cached locally:
- Location: `~/Library/Application Support/Extremis/mcp/`
- Structure:
  ```
  mcp/
  ├── github/           # GitHub MCP server package
  ├── brave-search/     # Brave Search MCP server package
  └── jira/             # Jira MCP server package
  ```
- Downloaded on first enable (not on app startup)
- Version-pinned for stability
- Can be updated via "Check for Updates" in Preferences

**Rationale**:
- Consistent MCP-based architecture
- All tools communicate via same protocol
- Easier to add new built-in connectors
- Auth layer ready for OAuth when needed
- Code extensible for direct API fallback if needed later

### 4. Transport Layer

**Decision**: Support both STDIO (local) and HTTP/SSE (remote) transports

**STDIO** (for local development):
- Use `Foundation.Process` for subprocess management
- JSON-RPC 2.0 over stdin/stdout
- Direct process control

**HTTP/SSE** (for remote servers):
- Standard HTTP POST for requests
- Server-Sent Events for streaming responses
- Future-proof for cloud-hosted MCP servers

### 5. Tool Execution Model

**Decision**: Support parallel and sequential tool execution within a single LLM response

**Parallel Execution**:
- Default for independent tools (no shared state)
- Use `TaskGroup` for concurrent execution
- Aggregate all results before returning to LLM

**Sequential Execution**:
- When tool outputs feed into subsequent tools
- Detected via dependency analysis or explicit chaining
- Execute in order, passing results forward

**Tool Name Disambiguation**:
When multiple connectors have tools with the same name, use underscore prefix format:
- `github_search_issues` (not `search_issues`)
- `jira_search_issues` (not `search_issues`)
- `filesystem_read_file` (not `read_file`)

This ensures unique tool names across all connectors for LLM tool calling.

### 5b. Connection Lifecycle

**Auto-connect on Startup**:
- All enabled connectors connect automatically when Extremis starts
- Connection happens in background (non-blocking)
- Since Extremis is a menu bar app that starts on boot, startup performance is less critical
- Users see status indicators during connection

**Auto-reconnect on Disconnect**:
- If connector disconnects mid-conversation, auto-reconnect silently
- Show reconnection status in chat: "Reconnecting to [connector]..."
- Maximum 3 retry attempts with exponential backoff
- After 3 failures, continue conversation without the tool and notify user
- User can manually reconnect via Preferences

### 6. LLM Provider Integration

**Decision**: Extend existing `LLMProvider` protocol with optional tool support

```swift
protocol LLMProvider: AnyObject {
    // Existing methods...

    // NEW: Optional tool support
    func generateChatWithTools(
        messages: [ChatMessage],
        tools: [ConnectorTool]?
    ) async throws -> GenerationWithToolCalls
}
```

**Tool Call Flow**:
1. Build messages with tool definitions
2. Send to LLM provider
3. Parse tool call requests from response
4. Execute tools via appropriate connector
5. Inject results back into conversation
6. Continue until LLM returns final response

### 7. UI Design

**Decision**: Unified "Connectors" tab in Preferences with two sections

```
┌─────────────────────────────────────────────────────┐
│ Connectors                                          │
├─────────────────────────────────────────────────────┤
│ Built-in Connectors                                 │
│ ┌─────────────────────────────────────────────────┐ │
│ │ 🔗 GitHub           [Connected ✓] [Disconnect]  │ │
│ │ 🔍 Web Search       [Connect]                   │ │
│ │ 📋 Jira             [Connect]                   │ │
│ └─────────────────────────────────────────────────┘ │
│                                                     │
│ Custom MCP Servers                    [+ Add New]   │
│ ┌─────────────────────────────────────────────────┐ │
│ │ My Tool Server      🟢 Connected   [Edit] [🗑]  │ │
│ │ Remote API          🔴 Error       [Edit] [🗑]  │ │
│ └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

**Chat UI**:
- Show "Using tool: [name]..." during execution
- Display tool results collapsed (expandable for details)
- Error states shown inline with retry option

## Complexity Tracking

> No complexity violations identified. Design follows existing patterns.

## Task Decomposition

Task decomposition will be generated via `/speckit.tasks` command after this plan is approved.

### Phase 1: Custom MCP Servers (Current)

1. **Foundation** (P0)
   - Connector protocol and base models
   - ConnectorConfig and persistence (JSON file)
   - ConnectorSecrets and Keychain integration
   - Basic unit tests

2. **Transport Layer** (P0)
   - MCPTransport protocol
   - StdioTransport implementation (local servers)
   - HTTPTransport implementation (remote servers)

3. **Connector Management** (P1)
   - ConnectorRegistry service (CustomMCPConnector only)
   - Connection lifecycle management
   - Auto-connect on startup
   - Auto-reconnect with 3 retry limit
   - Tool discovery flow

4. **Tool Execution** (P1)
   - ToolCall/ToolResult models
   - ToolExecutor with parallel/sequential support
   - Tool schema conversion (MCP → OpenAI/Anthropic)
   - Tool name disambiguation (underscore prefix)

5. **LLM Integration** (P1)
   - Extend LLMProvider protocol
   - Update OpenAI/Anthropic providers for tool calling
   - Tool-aware prompt building

6. **UI - Custom MCP Servers** (P2)
   - ConnectorsTab in Preferences (custom section only)
   - Add/Edit/Delete custom MCP server flows
   - Separate sections for "Environment Variables" and "API Keys"
   - Connection status indicators
   - Tool indicator in ChatMessageView

7. **Polish & Testing** (P2)
   - Unit tests for all components
   - Error handling refinement
   - Documentation updates (README, CLAUDE.md)

### Phase 2: Built-in Connectors (Requires Approval)

*Will start only after Phase 1 is complete and approved.*

8. **Built-in Connectors**
   - BuiltInConnectorType enum (GitHub, Brave Search, Jira)
   - npx dependency detection
   - Built-in connector implementations (all via MCP)
   - Unavailability UI when npx not installed

9. **UI - Built-in Connectors**
   - ConnectorsTab built-in section
   - One-click enable with auth modal
   - Connection status and error handling
