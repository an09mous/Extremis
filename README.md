# Extremis

A context-aware LLM writing assistant for macOS. Press a global hotkey anywhere to get AI-powered text generation with full context from your active application.

## Features

- **Global Hotkeys**
  - `Option+Space` - Quick Mode (with selection) or Chat Mode (without selection)
  - `Option+Tab` - Magic Mode: auto-summarize selected text (no-op without selection)
- **Context-Aware** - Captures app context (name, window title) and selected text
- **Quick Summarization** - Summarize selected text instantly with one keystroke
- **Multi-turn Chat** - Continue chatting with AI for refinements and follow-ups
- **Session Management** - Multiple chat sessions with automatic persistence across restarts
- **Context Window Management** - Long conversations are automatically summarized to fit context windows
- **Context Inspector** - View captured context (app, window, URL, metadata) before sending
- **Multi-Provider LLM Support**
  - OpenAI (GPT-4o, GPT-4o Mini, GPT-4 Turbo, GPT-4)
  - Anthropic (Claude Sonnet 4.5, Claude Haiku 4.5, Claude Opus 4.5)
  - Google Gemini (Gemini 2.5 Flash, Gemini 2.5 Pro, Gemini 2.0 Flash)
  - Ollama (Local models - Llama, Mistral, etc.)
- **MCP Server Support** - Connect external tools via Model Context Protocol
  - Tool execution with multi-turn loops
  - Automatic tool discovery from MCP servers
  - Partial result persistence on interruption
  - **Human-in-loop tool approval** with session memory
- **Real-time Streaming** - Responses appear character-by-character as they're generated
- **Smart Text Insertion** - Generated text automatically inserted at cursor
- **Privacy-First** - Uses Accessibility APIs for context, no screenshots
- **Menu Bar App** - Runs quietly in your menu bar, shows active provider/model

## Requirements

- macOS 13.0 (Ventura) or later
- Swift 5.9+
- Accessibility permission
- API key for at least one LLM provider (or Ollama running locally)

## Installation

```bash
# Clone and build
git clone https://github.com/yourusername/Extremis.git
cd Extremis/Extremis
swift build
swift run
```

## Setup

### 1. Grant Accessibility Permission

On first launch, go to **System Settings → Privacy & Security → Accessibility** and enable Extremis.

### 2. Configure LLM Provider

**Ollama is the default provider** - perfect for privacy-conscious users who want to run models locally.

#### Using Ollama (Default - Local Models)

1. Install Ollama from https://ollama.ai
2. Pull a model: `ollama pull llama3.2` or `ollama pull mistral`
3. Start Ollama (it runs on `http://127.0.0.1:11434` by default)
4. Extremis will automatically detect available models
5. Select your preferred model in Preferences → Providers → Ollama

#### Using Cloud Providers (Optional)

If you prefer cloud-based models:

1. Click the **sparkles icon** in your menu bar
2. Select **Preferences...**
3. Go to **Providers** tab
4. Enter your API key for any provider and click **Save**
5. Click **Use** to make it the active provider

| Provider | URL |
|----------|-----|
| OpenAI | https://platform.openai.com/api-keys |
| Anthropic | https://console.anthropic.com/settings/keys |
| Google Gemini | https://aistudio.google.com/app/apikey |

## Usage

### Quick Mode / Chat Mode (`Option+Space`)

The hotkey behavior depends on whether you have text selected:

**With text selected (Quick Mode):**
1. Press `Option+Space` with text selected
2. Click **Summarize** for instant summary, or type an instruction to transform the text
3. Press `Cmd+Enter` to insert or `Cmd+C` to copy

**Without selection (Chat Mode):**
1. Press `Option+Space` without any text selected
2. A conversational chat interface opens
3. Type your question or request and press Enter
4. Continue the conversation with follow-up questions

| Context | Mode | Available Actions |
|---------|------|------------------|
| Text selected | Quick Mode | Summarize, Transform (with instruction), Copy, Insert |
| No selection | Chat Mode | Conversational interface, multi-turn chat |

### Magic Mode (`Option+Tab`)

Smart summarization mode:

- **Text selected** → Auto-summarize the selection instantly
- **No selection** → No-op (does nothing silently)

A floating indicator appears while generating, and text is automatically inserted when ready.

### MCP Server Tools

Extremis can connect to MCP (Model Context Protocol) servers to extend the AI's capabilities with external tools:

1. Configure servers in `~/Library/Application Support/Extremis/mcp-servers.json`:
   ```json
   {
     "servers": {
       "filesystem": {
         "command": "npx",
         "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
       }
     }
   }
   ```

2. Restart Extremis - servers connect automatically
3. Tools appear in chat when the LLM decides to use them
4. Tool execution shows progress indicators in the UI

**Supported transports**: stdio (subprocess)

### Tool Approval

Extremis includes a human-in-loop approval system for MCP tool execution. You'll be prompted to approve or deny tools before they run.

**Keyboard shortcuts:**
- `Option+Return` - Allow all pending tools
- `Option+Escape` - Deny all pending tools
- `Return` - Allow focused tool
- `Escape` - Deny focused tool

**Session memory:**

Check "Remember for this session" when approving to automatically approve the same tool for the rest of the session without being asked again.

### Summarization

Extremis can quickly summarize text in multiple ways:

- **Click Summarize button** in Quick Mode
- **Press `Option+Tab` with text selected** for instant summarization

The LLM receives full context including:
- Application name and window title
- URL (for browser apps)
- App-specific metadata (Slack channel, Gmail subject, etc.)

## Context Capture

Extremis uses a hybrid approach to detect text selection:

1. **Accessibility API (Fast Path)** - Uses macOS AX APIs to read selected text directly
2. **Clipboard Fallback** - For apps where AX doesn't work (like Electron apps), temporarily copies selection via `Cmd+C`

### How It Works

1. Check for selected text via Accessibility API
2. If AX fails, save clipboard → send `Cmd+C` → check clipboard → restore clipboard
3. Includes heuristics to detect IDE "copy line" behavior (single line + trailing newline)

This approach:
- Works in **all applications** (VS Code, browsers, native apps)
- **Restores clipboard** after detection
- **Privacy-focused** - only reads text you explicitly select

### Application-Specific Metadata

Context metadata varies by app:

| Application | Additional Context |
|-------------|-------------------|
| **Browsers** | Window title, page URL |
| **Slack** | Channel name, channel type |
| **Others** | Focused element info, window title |

## Architecture

```
Extremis/
├── App/                    # App entry point and lifecycle
├── Core/
│   ├── Models/            # Data models (Context, ChatMessage, Preferences)
│   │   └── Persistence/   # Session storage models (PersistedSession, SessionIndex)
│   ├── Protocols/         # Protocol definitions (LLMProvider, SessionStorage, Connector)
│   └── Services/          # Business logic services
│       ├── SessionManager        # Session lifecycle and persistence
│       ├── SummarizationManager  # Long conversation summarization
│       ├── HotkeyManager         # Global hotkey registration
│       ├── ContextOrchestrator   # Context extraction coordination
│       └── JSONSessionStorage    # File-based session persistence
├── Connectors/            # MCP server integration
│   ├── Models/            # ConnectorTool, ToolCall, ToolResult, JSONSchema
│   ├── Services/          # ConnectorRegistry, ToolExecutor, ToolEnabledChatService
│   └── Transport/         # ProcessTransport (stdio subprocess communication)
├── Extractors/            # Context extractors
│   ├── GenericExtractor   # Fallback for any app
│   ├── BrowserExtractor   # All browsers via AX APIs
│   └── SlackExtractor     # Slack desktop + web
├── LLMProviders/          # OpenAI, Anthropic, Gemini, Ollama
│   ├── PromptBuilder      # Intent-based prompt formatting
│   └── PromptTemplateLoader # Handlebars template loading
├── UI/
│   ├── PromptWindow/      # Main floating panel and chat UI
│   ├── Preferences/       # Settings tabs
│   └── Components/        # Reusable UI components
└── Utilities/             # Helper classes
    ├── KeychainHelper     # Secure API key storage
    ├── SelectionDetector  # Text selection detection
    ├── ClipboardManager   # Clipboard operations
    └── UserDefaultsHelper # Preferences persistence
```

## Tech Stack

- **Language**: Swift 5.9+ with Swift Concurrency
- **UI**: SwiftUI + AppKit (NSPanel)
- **Frameworks**:
  - Carbon (global hotkey registration)
  - ApplicationServices (Accessibility APIs)
  - Security (Keychain for API key storage)
  - MCP Swift SDK (Model Context Protocol for tool integration)

## License

MIT License

## Contributing

Contributions welcome! Please open an issue or submit a PR.
