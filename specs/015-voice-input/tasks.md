# Tasks: Voice Input

**Input**: Design documents from `/specs/015-voice-input/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: Included per CLAUDE.md requirement ("All new code MUST include unit tests").

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add framework dependencies and permission keys required by all voice input features

- [X] T001 Add Speech and AVFoundation linked frameworks in Extremis/Package.swift
- [X] T002 [P] Add NSMicrophoneUsageDescription and NSSpeechRecognitionUsageDescription keys in Extremis/Info.plist

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core models, services, and permission infrastructure that MUST be complete before ANY user story can be implemented

- [X] T003 Create VoiceInputState enum, TranscriptionUpdate struct, and VoiceInputConfiguration struct in Extremis/Core/Models/VoiceInputModels.swift
- [X] T004 Create SpeechRecognitionService with AVAudioEngine + SFSpeechRecognizer, startTranscription() returning AsyncThrowingStream<TranscriptionUpdate, Error>, stopTranscription(), and proper cleanup in Extremis/Core/Services/SpeechRecognitionService.swift
- [X] T005 Create VoiceInputManager @MainActor singleton with @Published state/partialTranscription, toggleRecording(), startRecording(), stopRecording(), silence timeout timer, 60-second max duration timer, and text append logic (FR-012) in Extremis/Core/Services/VoiceInputManager.swift
- [X] T006 [P] Add microphoneStatus, speechRecognitionStatus computed properties and requestMicrophoneAccess(), requestSpeechRecognitionAccess() async methods to Extremis/Core/Services/PermissionManager.swift
- [X] T007 [P] Create unit tests for VoiceInputState transitions, VoiceInputConfiguration defaults, and TranscriptionUpdate in Extremis/Tests/Core/VoiceInputModelsTests.swift and add to Extremis/scripts/run-tests.sh

**Checkpoint**: Foundation ready — VoiceInputManager can start/stop recording, transcribe speech, and manage state. User story implementation can now begin.

---

## Phase 3: User Story 1 — Voice Prompt via Microphone Button (Priority: P1) MVP

**Goal**: User can tap a mic button in the prompt window to speak, see transcribed text in the input field, and send it to the LLM.

**Independent Test**: Open prompt window → tap mic button → speak → see transcription in input field → tap mic again to stop → press Enter to send → verify LLM responds with text.

### Implementation for User Story 1

- [X] T008 [US1] Create VoiceInputIndicator SwiftUI component with mic button (idle/recording/error states), pulsing animation using DS.Animation.expandCollapse, and SF Symbols (mic/mic.fill/mic.slash) in Extremis/UI/PromptWindow/VoiceInputIndicator.swift
- [X] T009 [US1] Add mic button to ChatInputView in the left HStack outside the supportsVision guard, wired to VoiceInputManager.shared.toggleRecording(), with live partialTranscription binding to text field in Extremis/UI/PromptWindow/ChatInputView.swift
- [X] T010 [US1] Add mic button to PromptView (Quick Mode) in the action button area, wired to VoiceInputManager.shared.toggleRecording(), with live partialTranscription binding to instructionText in Extremis/UI/PromptWindow/PromptView.swift
- [X] T011 [US1] Verify build succeeds and run existing test suite (cd Extremis && swift build && ./scripts/run-tests.sh) to confirm no regressions

**Checkpoint**: User Story 1 is fully functional — mic button visible, voice-to-text works, text editable before send.

---

## Phase 4: User Story 2 — Voice Input via Keyboard Shortcut (Priority: P2)

**Goal**: User can press Option+D to toggle voice recording without clicking the mic button.

**Independent Test**: Open prompt window → press Option+D → speak → press Option+D → verify transcription in input field. Also test: press Option+D with window closed → verify window opens and recording starts.

### Implementation for User Story 2

- [X] T012 [US2] Add case voiceInput = 5 to HotkeyIdentifier enum in Extremis/Core/Services/HotkeyManager.swift
- [X] T013 [US2] Register Option+D hotkey in setupHotkey() with callback to VoiceInputManager.shared.toggleRecording(), including logic to show prompt window if not visible, in Extremis/App/AppDelegate.swift
- [X] T014 [US2] Verify build succeeds and run existing test suite to confirm no regressions

**Checkpoint**: User Story 2 complete — Option+D toggles voice input globally.

---

## Phase 5: User Story 3 — Live Transcription Feedback (Priority: P2)

**Goal**: Partial transcription results appear progressively in the input field while the user speaks.

**Independent Test**: Start recording → speak a multi-word sentence → verify words appear progressively, not all at once after stopping.

### Implementation for User Story 3

- [X] T015 [US3] Ensure SpeechRecognitionService sets shouldReportPartialResults = true on SFSpeechAudioBufferRecognitionRequest and emits both partial (isFinal=false) and final (isFinal=true) TranscriptionUpdate values through the stream in Extremis/Core/Services/SpeechRecognitionService.swift
- [X] T016 [US3] Ensure VoiceInputManager updates @Published partialTranscription on each partial result, and ChatInputView/PromptView reflect partial text in the input field with a visual distinction (e.g., lighter color or italic) for unfinalized text in Extremis/Core/Services/VoiceInputManager.swift and Extremis/UI/PromptWindow/ChatInputView.swift

**Checkpoint**: User Story 3 complete — real-time streaming transcription visible while speaking.

---

## Phase 6: User Story 4 — Microphone Permission Handling (Priority: P3)

**Goal**: System requests microphone and speech recognition permissions on first use, shows clear guidance if denied.

**Independent Test**: Revoke microphone permission → tap mic button → verify error message with System Settings link appears. Grant permission → tap mic → verify recording starts.

### Implementation for User Story 4

- [X] T017 [US4] Add permission check flow in VoiceInputManager.startRecording(): check SFSpeechRecognizer.authorizationStatus and AVCaptureDevice.authorizationStatus, request if .notDetermined, show error with System Settings guidance if .denied, in Extremis/Core/Services/VoiceInputManager.swift
- [X] T018 [US4] Display permission error state in VoiceInputIndicator: show mic.slash icon with tooltip containing actionable guidance ("Open System Settings > Privacy > Microphone") in Extremis/UI/PromptWindow/VoiceInputIndicator.swift
- [X] T019 [US4] Add Siri availability check: if SFSpeechRecognizer.supportsOnDeviceRecognition is false, show guidance to enable Siri in System Settings in Extremis/Core/Services/VoiceInputManager.swift

**Checkpoint**: User Story 4 complete — all permission states handled gracefully.

---

## Phase 7: User Story 5 — Voice Input in Chat Mode (Priority: P3)

**Goal**: Voice input works for any message in an ongoing chat conversation, not just the first prompt.

**Independent Test**: Start a chat → send a typed message → get response → use voice input for follow-up → verify transcribed text enters input field and sends correctly.

### Implementation for User Story 5

- [X] T020 [US5] Verify voice input works in active chat sessions: ensure VoiceInputManager.toggleRecording() operates independently of chat generation state, and transcribed text appends to current input field without interfering with ongoing tool execution in Extremis/UI/PromptWindow/ChatInputView.swift
- [X] T021 [US5] Handle edge case: if recording is active when user sends a message (Enter key), stop recording first, finalize transcription, then send the combined text in Extremis/UI/PromptWindow/ChatInputView.swift

**Checkpoint**: User Story 5 complete — voice input works seamlessly in multi-turn conversations.

---

## Phase 8: Edge Cases & Robustness

**Purpose**: Handle all edge cases identified in the spec

- [X] T022 Handle microphone disconnect during recording: catch AVAudioEngine errors, stop recording gracefully, retain transcribed text, show error message in Extremis/Core/Services/SpeechRecognitionService.swift
- [X] T023 Handle app switch during recording: observe NSApplication.didResignActiveNotification to stop recording and retain text in Extremis/Core/Services/VoiceInputManager.swift
- [X] T024 Handle silence timeout: implement configurable silence timer (default 3s) that fires when no partial results arrive, auto-stops recording in Extremis/Core/Services/VoiceInputManager.swift
- [X] T025 Handle 60-second max duration: implement max duration timer that auto-stops recording and retains all transcribed text in Extremis/Core/Services/VoiceInputManager.swift
- [X] T026 Handle noisy environment: ensure SpeechRecognitionService does not crash or hang on low-confidence results, always delivers whatever is transcribed in Extremis/Core/Services/SpeechRecognitionService.swift

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, final tests, and quality assurance

- [X] T027 Update CLAUDE.md with voice input feature documentation: new files, key patterns, hotkey (Option+D), framework deps in /Users/shivamsaxena/Documents/Personal/Extremis/CLAUDE.md
- [X] T028 Update README.md with voice input usage instructions and Option+D shortcut in /Users/shivamsaxena/Documents/Personal/Extremis/README.md
- [X] T029 Run full build and test suite, verify zero regressions: cd Extremis && swift build && ./scripts/run-tests.sh
- [ ] T030 Manual QA: test all five user stories end-to-end, verify all edge cases from spec

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **User Stories (Phase 3–7)**: All depend on Phase 2 completion
  - US1 (Phase 3): No dependencies on other stories — **MVP**
  - US2 (Phase 4): No dependencies on other stories (uses existing HotkeyManager)
  - US3 (Phase 5): Refines behavior from Phase 2 (SpeechRecognitionService partial results)
  - US4 (Phase 6): Refines behavior from Phase 2 (VoiceInputManager permission flow)
  - US5 (Phase 7): Depends on US1 (mic button in ChatInputView must exist)
- **Edge Cases (Phase 8)**: Depends on Phase 2; can proceed in parallel with user stories
- **Polish (Phase 9)**: Depends on all previous phases

### User Story Dependencies

- **US1 (P1)**: Can start after Phase 2 — No dependencies on other stories
- **US2 (P2)**: Can start after Phase 2 — No dependencies on other stories
- **US3 (P2)**: Can start after Phase 2 — Refines SpeechRecognitionService from Phase 2
- **US4 (P3)**: Can start after Phase 2 — Refines VoiceInputManager from Phase 2
- **US5 (P3)**: Depends on US1 completion (mic button must exist in ChatInputView)

### Within Each User Story

- Models before services
- Services before UI integration
- Core implementation before edge cases
- Story complete before moving to next priority

### Parallel Opportunities

- T001 and T002 can run in parallel (Phase 1)
- T006 and T007 can run in parallel with T003–T005 (Phase 2)
- US1 and US2 can proceed in parallel after Phase 2
- US3 and US4 can proceed in parallel after Phase 2
- Edge case tasks (T022–T026) can proceed in parallel with each other

---

## Parallel Example: Phase 2

```bash
# Sequential (dependencies):
T003 → T004 → T005  (Models → SpeechService → VoiceInputManager)

# Parallel (different files):
T006 (PermissionManager.swift)  ←→  T007 (VoiceInputModelsTests.swift)
# Both can run alongside T003–T005
```

## Parallel Example: User Stories after Phase 2

```bash
# US1 and US2 can proceed in parallel:
Agent 1: T008 → T009 → T010 → T011  (US1: mic button UI)
Agent 2: T012 → T013 → T014          (US2: Option+D hotkey)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T002)
2. Complete Phase 2: Foundational (T003–T007)
3. Complete Phase 3: User Story 1 (T008–T011)
4. **STOP and VALIDATE**: Test mic button → speak → transcription → send → LLM response
5. Deploy/demo if ready

### Incremental Delivery

1. Setup + Foundational → Core voice engine ready
2. Add US1 (mic button) → Test → **MVP deployed**
3. Add US2 (Option+D) + US3 (live feedback) → Test → Enhanced UX
4. Add US4 (permissions) + US5 (chat mode) → Test → Polished experience
5. Edge cases + polish → Production ready

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- All new test files MUST be added to scripts/run-tests.sh
- Highest priority: zero regressions to existing functionality
