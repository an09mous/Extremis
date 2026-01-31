# Extremis

A context-aware AI assistant for macOS that lives in your menu bar. Press a global hotkey anywhere to chat, transform text, execute tools, and get things done — all with full awareness of your current app, window, and selection.

<img width="597" height="471" alt="image" src="https://github.com/user-attachments/assets/23b4feec-2c11-481c-969a-589c660b4b6f" />


## Features

**Instant Access**
- **Global Hotkeys**
   - Summon Extremis from any app with `Option+Space`
   - Summarize any selected text with `Option+tab`

- **Context-Aware** - Automatically captures app name, window title, URLs, and selected text
- **Smart Text Insertion** - Results insert directly at your cursor

**Powerful Conversations**
- **Multi-turn Chat** - Have full conversations with follow-ups and refinements
- **Session Persistence** - Conversations saved automatically, pick up where you left off
- **Context Window Management** - Long chats automatically summarized to stay within limits
- **Real-time Streaming** - See responses as they're generated

<img width="604" height="478" alt="image" src="https://github.com/user-attachments/assets/9f13e9b6-c3b2-4f82-ae91-0c3903ec81d2" />

**Tool Execution (MCP)**
- Connect external tools via Model Context Protocol
- Multi-turn agentic loops - AI can chain multiple tool calls
- Human-in-loop approval with session memory
- Works with any MCP-compatible server (filesystem, GitHub, databases, etc.)

<img width="495" height="459" alt="image" src="https://github.com/user-attachments/assets/2de96c4c-8a81-41d7-8b1a-c976feede92f" />


**Multi-Provider Support**
- OpenAI (GPT-4o, GPT-4o Mini, GPT-4 Turbo, GPT-4)
- Anthropic (Claude Sonnet 4.5, Claude Haiku 4.5, Claude Opus 4.5)
- Google Gemini (Gemini 3 Flash Preview, Gemini 2.5 Flash, Gemini 2.0 Flash)
- Ollama (Local models - Llama, Mistral, etc.)

<img width="496" height="466" alt="image" src="https://github.com/user-attachments/assets/e528395c-6a4d-47a9-af72-baae6462b2e1" />


## Requirements

- macOS 13.0 (Ventura) or later
- API key for at least one LLM provider (or Ollama for local models)

## Installation

### Build from Source (Recommended)

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
3. Run this command to bypass Gatekeeper (app isn't notarized):
   ```bash
   xattr -cr /Applications/Extremis.app
   ```
4. Launch Extremis from Applications

## Permissions

Extremis requires the following permissions to function:

### Accessibility (Required)

**Why:** Extremis uses macOS Accessibility APIs to:
- Read selected text from any application
- Detect the current app, window title, and focused element
- Insert generated text at your cursor position

**How to grant:** System Settings → Privacy & Security → Accessibility → Enable Extremis

Without this permission, Extremis cannot capture context or insert text.

### Keychain (Automatic)

**Why:** API keys are stored securely in the macOS Keychain rather than plain text files.

**How it works:** macOS will prompt you to allow Keychain access on first use. Click "Always Allow" to avoid repeated prompts.

## Setup

### 1. Grant Accessibility Permission

On first launch, go to **System Settings → Privacy & Security → Accessibility** and enable Extremis. You may need to restart Extremis after granting permission.

### 2. Configure an LLM Provider

Click the menu bar icon → **Preferences** → **Providers** tab.

| Provider | Get API Key |
|----------|-------------|
| OpenAI | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| Anthropic | [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) |
| Google Gemini | [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey) |
| Ollama | No key needed - [ollama.ai](https://ollama.ai) |

For Ollama: Install from ollama.ai, run `ollama pull llama3.2`, and Extremis auto-detects it.

## Usage

### `Option+Space` - Quick Mode / Chat Mode

| Context | Mode | What It Does |
|---------|------|--------------|
| Text selected | Quick Mode | Transform or summarize selected text |
| No selection | Chat Mode | Open conversational chat interface |

**Quick Mode**: Select text → `Option+Space` → Type instruction or click Summarize → `Cmd+Enter` to insert

**Chat Mode**: `Option+Space` (no selection) → Type your question → Continue conversation

### `Option+Tab` - Magic Mode

Instantly summarize selected text with one keystroke. Does nothing without a selection.

### MCP Tools (Optional)

Configure external tools in `~/Library/Application Support/Extremis/mcp-servers.json`:

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

**Tool Approval Shortcuts:**
- `Option+Return` - Allow all tools
- `Option+Escape` - Deny all tools
- Check "Remember for this session" to auto-approve repeated tool calls

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Option+Space` | Open Extremis (Quick/Chat mode) |
| `Option+Tab` | Magic Mode (instant summarize) |
| `Cmd+Enter` | Insert generated text |
| `Cmd+C` | Copy generated text |
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
