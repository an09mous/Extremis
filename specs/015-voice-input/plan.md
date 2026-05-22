# Implementation Plan: Voice Input

**Branch**: `015-voice-input` | **Date**: 2026-05-22 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/015-voice-input/spec.md`

## Summary

Add voice-to-text input to Extremis using Apple's `SFSpeechRecognizer` with on-device recognition. Users speak into their microphone via a mic button or Fn hold-to-talk shortcut; speech is transcribed in real-time into the existing text input field. All LLM responses remain text-only. The feature is additive — no existing input flows are modified.

## Technical Context

**Language/Version**: Swift 5.9+
**Primary Dependencies**: Speech framework (SFSpeechRecognizer), AVFoundation (AVAudioEngine), Carbon (existing), ApplicationServices (existing)
**Storage**: N/A — no audio or transcription persisted; text flows into existing ChatMessage pipeline
**Testing**: Standalone Swift test files via `scripts/run-tests.sh` (existing pattern)
**Target Platform**: macOS 13.0+ (Ventura)
**Project Type**: Single macOS app (existing Extremis structure)
**Performance Goals**: Transcription visible within 1 second of speech; recording start <100ms perceived latency
**Constraints**: On-device only (no network), English only, 60-second max recording, no audio stored
**Scale/Scope**: Single-user desktop app; one concurrent voice session

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Modularity & Separation of Concerns | PASS | Three new files with distinct responsibilities: `VoiceInputManager` (coordinator), `SpeechRecognitionService` (audio+recognition), `VoiceInputKeyHandler` (Fn key). No circular dependencies. |
| II. Code Quality & Best Practices | PASS | Follows Swift API Design Guidelines. Named constants for timeouts/durations. Protocol-based where extensible. |
| III. Extensibility & Testability | PASS | `SpeechRecognitionService` is injectable. Business logic separated from UI. Uses Swift Concurrency (`async/await`, `AsyncThrowingStream`). |
| IV. User Experience Excellence | PASS | <100ms perceived start latency. Visual recording indicator with animation. Clear error states with actionable guidance. Fn shortcut is discoverable. |
| V. Documentation Synchronization | PASS | README and CLAUDE.md to be updated with new feature documentation. |
| VI. Testing Discipline | PASS | Unit tests for state machine, configuration, key handler logic, transcription update model. Edge cases from spec covered. |
| VII. Regression Prevention | PASS | Feature is purely additive — new files, new UI element in existing HStack. No modification to existing hotkey, LLM, or chat flows. Existing tests must continue passing. |

## Project Structure

### Documentation (this feature)

```text
specs/015-voice-input/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
Extremis/
├── Core/
│   ├── Models/
│   │   └── VoiceInputModels.swift          # VoiceInputState, TranscriptionUpdate, VoiceInputConfiguration
│   └── Services/
│       ├── VoiceInputManager.swift         # @MainActor singleton coordinator
│       └── SpeechRecognitionService.swift   # AVAudioEngine + SFSpeechRecognizer wrapper
├── UI/
│   └── PromptWindow/
│       └── VoiceInputIndicator.swift       # Recording indicator overlay / inline component
├── Package.swift                           # Add Speech, AVFoundation frameworks
└── Info.plist                              # Add NSMicrophoneUsageDescription, NSSpeechRecognitionUsageDescription

Tests/
└── Core/
    └── VoiceInputModelsTests.swift          # State transitions, configuration defaults
```

**Structure Decision**: Follows existing Extremis directory conventions. New models go in `Core/Models/`, new services in `Core/Services/`, new UI in `UI/PromptWindow/`. No new top-level directories needed.

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    UI Layer                                   │
│                                                               │
│  ┌─────────────────┐    ┌──────────────────┐                 │
│  │ ChatInputView   │    │ PromptView       │                 │
│  │ (mic button)    │    │ (mic button)     │                 │
│  │ @Binding text   │    │ @Binding text    │                 │
│  └────────┬────────┘    └────────┬─────────┘                 │
│           │                      │                            │
│  ┌────────▼──────────────────────▼─────────┐                 │
│  │       VoiceInputIndicator               │                 │
│  │       (recording state visual)          │                 │
│  └────────┬────────────────────────────────┘                 │
│           │ reads state                                       │
├───────────┼──────────────────────────────────────────────────┤
│           │          Service Layer                            │
│           │                                                   │
│  ┌────────▼────────────────────────────────┐                 │
│  │       VoiceInputManager.shared          │                 │
│  │       (@MainActor singleton)            │                 │
│  │                                         │                 │
│  │  @Published state: VoiceInputState      │                 │
│  │  @Published partialText: String         │                 │
│  │  configuration: VoiceInputConfiguration │                 │
│  │                                         │                 │
│  │  toggleRecording()                      │                 │
│  │  startRecording()                       │                 │
│  │  stopRecording()                        │                 │
│  └──────┬──────────────────────────────────┘                 │
│         │                                                    │
│  ┌──────▼───────────────────────┐                            │
│  │ SpeechRecognitionService     │                            │
│  │                              │                            │
│  │ AVAudioEngine                │                            │
│  │ SFSpeechRecognizer           │                            │
│  │ → AsyncThrowingStream        │                            │
│  └──────────────────────────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

```
1. User taps mic button OR holds Fn key
2. VoiceInputManager.toggleRecording() / startRecording() called
3. VoiceInputManager checks permission (SFSpeechRecognizer.authorizationStatus)
   - Not determined → request authorization → on grant, continue
   - Denied → set state to .error with guidance message → return
   - Authorized → continue
4. VoiceInputManager sets state = .recording
5. SpeechRecognitionService.startTranscription() called
   - Creates SFSpeechAudioBufferRecognitionRequest (requiresOnDeviceRecognition = true)
   - Installs tap on AVAudioEngine.inputNode
   - Starts AVAudioEngine
   - Starts SFSpeechRecognitionTask
   - Returns AsyncThrowingStream<TranscriptionUpdate, Error>
6. VoiceInputManager consumes stream:
   - Partial results → updates partialText (UI sees live transcription)
   - Final result → updates partialText with final text
   - Error → sets state = .error
7. User stops recording (button tap / Fn release / silence timeout / 60s max)
8. VoiceInputManager.stopRecording() called
   - SpeechRecognitionService.stopTranscription()
   - Waits for final result
   - Appends final text to the input field's text binding
   - Sets state = .idle
```

### Key Design Decisions

#### 1. Additive-Only Changes to Existing Files

The only existing files that need modification:

| File | Change | Risk |
|---|---|---|
| `ChatInputView.swift` | Add mic `Button` in left HStack, outside `supportsVision` guard | Minimal — adding one button to an HStack |
| `PromptView.swift` | Add mic `Button` in action button area | Minimal — same pattern |
| `Package.swift` | Add `.linkedFramework("Speech")`, `.linkedFramework("AVFoundation")` | Zero risk — additive linker settings |
| `Info.plist` | Add 2 usage description keys | Zero risk — additive plist entries |
| `PermissionManager.swift` | Add `microphoneStatus` and `speechRecognitionStatus` computed properties | Minimal — additive methods |
| `HotkeyManager.swift` | Add `case voiceInput = 5` to `HotkeyIdentifier` enum | Minimal — one new enum case |
| `AppDelegate.swift` | Register Option+D hotkey for voice input toggle | Minimal — follows existing hotkey registration pattern |

No existing code paths are modified. No existing function signatures change.

#### 2. Keyboard Shortcut (Option+D Toggle)

Uses the existing Carbon `RegisterEventHotKey` mechanism via `HotkeyManager`:

```
Register Option+D as HotkeyIdentifier.voiceInput (rawValue 5)
Callback: VoiceInputManager.shared.toggleRecording()

Toggle behavior:
  - If idle → startRecording()
  - If recording → stopRecording()
```

No new `NSEvent` monitor or `VoiceInputKeyHandler` needed. The existing `HotkeyManager` handles everything, keeping the implementation simple and consistent with Option+Space, Option+Tab, Option+Shift+S.

#### 3. Silence Timeout Detection

The `SFSpeechRecognitionTask` callback fires with partial results as speech is detected. Silence is detected by tracking the time since the last partial result update:

```
silenceTimer starts when recording begins
On each partial result → reset silenceTimer
If silenceTimer fires (3s default) → stopRecording()
```

#### 4. Recording State Visual Indicator

The mic button changes appearance based on `VoiceInputState`:

| State | Mic Button Appearance |
|---|---|
| `.idle` | `mic` SF Symbol, `.secondary` color, `.plain` button style |
| `.recording` | `mic.fill` SF Symbol, `.red` color, pulsing animation (`DS.Animation.expandCollapse`) |
| `.error` | `mic.slash` SF Symbol, `.secondary` color, tooltip with error message |

Additionally, during `.recording`, a subtle red border or glow appears around the input field using `DS.Colors.errorBorder`.

#### 5. Text Append Behavior (FR-012)

When the user already has text in the input field and activates voice input:
- Transcribed text is **appended** at the end of existing text, separated by a space
- The user can edit the combined text before sending
- If the input field is empty, transcribed text starts from the beginning

## Complexity Tracking

> No constitution violations detected. All design choices use the simplest available approach.

| Aspect | Approach | Why Simplest |
|---|---|---|
| Speech recognition | Apple built-in SFSpeechRecognizer | System framework, no external deps |
| Fn key detection | NSEvent global monitor | Simpler than CGEventTap or IOKit HID |
| State management | Observable singleton + enum | Matches existing Extremis patterns |
| Audio capture | AVAudioEngine single tap | Standard Apple pattern, minimal code |
| UI integration | Button in existing HStack | No new views/controllers needed |
| Configuration | UserDefaults | Matches existing preferences pattern |
