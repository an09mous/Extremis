# Feature Specification: Voice Input

**Feature Branch**: `015-voice-input`
**Created**: 2026-05-22
**Status**: Draft
**Input**: User description: "Build voice support feature in extremis. I want to prompt via voice but extremis will still return me textual data only. It won't return voice data"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Voice Prompt via Microphone Button (Priority: P1)

A user activates Extremis via their usual hotkey and, instead of typing, taps a microphone button to speak their prompt. Extremis transcribes the speech to text in real-time, displays the transcription in the input field, and sends it to the LLM as a normal text prompt. The LLM response is returned as text only — no audio playback.

**Why this priority**: This is the core value proposition. Without basic voice-to-text input, no other voice features matter.

**Independent Test**: Can be fully tested by activating the prompt window, tapping the mic button, speaking a phrase, and verifying the transcribed text appears in the input field and is sent to the LLM.

**Acceptance Scenarios**:

1. **Given** the prompt window is open, **When** the user taps the microphone button, **Then** the system begins listening and shows a visual recording indicator.
2. **Given** the system is recording, **When** the user speaks a phrase, **Then** the spoken words appear in the input field as transcribed text in near real-time.
3. **Given** transcription is complete, **When** the user confirms (presses Enter or taps send), **Then** the transcribed text is sent to the active LLM provider and the response is displayed as text.
4. **Given** the system is recording, **When** the user taps the microphone button again, **Then** recording stops and the transcribed text remains in the input field for review or editing before sending.

---

### User Story 2 - Voice Input via Keyboard Shortcut (Priority: P2)

A user triggers voice input directly via a keyboard shortcut (Option+D) without needing to click the microphone button. This enables a fast, keyboard-driven workflow — press the shortcut to start recording, press again to stop.

**Why this priority**: Power users need a fast, keyboard-driven workflow. A shortcut for voice input removes friction.

**Independent Test**: Can be tested by pressing Option+D, speaking, pressing Option+D again, and verifying the transcribed text is placed in the input field.

**Acceptance Scenarios**:

1. **Given** the prompt window is open and not recording, **When** the user presses Option+D, **Then** recording begins immediately with a visual indicator.
2. **Given** recording is active, **When** the user presses Option+D again, **Then** recording stops and the transcribed text remains in the input field.
3. **Given** the prompt window is not open, **When** the user presses Option+D, **Then** the prompt window opens and recording begins.

---

### User Story 3 - Live Transcription Feedback (Priority: P2)

While the user is speaking, partial transcription results appear in the input field in real-time, giving the user confidence that their speech is being captured correctly.

**Why this priority**: Real-time feedback is essential for a good voice input experience — without it, users cannot tell if their speech is being recognized correctly until after they stop.

**Independent Test**: Can be tested by speaking a multi-word phrase and verifying that words appear progressively in the input field as they are spoken.

**Acceptance Scenarios**:

1. **Given** recording is active, **When** the user speaks continuously, **Then** partial transcription results appear in the input field progressively.
2. **Given** partial results are displayed, **When** the system finalizes a segment, **Then** the partial text is replaced with the final, more accurate transcription.

---

### User Story 4 - Microphone Permission Handling (Priority: P3)

When the user first attempts voice input, the system requests microphone permission if not already granted. If permission is denied, the system shows a clear message directing the user to System Settings.

**Why this priority**: Necessary for a polished experience, but secondary to core functionality.

**Independent Test**: Can be tested by revoking microphone permission and attempting voice input, verifying the appropriate guidance is shown.

**Acceptance Scenarios**:

1. **Given** microphone permission has not been granted, **When** the user activates voice input, **Then** the system requests microphone access via the standard macOS permission dialog.
2. **Given** microphone permission is denied, **When** the user attempts voice input, **Then** the system displays a message explaining how to grant permission in System Settings.
3. **Given** microphone permission is granted, **When** the user activates voice input, **Then** recording begins without any permission prompts.

---

### User Story 5 - Voice Input in Chat Mode (Priority: P3)

In an ongoing chat conversation, the user can use voice input for any message — not just the first prompt. The voice input integrates seamlessly with the existing chat flow.

**Why this priority**: Natural extension of P1, but less critical than getting the initial voice input working.

**Independent Test**: Can be tested by starting a chat, sending a typed message, then using voice input for a follow-up message in the same conversation.

**Acceptance Scenarios**:

1. **Given** an active chat conversation, **When** the user activates voice input, **Then** the transcribed text is added to the input field for the current conversation.
2. **Given** an active chat with tool calls in progress, **When** the user activates voice input, **Then** voice input works without interfering with ongoing tool execution.

---

### Edge Cases

- What happens when the user speaks in a very noisy environment? The system should still attempt transcription and display whatever it captures — accuracy may degrade but the system should not crash or hang.
- What happens when the microphone is disconnected during recording? The system should stop recording gracefully, retain any already-transcribed text, and show an appropriate message.
- What happens when the user speaks for an extended period? The system should handle input up to 60 seconds maximum, then automatically stop recording and retain the transcribed text.
- What happens when the user activates voice input but says nothing? After a silence timeout, the system should stop recording and leave the input field unchanged.
- What happens when the user switches apps while recording? Recording should stop gracefully and retain any transcribed text.
- What happens when voice input is used with Quick Mode (text selection present)? The voice input should work the same way — transcribed text replaces typed input and is sent alongside the selected text context.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a microphone button in the prompt window input area to initiate voice recording.
- **FR-002**: System MUST transcribe spoken audio to text using on-device speech recognition (no external API dependency, no network required).
- **FR-003**: System MUST display real-time partial transcription results in the input field as the user speaks.
- **FR-004**: System MUST stop recording when the user explicitly stops it (button click or key release), after a silence timeout, or after reaching the 60-second maximum duration.
- **FR-005**: System MUST allow the user to edit transcribed text before sending it to the LLM.
- **FR-006**: System MUST show a clear visual indicator when recording is active (e.g., pulsing microphone icon, colored border).
- **FR-007**: System MUST handle microphone permission requests and denials gracefully with user-friendly guidance.
- **FR-008**: System MUST support voice input in all modes: Quick Mode, Chat Mode, and Command Mode.
- **FR-009**: System MUST provide a keyboard shortcut (Option+D, toggle) for voice input activation. Press once to start recording, press again to stop.
- **FR-010**: System MUST retain all transcribed text if recording is interrupted (mic disconnect, app switch, error).
- **FR-011**: System MUST return LLM responses as text only — no audio output or text-to-speech.
- **FR-012**: System MUST allow voice input to be used alongside existing text in the input field (append, not replace).
- **FR-013**: System MUST support English language speech recognition only.

### Key Entities

- **VoiceSession**: Represents a single voice recording session — includes start/end timestamps, recording state, and the accumulated transcription text.
- **TranscriptionResult**: A segment of transcribed text — may be partial (in-progress) or final (confirmed by the recognition engine).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can complete a voice-prompted interaction (speak, review, send) in under 10 seconds for a typical single-sentence prompt.
- **SC-002**: Transcription appears in the input field within 1 second of the user speaking.
- **SC-003**: Voice input works reliably across all three input modes (Quick, Chat, Command) without errors.
- **SC-004**: Users can review and edit transcribed text before submission 100% of the time — no auto-send without user confirmation.
- **SC-005**: System gracefully handles all error conditions (no permission, mic disconnect, silence) without crashing or hanging.
- **SC-006**: Voice input adds no more than 1 additional user action compared to typed input (i.e., tap mic + speak vs. type).

## Clarifications

### Session 2026-05-22

- Q: Should voice input be disabled or warned when stealth mode is active? → A: No special behavior — voice input works identically regardless of stealth mode.
- Q: Which keyboard shortcut should trigger voice input? → A: Option+D (toggle: press to start, press again to stop). Follows existing Option+key pattern. Avoids Fn system conflicts.
- Q: What is the maximum continuous recording duration? → A: 60 seconds. Recording auto-stops and retains transcribed text.

## Assumptions

- **A-001**: The operating system's built-in speech recognition provides sufficient transcription quality for the primary system language without requiring an external API.
- **A-002**: The user has a working microphone connected to their Mac (built-in or external).
- **A-003**: Voice input is a supplementary input method — keyboard text input remains the primary method and is unaffected.
- **A-004**: No audio is stored or persisted — transcription happens in real-time and only the resulting text is kept.
- **A-005**: Default silence timeout of 3 seconds is appropriate for most users.
