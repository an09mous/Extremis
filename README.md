# Extremis

A context-aware AI assistant for macOS that lives in your menu bar. Press a global hotkey anywhere to chat, transform text, execute tools, and get things done — all with full awareness of your current app, window, and selection.

[![Demo](https://img.youtube.com/vi/mCSchPCEza4/maxresdefault.jpg)](https://youtu.be/mCSchPCEza4)

> **[Watch the demo →](https://youtu.be/mCSchPCEza4)** | **[All demos →](https://www.youtube.com/watch?v=zUP5TH_F-dM&list=PLltnaMY5emM9y1-78i_tKbv-Lvu0fLbUf)**

## Features

- **Global Hotkeys** — `Option+Space` to summon from any app, `Option+Tab` to instantly summarize selected text
- **Context-Aware** — Automatically captures app name, window title, URLs, and selected text
- **Multi-turn Chat** — Full conversations with follow-ups, session persistence, and automatic summarization
- **Quick Commands** — Pinned commands bar, command palette (`/`), and custom prompt templates
- **Tool Execution (MCP)** — Built-in shell, GitHub, and web fetch connectors plus any MCP-compatible server
- **Human-in-Loop Approval** — Review and approve tool calls with session memory
- **Multi-Provider** — OpenAI, Anthropic, Google Gemini, and Ollama (local models)
- **Smart Text Insertion** — Results insert directly at your cursor with `Cmd+Enter`

## Requirements

- macOS 13.0 (Ventura) or later
- API key for at least one LLM provider, or Ollama for local models

## Installation

### Build from Source

```bash
git clone https://github.com/an09mous/Extremis.git
cd Extremis/Extremis
./scripts/build.sh
open build/Extremis.dmg
```

Drag Extremis to Applications from the DMG.

### Download Pre-built

1. Download **Extremis.dmg** from [GitHub Releases](https://github.com/an09mous/Extremis/releases)
2. Open the DMG and drag Extremis to Applications
3. Bypass Gatekeeper (app isn't notarized):
   ```bash
   xattr -cr /Applications/Extremis.app
   ```
4. Launch Extremis from Applications

## Setup

### 1. Grant Accessibility Permission

On first launch, go to **System Settings → Privacy & Security → Accessibility** and enable Extremis. Restart Extremis after granting permission.

### 2. Configure an LLM Provider

Click the menu bar icon → **Preferences** → **Providers** tab.

| Provider | API Key |
|----------|---------|
| OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| Anthropic | [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) |
| Google Gemini | [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey) |
| Ollama | No key needed — see below |

### Setting Up Ollama (Local Models)

1. Install Ollama from [ollama.com](https://ollama.com)
2. Start ollama
3. Pull a model:
   ```bash
   ollama pull llama3.2
   ```
4. In Extremis, go to **Preferences → Providers → Ollama (Local)** — it auto-detects the server at `http://127.0.0.1:11434`
5. Select your model from the dropdown

Ollama models that support tool calling (e.g., `llama3.1`, `qwen2.5`) will automatically work with MCP connectors. Extremis checks each model's capabilities at runtime.

To use a remote Ollama server, update the base URL in Preferences.

## Usage

### `Option+Space` — Quick Mode / Chat Mode

| Context | Mode | What It Does |
|---------|------|--------------|
| Text selected | Quick Mode | Transform or act on selected text |
| No selection | Chat Mode | Open conversational chat |

- **Quick Mode**: Select text → `Option+Space` → Type instruction → `Cmd+Enter` to insert
- **Chat Mode**: `Option+Space` (no selection) → Type your question → Continue conversation

### `Option+Tab` — Magic Mode

Instantly summarize selected text with one keystroke. Does nothing without a selection.

### MCP Tools

**Built-in connectors** (Preferences → Connectors):
- **System Commands** — Execute macOS shell commands
- **GitHub** — Access repos, issues, PRs via Copilot MCP (requires GitHub PAT)
- **Web Fetch** — Fetch and process web content

**Custom MCP servers** — Add via **Preferences → Connectors → Add MCP Server**, or edit `~/Library/Application Support/Extremis/mcp-servers.json` directly.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Option+Space` | Open Extremis |
| `Option+Tab` | Magic Mode (instant summarize) |
| `Cmd+Enter` | Insert generated text |
| `Cmd+C` | Copy generated text |
| `Option+Return` | Allow all tool calls |
| `Option+Escape` | Deny all tool calls |
| `Escape` | Close window |

## Privacy

- Uses Accessibility APIs for context capture (no screenshots)
- Only reads text you explicitly select
- API keys stored in macOS Keychain
- Clipboard is restored after selection detection

## License

MIT License

## Contributing

Contributions welcome! Please open an issue or submit a PR.
