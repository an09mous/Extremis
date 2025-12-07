# Extremis

A context-aware LLM writing assistant for macOS. Press a global hotkey anywhere to get AI-powered text generation with full context from your active application.

## Features

- **🔥 Global Hotkeys**
  - `⌘+Shift+Space` - Open prompt window for instructions
  - `⌥+Tab` - Instant autocomplete at cursor position
- **🧠 Context-Aware** - Captures surrounding text and page content via macOS Accessibility APIs
- **🤖 Multi-Provider LLM Support**
  - OpenAI (GPT-4o)
  - Anthropic (Claude 3.5 Sonnet)
  - Google Gemini (Gemini 1.5 Flash)
  - Ollama (Local models - Llama, Mistral, etc.)
- **📝 Smart Text Insertion** - Generated text automatically inserted at cursor
- **🔒 Privacy-First** - Uses AX APIs only, no screenshots
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
2. Type your instruction (e.g., "make this more professional")
3. Press `Enter` to generate
4. Press `⌘+Enter` to insert or `⌘+C` to copy

### Autocomplete Mode (`⌥+Tab`)

1. Type some text in any application
2. Press `⌥+Tab` to auto-complete based on context
3. A floating "Generating..." indicator appears at the top of your screen
4. Text is automatically inserted when ready

## Context Extraction

Extremis captures context differently based on the application:

### Browsers (Chrome, Safari, Arc, etc.)
- **Surrounding text**: Captured via clipboard (text before cursor)
- **Page content**: Extracted via AX APIs (headings, paragraphs, links, buttons)
- **Window title**: Usually contains page title

### Slack (Desktop App)
- Channel name and type
- Recent messages
- Participants
- Selected text

### Other Applications
- Selected text via Accessibility APIs
- Focused element info
- Window title

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

## License

MIT License

## Contributing

Contributions welcome! Please open an issue or submit a PR.
