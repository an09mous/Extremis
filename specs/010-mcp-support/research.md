# Connectors Research

**Feature**: Connectors (MCP Support)
**Date**: 2026-01-18
**Status**: Complete

## Overview

Research findings for implementing Connectors support in Extremis. The system provides two types of connectors:

1. **Built-in Connectors** - Pre-configured integrations (GitHub, Web Search, Jira) with minimal setup
2. **Custom MCP Servers** - User-configured MCP servers for advanced use cases

Both use the Model Context Protocol (MCP) under the hood for tool discovery and execution.

---

## MCP Protocol Specification

### Protocol Version
- **Current Version**: 2025-11-25 (latest stable)
- **Transport**: JSON-RPC 2.0 over STDIO or HTTP/SSE
- **Capabilities**: Tool discovery, tool execution, resource access, prompt templates

### Core Message Flow

```
Client (Extremis)                    Server (MCP Server)
       |                                    |
       |--- initialize ------------------->|
       |<-- initialize result -------------|
       |--- initialized ------------------>|
       |                                    |
       |--- tools/list ------------------->|
       |<-- tools list result -------------|
       |                                    |
       |--- tools/call ------------------->|
       |<-- tool result -------------------|
```

### Key Protocol Messages

| Message | Direction | Purpose |
|---------|-----------|---------|
| `initialize` | Client → Server | Negotiate capabilities |
| `initialized` | Client → Server | Confirm initialization complete |
| `tools/list` | Client → Server | Discover available tools |
| `tools/call` | Client → Server | Execute a tool |
| `ping` | Bidirectional | Keep-alive / health check |

### Tool Schema Format (MCP Native)

```json
{
  "name": "get_weather",
  "description": "Get current weather for a location",
  "inputSchema": {
    "type": "object",
    "properties": {
      "location": {
        "type": "string",
        "description": "City name or coordinates"
      }
    },
    "required": ["location"]
  }
}
```

---

## MCP Swift SDK

### Package Information
- **Repository**: `modelcontextprotocol/swift-sdk`
- **Version**: 0.10.0+ (recommended)
- **Swift Version**: 5.9+
- **Platform**: macOS 13.0+

### SDK Architecture

The Swift SDK provides:
1. **Client Protocol**: For connecting to MCP servers
2. **Transport Abstractions**: STDIO and HTTP transports
3. **Message Types**: Strongly-typed Swift structs for all MCP messages
4. **Async/Await**: Full Swift Concurrency support

### Key Types

```swift
// From MCP Swift SDK
public struct Tool: Codable, Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: JSONSchema
}

public struct CallToolResult: Codable, Sendable {
    public let content: [Content]
    public let isError: Bool?
}

public enum Content: Codable, Sendable {
    case text(TextContent)
    case image(ImageContent)
    case resource(EmbeddedResourceContent)
}
```

### Transport Options

**STDIO Transport** (Local servers):
- Process spawned as subprocess
- Communication via stdin/stdout
- Best for local development tools
- Example: `npx @modelcontextprotocol/server-filesystem`

**HTTP/SSE Transport** (Remote servers):
- Standard HTTP POST for requests
- Server-Sent Events for streaming responses
- Best for cloud-hosted services
- Requires URL endpoint

---

## Configuration Patterns

### Claude Desktop Pattern (Industry Reference)

Claude Desktop uses a JSON configuration file at:
- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed/files"],
      "env": {}
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "token_here"
      }
    }
  }
}
```

### Extremis Connectors Pattern

Extremis uses a unified "Connectors" approach with two sections:

**Proposed Location**: `~/Library/Application Support/Extremis/connectors.json`

**Proposed Format**:
```json
{
  "version": 1,
  "builtIn": {
    "github": { "enabled": true },
    "webSearch": { "enabled": false },
    "jira": { "enabled": true, "settings": { "baseUrl": "https://company.atlassian.net" } }
  },
  "custom": [
    {
      "id": "uuid-string",
      "name": "Filesystem Tools",
      "type": "stdio",
      "command": "/usr/local/bin/mcp-server",
      "args": ["--path", "/Users/me/projects"],
      "env": {},
      "enabled": true
    }
  ]
}
```

**Advantages**:
- **User-friendly**: "Connectors" is more intuitive than "MCP Servers"
- **Unified experience**: Built-in and custom appear in same UI
- **Progressive disclosure**: Easy built-in connectors for most users, custom MCP for power users
- **Future-proof**: Can add non-MCP integrations later

**Sensitive Data**: API keys and tokens stored in Keychain, keyed by connector ID.

---

## Built-in Connectors Strategy

### Initial Built-in Connectors

| Connector | Implementation | Tools Provided | Auth Required |
|-----------|----------------|----------------|---------------|
| GitHub | MCP server (npx) | Repo search, issues, PRs, code search | Personal Access Token |
| Web Search | Direct API (Tavily/Brave) | Web search, news search | API Key |
| Jira | MCP server or API | Issues, projects, sprints | API Token + Base URL |

### Implementation Options

**Option A: Wrap MCP Servers**
- Built-in connectors internally spawn MCP servers
- Consistent implementation with custom connectors
- Leverages existing MCP server ecosystem
- Example: GitHub uses `npx @modelcontextprotocol/server-github`

**Option B: Direct API Integration**
- Built-in connectors call APIs directly
- More control over behavior
- Can optimize for specific use cases
- Example: Web Search calls Tavily API directly

**Recommended**: Hybrid approach - use MCP servers where available, direct APIs where beneficial.

---

## LLM Tool Calling Formats

### OpenAI Format

```json
{
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get current weather",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {"type": "string"}
          },
          "required": ["location"]
        }
      }
    }
  ]
}
```

**Tool Call Response**:
```json
{
  "tool_calls": [
    {
      "id": "call_abc123",
      "type": "function",
      "function": {
        "name": "get_weather",
        "arguments": "{\"location\": \"San Francisco\"}"
      }
    }
  ]
}
```

### Anthropic Format

```json
{
  "tools": [
    {
      "name": "get_weather",
      "description": "Get current weather",
      "input_schema": {
        "type": "object",
        "properties": {
          "location": {"type": "string"}
        },
        "required": ["location"]
      }
    }
  ]
}
```

**Tool Use Response**:
```json
{
  "content": [
    {
      "type": "tool_use",
      "id": "toolu_abc123",
      "name": "get_weather",
      "input": {"location": "San Francisco"}
    }
  ]
}
```

### Conversion Strategy

MCP tool schemas are similar to JSON Schema (used by both OpenAI and Anthropic):

| MCP Field | OpenAI Field | Anthropic Field |
|-----------|--------------|-----------------|
| `name` | `function.name` | `name` |
| `description` | `function.description` | `description` |
| `inputSchema` | `function.parameters` | `input_schema` |

Conversion is straightforward with minor structural differences.

---

## Tool Execution Patterns

### Parallel Execution

When tools are independent (no shared state or data dependencies):

```swift
// Using Swift TaskGroup
await withTaskGroup(of: ToolResult.self) { group in
    for call in toolCalls {
        group.addTask {
            await self.executeTool(call)
        }
    }

    for await result in group {
        results.append(result)
    }
}
```

**Benefits**:
- Faster overall execution
- Better UX for multiple independent tools
- Natural fit for Swift Concurrency

### Sequential Execution

When tools have dependencies:

```swift
// Execute in order
for call in toolCalls {
    let result = await executeTool(call)
    // Result may influence next call
    context.addResult(result)
}
```

**When to Use**:
- Tool outputs feed into subsequent tools
- Explicit ordering required by LLM
- Shared state modifications

### Hybrid Approach (Recommended)

Let the LLM indicate dependencies via tool call order or explicit chaining:
1. Analyze tool calls for dependencies
2. Group independent calls for parallel execution
3. Execute dependent groups sequentially

---

## Error Handling

### Connection Errors

| Error | Handling |
|-------|----------|
| Server not found | Show "Connector unavailable" status |
| Connection timeout (5s) | Retry with backoff, then mark disconnected |
| Process crash | Detect via SIGCHLD, attempt reconnect |
| Auth failure | Prompt user to re-authenticate |

### Tool Execution Errors

| Error | Handling |
|-------|----------|
| Timeout (30s) | Cancel execution, return error to LLM |
| Invalid arguments | Return validation error to LLM |
| Server error | Return error message to LLM |
| Malformed response | Log warning, return generic error |

### Graceful Degradation

- Chat continues normally without connector tools when unavailable
- Individual connector failures don't affect other connectors
- Tool failures don't crash the app
- Built-in connector backend failures show clear error messages

---

## Security Considerations

### Credential Storage (Keychain-Only)

**Key Decision**: Unlike Claude Desktop (which stores API keys in plain text in config), Extremis stores ALL secrets in macOS Keychain.

| Approach | Claude Desktop | Extremis |
|----------|----------------|----------|
| Storage | Plain text in JSON | macOS Keychain |
| Security | Insecure | Encrypted |
| Shareable config | No (contains secrets) | Yes (no secrets) |

**Why Keychain?**
- Encrypted at rest by macOS
- Protected by system security (Touch ID, password)
- Config file can be safely shared/backed up
- Follows macOS security best practices

### Secrets Flow

```
┌─────────────────────────────────────────────────────────────┐
│ User enters API key in Preferences UI                       │
│              ↓                                              │
│ Extremis stores in Keychain (encrypted)                     │
│ Key: "connector.builtin.github" or "connector.custom.{uuid}"│
│              ↓                                              │
│ Config file stores only: secretEnvVarNames: ["API_KEY"]     │
│ (the name, NOT the value)                                   │
│              ↓                                              │
│ At connection time:                                         │
│   1. Load non-sensitive env vars from config                │
│   2. Load secrets from Keychain                             │
│   3. Merge and inject into process environment              │
└─────────────────────────────────────────────────────────────┘
```

### Keychain Key Format

```swift
// Built-in connectors
"connector.builtin.github"
"connector.builtin.webSearch"
"connector.builtin.jira"

// Custom MCP servers
"connector.custom.{uuid}"
```

### What's Stored Where

| Data | Location | Example |
|------|----------|---------|
| Server command | Config file | `/usr/local/bin/mcp-server` |
| Server args | Config file | `["--verbose"]` |
| Non-secret env vars | Config file | `DEBUG_MODE=true` |
| Secret env var **names** | Config file | `secretEnvVarNames: ["API_KEY"]` |
| Secret env var **values** | Keychain | `API_KEY=sk-xxxxx` |
| API tokens | Keychain | `ghp_xxxxxxxxxxxx` |

### Process Isolation

- STDIO servers run as separate processes
- Use sandbox-friendly paths
- Validate server commands before execution
- Secrets injected via process environment (never written to disk)

### Network Security

- HTTPS required for remote connectors
- Validate SSL certificates
- Auth headers stored in Keychain, not config

---

## npx Dependency Research

### Common Issue

Claude Desktop and other MCP clients experience `spawn npx ENOENT` errors when the npx command cannot be found. This happens because macOS applications inherit the system `$PATH` but miss paths added via shell configuration files (.bashrc, .zshrc).

### How Other AI Assistants Handle This

**Claude Desktop**:
- Shows error in logs: `spawn npx ENOENT`
- Requires users to manually symlink npx to accessible paths
- No built-in detection or guidance
- Solutions include using full paths or global npm install

**Cursor IDE**:
- Requires Node.js v18+ or v20+ depending on server
- Checks `node -v` for version
- Uses `mcp.json` config with explicit command paths
- More explicit about Node.js requirements in setup docs

### Extremis Approach

Based on research, Extremis should:

1. **Proactive Detection**: Check common npx paths at startup:
   - `/usr/local/bin/npx` (standard)
   - `/opt/homebrew/bin/npx` (Homebrew on Apple Silicon)
   - `~/.nvm/versions/node/*/bin/npx` (nvm users)
   - System PATH resolution

2. **Clear User Guidance**: When npx not found:
   - Show built-in connector as "Unavailable"
   - Display: "Requires Node.js. Install from nodejs.org"
   - Provide "Check Again" button after installation

3. **Full Path Usage**: Once found, use full path to npx in Process spawn to avoid PATH issues

### References

- [Claude Desktop MCP Setup Notes](https://nishtahir.com/notes-on-setting-up-claude-desktop-mcp-servers/)
- [MCP Server Connection Issues with NVM/NPM](https://medium.com/@chanmeng666/solution-for-mcp-servers-connection-issues-with-nvm-npm-5529b905e54a)
- [Setup MCP Server using Cursor](https://medium.com/@sophia-brown-harrods/setup-mcp-server-using-cursor-c51634a4d4df)

---

## Performance Targets

| Metric | Target | Rationale |
|--------|--------|-----------|
| Connection time | < 5s | Fast startup experience |
| Tool discovery | < 3s | Quick availability |
| Tool execution | < 30s | Reasonable for most operations |
| UI blocking | 0ms | All operations async |

---

## UI/UX Considerations

### Connectors Tab Design

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

### Status Indicators

| State | Indicator | Color |
|-------|-----------|-------|
| Connected | 🟢 | Green |
| Connecting | 🟡 | Yellow |
| Disconnected | ⚪ | Gray |
| Error | 🔴 | Red |

### Tool Execution Feedback

- Inline "Using tool: [name]..." indicator during execution
- Collapsed tool results (expandable)
- Clear error messages with retry option

---

## References

1. [MCP Specification](https://spec.modelcontextprotocol.io/) - Official protocol documentation
2. [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) - Official Swift implementation
3. [Claude Desktop Config](https://modelcontextprotocol.io/quickstart/user) - Configuration reference
4. [OpenAI Function Calling](https://platform.openai.com/docs/guides/function-calling) - OpenAI tool format
5. [Anthropic Tool Use](https://docs.anthropic.com/en/docs/build-with-claude/tool-use) - Anthropic tool format
6. [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/) - UI design guidelines
