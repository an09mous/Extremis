# Extremis

A context-aware LLM writing assistant for macOS. Press a global hotkey anywhere to get AI-powered text generation with full context from your active application.

## Features

- **🔥 Global Hotkeys**
  - `⌘+Shift+Space` - Open prompt window for instructions/summarization
  - `⌥+Tab` - Magic Mode: auto-summarize selected text OR autocomplete at cursor
- **🧠 Context-Aware** - Captures surrounding text via keyboard simulation (works in all apps including VS Code)
- **📋 Smart Summarization** - Quickly summarize selected text or surrounding context with one click
- **🤖 Multi-Provider LLM Support**
  - OpenAI (GPT-4o)
  - Anthropic (Claude 3.5 Sonnet)
  - Google Gemini (Gemini 1.5 Flash)
  - Ollama (Local models - Llama, Mistral, etc.)
- **📝 Smart Text Insertion** - Generated text automatically inserted at cursor
- **🔒 Privacy-First** - No screenshots, uses keyboard simulation for text capture
- **🎨 Menu Bar App** - Runs quietly in your menu bar, shows active provider/model

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

1. Click the **✨ sparkles icon** in your menu bar
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

### Prompt Mode (`⌘+Shift+Space`)

1. Press hotkey anywhere
2. **With text selected**: Click **Summarize** or type an instruction to transform
3. **Without selection**: Type your instruction or press Enter for autocomplete
4. Press `⌘+Enter` to insert or `⌘+C` to copy

| Context | Available Actions |
|---------|------------------|
| Text selected | Summarize, Transform (with instruction), Copy |
| Cursor with surrounding text | Summarize context, Autocomplete, Transform |
| Empty field | Autocomplete, Generate new content |

### Magic Mode (`⌥+Tab`)

Smart context-aware mode that automatically chooses the best action:

1. **Text selected** → Auto-summarize the selection
2. **No selection** → Autocomplete at cursor position

A floating indicator appears while generating, and text is automatically inserted when ready.

### Summarization

Extremis can quickly summarize text in multiple ways:

- **Click Summarize button** in Prompt Mode
- **Press `⌥+Tab` with text selected** for instant summarization
- Works with selected text OR surrounding context (preceding + succeeding text)

The LLM receives full context including:
- Application name and window title
- URL (for browser apps)
- App-specific metadata (Slack channel, Gmail subject, etc.)

## Context Extraction

Extremis uses a **marker-based keyboard simulation** approach to capture text around the cursor. This works universally across all applications including VS Code and other Electron-based editors.

### How It Works

1. **Type a space marker** at cursor position
2. **Select text** using `Cmd+Shift+Up/Down`
3. **Copy** the selection
4. **Delete the marker** using backspace/delete
5. **Strip the marker** from captured text

This approach:
- ✅ Works in **all applications** (VS Code, browsers, native apps)
- ✅ **Preserves cursor position** exactly
- ✅ **Restores clipboard** after capture
- ✅ No dependency on Accessibility APIs for text capture

### Application-Specific Metadata

While text capture is universal, metadata varies by app:

| Application | Additional Context |
|-------------|-------------------|
| **Browsers** | Page content via AX APIs (headings, paragraphs, links) |
| **Slack** | Channel name, recent messages, participants |
| **Others** | Focused element info, window title |

## Architecture

```
Extremis/
├── App/                    # App entry point and lifecycle
├── Core/
│   ├── Models/            # Data models (Context, Preferences)
│   ├── Protocols/         # Protocol definitions
│   └── Services/          # HotkeyManager, ContextOrchestrator
├── Extractors/            # Context extractors
│   ├── GenericExtractor   # Fallback for any app
│   ├── BrowserExtractor   # All browsers via AX APIs
│   └── SlackExtractor     # Slack desktop + web
├── LLMProviders/          # OpenAI, Anthropic, Gemini
├── UI/                    # SwiftUI views
│   ├── PromptWindow       # Main floating panel
│   └── Preferences/       # Settings tabs
└── Utilities/             # Keychain, Clipboard helpers
```

## Tech Stack

- **Language**: Swift 5.9+ with Swift Concurrency
- **UI**: SwiftUI + AppKit (NSPanel)
- **Frameworks**:
  - Carbon (global hotkey registration)
  - ApplicationServices (Accessibility APIs)
  - Security (Keychain for API key storage)

## Roadmap

- [ ] **Replace mode** - Option to replace selected text instead of just inserting
- [x] **Full context capture** - Capture text after cursor (succeeding text) in addition to preceding text
- [x] **Universal app support** - Works in VS Code and all Electron apps via marker-based capture
- [x] **Summarization** - Quick summarize selected text or surrounding context
- [ ] **Chat + Memory** - Conversational interface with persistent memory across sessions
- [ ] **MCP support** - Integration with Model Context Protocol for external tools and data sources

See [open issues](https://github.com/an09mous/Extremis/issues) for more details and to contribute ideas.

## License

MIT License

## Contributing

Contributions welcome! Please open an issue or submit a PR.
