# Research: Voice Input (015)

**Date**: 2026-05-22
**Branch**: `015-voice-input`

## Decision 1: Speech Recognition Framework

**Decision**: Use Apple's `SFSpeechRecognizer` (Speech framework) with `requiresOnDeviceRecognition = true`.

**Rationale**:
- Available on macOS 10.15+; our target macOS 13.0+ is fully covered
- On-device mode: zero network dependency, zero rate limits, no duration limits
- English on-device recognition supported on all Apple Silicon and Intel Macs with macOS 13+
- `shouldReportPartialResults = true` provides real-time streaming partial transcription
- `AVAudioEngine` microphone tap is a single `.installTap()` call
- `AsyncThrowingStream` pattern fits naturally into Extremis's existing LLM streaming architecture
- No external dependencies — `Speech` and `AVFoundation` are system frameworks

**Alternatives considered**:

| Alternative | Why Rejected |
|---|---|
| `NSSpeechRecognizer` (AppKit) | Command-recognition only — no free-form transcription, no partial results |
| Apple System Dictation | Not programmatically accessible — no public API to start/stop or capture output |
| Whisper.cpp / WhisperKit | Overkill for menu bar app. WhisperKit requires macOS 14+ (conflicts with our macOS 13 target). Raw whisper.cpp needs C bridging, ~273MB–3.9GB RAM per model. Complex integration for marginal accuracy gain |

**Gotcha**: `SFSpeechRecognizer` requires Siri to be enabled in System Settings for on-device mode. If Siri is disabled, `supportsOnDeviceRecognition` returns `false`. The app should detect this and show clear guidance.

## Decision 2: Keyboard Shortcut — Option+D Toggle

**Decision**: Use `Option+D` as a toggle shortcut (press to start, press to stop) via the existing Carbon `RegisterEventHotKey` mechanism in `HotkeyManager`.

**Rationale**:
- Uses the existing `HotkeyManager` Carbon hotkey system — no new event handling mechanism needed
- "D" for Dictation — mnemonic and easy to remember
- Follows established Extremis pattern: Option+Space, Option+Tab, Option+Shift+S
- Toggle behavior is simpler than hold-to-talk (no key-up detection needed)
- No system conflicts — Option+D is not reserved by macOS
- Eliminates the need for `VoiceInputKeyHandler`, `NSEvent` global monitor, and Fn system-conflict detection

**Alternatives considered**:

| Alternative | Why Rejected |
|---|---|
| Fn key (hold-to-talk) | Carbon can't capture Fn; system conflict with Dictation/Emoji; requires NSEvent monitor and user System Settings changes |
| `NSEvent.addGlobalMonitorForEvents` | Heavier mechanism; unnecessary when Carbon toggle works |
| Option+V / Option+M | Less mnemonic than "D" for Dictation |
| Hold-to-talk (any key) | Requires key-up detection; Carbon only fires key-down; would need separate NSEvent monitor |

## Decision 3: Audio Engine Pattern

**Decision**: Single `AVAudioEngine` instance owned by `SpeechRecognitionService`, with tap installed/removed per recording session.

**Rationale**:
- `audioEngine.inputNode.outputFormat(forBus: 0)` gives native hardware format — no manual resampling needed
- macOS has no `AVAudioSession` category system (unlike iOS) — audio engine connects directly to hardware
- `audioEngine.prepare()` before `audioEngine.start()` pre-allocates buffers, reducing start latency
- Tap closure receives `AVAudioPCMBuffer` objects, passed to `request.append(buffer)` — no manual retention needed
- Clean shutdown order: `engine.stop()` → `removeTap(onBus: 0)` → `request.endAudio()` → `task.finish()`

## Decision 4: Service Architecture

**Decision**: `@MainActor` singleton `VoiceInputManager` coordinating `SpeechRecognitionService` (audio + recognition). Keyboard shortcut handled by existing `HotkeyManager`. Expose transcription via `AsyncThrowingStream<String, Error>`.

**Rationale**:
- Matches Extremis's established singleton pattern (`HotkeyManager.shared`, `StealthManager.shared`)
- `AsyncThrowingStream` mirrors the `LLMProvider.generateStream()` pattern already used for LLM responses
- Keyboard shortcut uses existing `HotkeyManager` — no separate key handler component needed
- `@MainActor` ensures thread safety for UI state updates (recording indicator, text binding)

## Decision 5: UI Integration Points

**Decision**: Mic button in `ChatInputView` button row (outside `supportsVision` guard). Write transcription to existing `@Binding var text: String`.

**Rationale**:
- `ChatInputView` already has attachment buttons (paperclip, camera) in an `HStack(spacing: 4)` — mic button fits the same pattern
- Voice input is independent of vision capability, so it lives outside the `if supportsVision` conditional
- Writing to `@Binding var text: String` automatically propagates to `NSTextView.string` via `updateNSView`
- `canSend` flag (`!text.isEmpty || !pendingAttachments.isEmpty`) auto-enables send button when transcription appears
- For Quick Mode (`PromptView.swift`), same pattern via `@Binding var instructionText: String`

## Decision 6: Permission Requirements

**Decision**: Two Info.plist keys + Speech framework authorization check.

| Requirement | Key / API |
|---|---|
| Microphone access | `NSMicrophoneUsageDescription` in Info.plist |
| Speech recognition | `NSSpeechRecognitionUsageDescription` in Info.plist |
| Runtime check | `SFSpeechRecognizer.requestAuthorization()` on first voice input activation |
| Denied state | Direct user to System Settings > Privacy > Speech Recognition / Microphone |

No sandbox entitlement needed — Extremis has sandbox disabled.

## Decision 7: Framework Dependencies

**Decision**: Add `Speech` and `AVFoundation` as linked frameworks in `Package.swift`.

```swift
linkerSettings: [
    .linkedFramework("Carbon"),
    .linkedFramework("ApplicationServices"),
    .linkedFramework("Speech"),        // SFSpeechRecognizer
    .linkedFramework("AVFoundation"),  // AVAudioEngine
]
```

No new Swift Package Manager dependencies required.
