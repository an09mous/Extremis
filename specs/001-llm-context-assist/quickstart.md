# Quickstart: Extremis Development

**Branch**: `001-llm-context-assist` | **Date**: 2025-12-06

## Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Swift 5.9+
- API key from at least one LLM provider (OpenAI, Anthropic, or Google)

## Project Setup

### 1. Create Xcode Project

```bash
# Create project directory
mkdir -p Extremis
cd Extremis

# Open Xcode and create new project:
# - macOS > App
# - Product Name: Extremis
# - Interface: SwiftUI
# - Language: Swift
# - Uncheck "Include Tests" (we'll add manually for better structure)
```

### 2. Configure Info.plist

Add these keys to make it a menu bar app:

```xml
<!-- Hide from Dock -->
<key>LSUIElement</key>
<true/>

<!-- App description for permissions -->
<key>NSHumanReadableCopyright</key>
<string>© 2025 Extremis</string>
```

### 3. Configure Entitlements

Create `Extremis.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- Hardened Runtime exceptions for AppleScript -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    
    <!-- Keychain access for API keys -->
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.extremis.app</string>
    </array>
</dict>
</plist>
```

### 4. Add Privacy Descriptions to Info.plist

```xml
<!-- Required for Accessibility APIs -->
<key>NSAccessibilityUsageDescription</key>
<string>Extremis needs accessibility access to read text from applications and insert AI-generated responses.</string>

<!-- Required for AppleScript browser control -->
<key>NSAppleEventsUsageDescription</key>
<string>Extremis needs to communicate with browsers to extract context from web applications.</string>
```

## Project Structure

Create the following folder structure:

```
Extremis/
├── App/
├── Core/
│   ├── Models/
│   ├── Protocols/
│   └── Services/
├── Extractors/
├── LLMProviders/
├── UI/
│   ├── PromptWindow/
│   ├── Preferences/
│   └── Components/
├── Utilities/
└── Resources/

Tests/
├── ExtremisTests/
└── ExtremisUITests/
```

## Key Implementation Order

### Phase 1: Core Infrastructure
1. `HotkeyManager` - Global hotkey registration
2. `PermissionManager` - Accessibility permission handling
3. `PreferencesManager` - UserDefaults + Keychain

### Phase 2: Context Extraction
4. `GenericExtractor` - Fallback using AX selected text
5. `ExtractorRegistry` - Plugin registration
6. `BrowserBridge` - AppleScript execution

### Phase 3: LLM Integration
7. `LLMProvider` protocol implementation
8. `OpenAIProvider`, `AnthropicProvider`, `GeminiProvider`
9. `ProviderRegistry`

### Phase 4: UI
10. `PromptWindow` - Floating panel
11. `PromptView` - SwiftUI input/output
12. `PreferencesWindow` - Settings UI

### Phase 5: App-Specific Extractors
13. `SlackExtractor`
14. `GmailExtractor`
15. `GitHubExtractor`

## Running Tests

```bash
# Run all tests
xcodebuild test -scheme Extremis -destination 'platform=macOS'

# Run specific test class
xcodebuild test -scheme Extremis -destination 'platform=macOS' \
    -only-testing:ExtremisTests/ContextOrchestratorTests
```

## Development Tips

### Testing Accessibility APIs

```swift
// Check if accessibility is enabled
AXIsProcessTrusted() // Returns Bool

// Prompt user to enable (shows System Preferences)
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
AXIsProcessTrustedWithOptions(options as CFDictionary)
```

### Testing AppleScript Bridge

```swift
// Test Safari script execution
let script = NSAppleScript(source: """
    tell application "Safari"
        return URL of current tab of front window
    end tell
""")
var error: NSDictionary?
let result = script?.executeAndReturnError(&error)
```

### Debugging Hotkey Registration

```swift
// Log when hotkey is registered
print("Hotkey registered: Cmd+Shift+Space (keyCode: 49)")

// Log when hotkey is triggered
print("Hotkey triggered at \(Date())")
```

## Environment Variables (for testing)

```bash
# Skip permission checks during development
export EXTREMIS_SKIP_PERMISSIONS=1

# Use mock LLM responses
export EXTREMIS_MOCK_LLM=1

# Verbose logging
export EXTREMIS_DEBUG=1
```

