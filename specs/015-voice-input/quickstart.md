# Quickstart: Voice Input (015)

## Prerequisites

- macOS 13.0+ (Ventura)
- Microphone (built-in or external)
- Siri enabled in System Settings (required for on-device speech recognition)

## New Frameworks

Add to `Package.swift` linker settings:
```swift
.linkedFramework("Speech")
.linkedFramework("AVFoundation")
```

## Info.plist Keys

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Extremis uses your microphone to transcribe voice input into text prompts.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Extremis uses on-device speech recognition to convert your voice to text.</string>
```

## New Files to Create

| File | Purpose |
|---|---|
| `Core/Models/VoiceInputModels.swift` | VoiceInputState enum, TranscriptionUpdate, VoiceInputConfiguration |
| `Core/Services/VoiceInputManager.swift` | @MainActor singleton coordinator |
| `Core/Services/SpeechRecognitionService.swift` | AVAudioEngine + SFSpeechRecognizer |
| `UI/PromptWindow/VoiceInputIndicator.swift` | Recording state visual component |
| `Tests/Core/VoiceInputModelsTests.swift` | State machine and config tests |

## Existing Files to Modify

| File | Change |
|---|---|
| `UI/PromptWindow/ChatInputView.swift` | Add mic button in left HStack |
| `UI/PromptWindow/PromptView.swift` | Add mic button in action area |
| `Core/Services/PermissionManager.swift` | Add microphone + speech recognition status |
| `Core/Services/HotkeyManager.swift` | Add `case voiceInput = 5` to HotkeyIdentifier |
| `App/AppDelegate.swift` | Register Option+D hotkey for voice input toggle |
| `Package.swift` | Add Speech, AVFoundation frameworks |

## Core API Surface

```swift
// Start/stop voice input
VoiceInputManager.shared.toggleRecording()
VoiceInputManager.shared.startRecording()
VoiceInputManager.shared.stopRecording()

// Observe state in SwiftUI
@ObservedObject var voiceInput = VoiceInputManager.shared
// voiceInput.state — VoiceInputState (.idle, .recording, .error)
// voiceInput.partialTranscription — String (live text while recording)

// Check permissions
VoiceInputManager.shared.checkPermissions() -> VoicePermissionStatus
VoiceInputManager.shared.requestPermissions() async -> Bool
```

## Build & Test

```bash
cd Extremis && swift build
cd Extremis && ./scripts/run-tests.sh
```
