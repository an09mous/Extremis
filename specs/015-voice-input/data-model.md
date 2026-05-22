# Data Model: Voice Input (015)

**Date**: 2026-05-22
**Branch**: `015-voice-input`

## Entities

### VoiceInputState (Observable Enum)

Represents the current state of the voice input system, driven by `VoiceInputManager`.

```
States:
  idle          — No recording active. Mic button shows default appearance.
  requesting    — Permission being requested. Mic button disabled.
  recording     — Actively recording and transcribing. Visual indicator active.
  error(String) — An error occurred. Shows inline error message, auto-dismisses.

Transitions:
  idle → requesting        : User taps mic / presses Option+D (first time, permission not granted)
  idle → recording         : User taps mic / presses Option+D (permission already granted)
  requesting → recording   : Permission granted
  requesting → error       : Permission denied
  requesting → idle        : User cancels permission dialog
  recording → idle         : User stops recording (button tap/Option+D toggle/silence timeout/60s max)
  recording → error        : Mic disconnected, recognizer unavailable, audio engine failure
  error → idle             : Error auto-dismissed after 3 seconds
```

### TranscriptionUpdate

A value emitted by the speech recognition stream for each partial or final result.

```
Fields:
  text: String           — The current best transcription (replaces previous partial)
  isFinal: Bool          — Whether this is the final, definitive result
  confidence: Double?    — Optional confidence score (0.0–1.0) from recognizer
```

### VoiceInputConfiguration (UserDefaults-backed)

User-configurable settings for voice input behavior.

```
Fields:
  silenceTimeoutSeconds: Double    — Seconds of silence before auto-stop (default: 3.0)
  maxDurationSeconds: Double       — Maximum recording duration (default: 60.0)
  showWaveformIndicator: Bool      — Whether to show animated waveform during recording (default: true)

Storage:
  UserDefaults keys prefixed with "voiceInput." (e.g., "voiceInput.silenceTimeout")
```

## Relationships

```
VoiceInputManager (singleton, @MainActor)
├── owns → VoiceInputState (published, drives UI)
├── owns → VoiceInputConfiguration (reads settings)
└── uses → SpeechRecognitionService (start/stop recording, receive transcription stream)

SpeechRecognitionService
├── owns → AVAudioEngine (microphone capture)
├── owns → SFSpeechRecognizer (on-device recognition)
├── owns → SFSpeechAudioBufferRecognitionRequest (per-session)
├── owns → SFSpeechRecognitionTask (per-session)
└── emits → AsyncThrowingStream<TranscriptionUpdate, Error>

HotkeyManager (existing singleton — no new component)
└── registers → Option+D as HotkeyIdentifier.voiceInput
    → callback: VoiceInputManager.shared.toggleRecording()

ChatInputView / PromptView (UI)
├── reads → VoiceInputManager.state (recording indicator, error display)
├── reads → VoiceInputManager.partialTranscription (live text in input field)
└── calls → VoiceInputManager.toggleRecording() (mic button action)
```

## No Persistence Required

Per spec assumption A-004: "No audio is stored or persisted — transcription happens in real-time and only the resulting text is kept."

- Audio buffers are transient (consumed by recognizer, not retained)
- Transcribed text flows into the existing `@Binding var text: String` in the input field
- Once sent as a chat message, the text is persisted via the existing `ChatMessage` / `JSONSessionStorage` pipeline
- No new persistence layer needed for voice input
