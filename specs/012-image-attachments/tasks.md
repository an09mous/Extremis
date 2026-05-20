# Tasks: Image Attachments

**Input**: Design documents from `/specs/012-image-attachments/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Included — unit tests requested for all components.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **macOS app**: `Extremis/` at repository root (Swift Package Manager)
- **Tests**: `Extremis/Tests/` organized by module

---

## Phase 1: Setup

**Purpose**: Project structure and model configuration

- [x] T001 Add `supportsVision` capability flag to all models in `Extremis/Resources/models.json` (true for GPT-4o, GPT-4o-mini, GPT-4-turbo, all Claude 3+, all Gemini models; false for others)
- [x] T002 Update `LLMModel` to read `supportsVision` from capabilities in the model config struct (wherever `supportsTools` is read, add `supportsVision` alongside it)
- [x] T003 Create images storage directory helper — ensure `~/Library/Application Support/Extremis/images/` is created on first use (add to existing Application Support directory setup)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data model, image processing pipeline, persistence layer, and provider formatting that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

### Tests for Foundational Phase

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T004 [P] Create `ImageAttachment` model unit tests in `Extremis/Tests/Core/ImageAttachmentTests.swift` — test Codable round-trip, Equatable conformance, ImageFormat/ImageSourceType enums, ImageRef creation from ImageAttachment
- [x] T005 [P] Create `ImageProcessor` unit tests in `Extremis/Tests/Core/ImageProcessorTests.swift` — test format validation (accept PNG/JPEG/GIF/WebP/HEIC, reject TIFF/BMP), size validation (reject >10MB input), thumbnail generation (output <=200px), resize logic (output <=1568px), JPEG compression quality, base64 encoding
- [x] T006 [P] Create `ImagePersistence` unit tests in `Extremis/Tests/Utilities/ImagePersistenceTests.swift` — test save/load round-trip, restore from ImageRef, delete, file naming convention ({uuid}.{format}), missing file handling
- [x] T007 [P] Create `PromptBuilder` multimodal formatting tests in `Extremis/Tests/LLMProviders/PromptBuilderImageTests.swift` — test text-only messages unchanged, OpenAI vision format, Anthropic multimodal format, Gemini inlineData format, Ollama images array format, image-only message (no text), multiple images per message, non-vision model strips images
- [x] T008 Add all new test files (T004-T007) to `Extremis/scripts/run-tests.sh`

### Implementation for Foundational Phase

- [x] T009 [P] Create `ImageAttachment` model in `Extremis/Core/Models/ImageAttachment.swift` — struct with id (UUID), imageData (Data), thumbnailData (Data), originalFilename (String?), width (Int), height (Int), fileSize (Int), format (ImageFormat enum: jpeg/png), mimeType (String), sourceType (ImageSourceType enum: clipboard/filePicker/dragAndDrop), createdAt (Date). Must be Codable, Identifiable, Equatable.
- [x] T010 [P] Create `ImageRef` persistence struct in `Extremis/Core/Models/ImageAttachment.swift` (same file) — struct with id (UUID), filename (String), thumbnailBase64 (String), originalFilename (String?), width (Int), height (Int), format (String). Must be Codable. Add convenience init from ImageAttachment.
- [x] T011 Create `ImageProcessor` service in `Extremis/Core/Services/ImageProcessor.swift` — @MainActor singleton with: configuration constants (maxImageLongEdge=1568, maxImageFileSize=4MB, maxInputImageSize=10MB, maxImagesPerMessage=5, thumbnailMaxSize=200, jpegQuality=0.85, thumbnailJpegQuality=0.6), supportedUTTypes, `process(data:sourceType:originalFilename:) throws -> ImageAttachment`, `validate(data:) -> Result<Void, ImageProcessingError>`, `generateThumbnail(from:maxSize:) -> Data?`, `base64Encode(_:) -> String`. Use ImageIO framework (CGImageSourceCreateThumbnailAtIndex) for memory-efficient resizing. HEIC/GIF/WebP → JPEG conversion. PNG with alpha → PNG, else → JPEG. ImageProcessingError enum with unsupportedFormat, inputTooLarge, processingFailed, outputTooLarge cases.
- [x] T012 Create `ImagePersistence` actor in `Extremis/Utilities/ImagePersistence.swift` — actor with: imagesDirectory URL (~/Library/Application Support/Extremis/images/), `save(_:) throws -> ImageRef`, `save(_:[ImageAttachment]) throws -> [ImageRef]`, `loadImageData(for:) throws -> Data`, `restore(from:) throws -> ImageAttachment`, `restore(from:[ImageRef]) throws -> [ImageAttachment]`, `delete(ref:) throws`, `cleanupOrphaned(activeRefs:) throws -> Int`. Atomic file writes. Create directory on first access.
- [x] T013 Extend `ChatMessage` in `Extremis/Core/Models/ChatMessage.swift` — add optional `imageAttachments: [ImageAttachment]?` property with nil default. Ensure Codable and Equatable conformance still works. Existing text-only messages must be unaffected.
- [x] T014 Extend `PersistedMessage` in `Extremis/Core/Models/Persistence/PersistedMessage.swift` — add optional `imageRefs: [ImageRef]?` property. Update encoding/decoding to handle optional field gracefully (backward compatible with existing sessions).
- [x] T015 Extend `PromptBuilder` in `Extremis/LLMProviders/PromptBuilder.swift` — add `formatChatMessagesMultimodal(messages:) -> [[String: Any]]` method. When a message has imageAttachments, return content as array of content blocks. When text-only, return content as String (existing behavior). Images placed before text in content blocks.
- [x] T016 [P] Update `OpenAIProvider` in `Extremis/LLMProviders/OpenAIProvider.swift` — modify request builders (buildChatRequest and tool variants) to use `formatChatMessagesMultimodal`. For messages with images: content becomes array with `{"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,{data}", "detail": "auto"}}` blocks. Text-only messages use existing String format.
- [x] T017 [P] Update `AnthropicProvider` in `Extremis/LLMProviders/AnthropicProvider.swift` — modify request builders to use multimodal formatting. For messages with images: content becomes array with `{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": "{data}"}}` blocks. Images before text per Anthropic docs.
- [x] T018 [P] Update `GeminiProvider` in `Extremis/LLMProviders/GeminiProvider.swift` — modify request builders to use multimodal formatting. For messages with images: parts array gets `{"inlineData": {"mimeType": "image/jpeg", "data": "{data}"}}` entries.
- [x] T019 [P] Update `OllamaProvider` in `Extremis/LLMProviders/OllamaProvider.swift` — modify request builders. For messages with images: add separate `"images": ["{raw_base64}"]` field to message dict. Content remains plain string. No data URI prefix on base64.
- [x] T020 Verify all existing tests pass — run `cd Extremis && ./scripts/run-tests.sh` and confirm zero regressions. Verify `swift build` compiles without warnings.

**Checkpoint**: Foundation ready — image processing pipeline, persistence, provider formatting, and model capability all functional. User story implementation can now begin.

---

## Phase 3: User Story 4 — Vision Capability Detection (Priority: P1)

**Goal**: Detect whether the active model supports images and gate the UI accordingly. This is P1 and must be done before other UI stories since all attachment UI depends on vision capability gating.

**Independent Test**: Switch between vision-capable and text-only models; verify attachment controls appear/disappear.

### Implementation for User Story 4

- [x] T021 [US4] Expose `supportsVision` on the active provider/model — ensure the current model's vision capability is accessible from wherever `ChatInputView` and `PromptWindowController` read model state. Follow the same pattern used for `supportsTools`.
- [x] T022 [US4] Add vision capability gating to `ChatInputView` in `Extremis/UI/PromptWindow/ChatInputView.swift` — accept a `supportsVision: Bool` parameter. When false: hide attachment button, disable image paste/drop handlers. When true: show attachment controls. No visual changes yet (attachment UI built in US1).
- [x] T023 [US4] Add non-vision model notification — when user attempts to paste an image (Cmd+V with image on clipboard) and `supportsVision` is false, show a brief non-intrusive toast/notification: "Current model doesn't support images". Use existing notification/toast pattern if available, or add minimal toast component.
- [x] T024 [US4] Wire `supportsVision` from model config through `PromptWindowController` in `Extremis/UI/PromptWindow/PromptWindowController.swift` — pass the active model's `supportsVision` to `ChatInputView`. Update when model changes mid-conversation.

**Checkpoint**: Vision capability detection works — model switching correctly shows/hides image controls.

---

## Phase 4: User Story 1 — Paste Image from Clipboard (Priority: P1) — MVP

**Goal**: Users can paste images from clipboard into Chat Mode, see a thumbnail preview, send with a message, and see the image in conversation history.

**Independent Test**: Copy any image to clipboard, open Chat Mode, press Cmd+V, see thumbnail, type a question, press Enter — image and text sent to vision-capable LLM, response received, image visible in chat history.

### Implementation for User Story 1

- [x] T025 [P] [US1] Create `ImageAttachmentView` thumbnail strip in `Extremis/UI/PromptWindow/ImageAttachmentView.swift` — horizontal ScrollView of thumbnails (80-120px), each with "X" dismiss button (top-right), label below (originalFilename ?? "Pasted image"). Use DS.Radii.medium for corners, DS.Spacing.sm between thumbnails, DS.Colors.borderSubtle for border. Accept `attachments: [ImageAttachment]` and `onRemove: (UUID) -> Void`.
- [x] T026 [US1] Add clipboard paste image detection to `ChatInputView` in `Extremis/UI/PromptWindow/ChatInputView.swift` — intercept Cmd+V: check NSPasteboard.general for image types (public.tiff, public.png, public.jpeg, public.heic). If image found: process via ImageProcessor.shared.process(), add to pending attachments array. If both text and image on clipboard: attach image AND paste text. If only text: existing paste behavior unchanged (FR-017).
- [x] T027 [US1] Add pending attachments state and thumbnail strip to `ChatInputView` — add `@State var pendingAttachments: [ImageAttachment]` (or @Binding from parent). Show `ImageAttachmentView` above text editor when non-empty. Update send button: enabled when text is non-empty OR pendingAttachments is non-empty (FR-018). Allow image-only sends with no text.
- [x] T028 [US1] Wire pending attachments into message creation in `PromptWindowController` in `Extremis/UI/PromptWindow/PromptWindowController.swift` — when creating ChatMessage on send, attach pendingAttachments to the message's imageAttachments property. Clear pending attachments after successful send. Preserve pending attachments on send failure (FR-016).
- [x] T029 [US1] Add image display in chat history bubbles — in the existing chat message/bubble view, render image thumbnails (max 300px width, aspect ratio preserved) above message text when `message.imageAttachments` is non-empty. Use DS.Radii.medium for image corners. Click thumbnail to view full-size (Quick Look popover or NSPanel).
- [x] T030 [US1] Add image session persistence — update session save flow: call `ImagePersistence.shared.save()` for each message's images, store `ImageRef` array in `PersistedMessage.imageRefs`. Update session load flow: call `ImagePersistence.shared.restore()` from `imageRefs` to reconstruct `ImageAttachment` objects. Handle missing image files gracefully (show placeholder).
- [x] T031 [US1] Run full regression test — `cd Extremis && ./scripts/run-tests.sh`, verify `swift build` clean, manually test: paste image → thumbnail appears → send → response received → image in history → quit → relaunch → image still visible. Also verify text-only Chat Mode, Quick Mode, and Magic Mode all work unchanged.

**Checkpoint**: MVP complete — users can paste images from clipboard, send to vision-capable LLMs, see images in chat history, and images persist across sessions.

---

## Phase 5: User Story 2 — Attach Image via File Picker (Priority: P2)

**Goal**: Users can click an attachment button to open a file picker and select image files to attach.

**Independent Test**: Open Chat Mode with vision-capable model, click paperclip button, select an image file, see thumbnail, send message.

### Implementation for User Story 2

- [x] T032 [US2] Add attachment button (paperclip icon) to `ChatInputView` in `Extremis/UI/PromptWindow/ChatInputView.swift` — place to the left of send button. Only visible when `supportsVision` is true. Use SF Symbol "paperclip" or equivalent. Style with DS tokens.
- [x] T033 [US2] Implement file picker action in `ChatInputView` — on attachment button tap, present `NSOpenPanel` with: allowedContentTypes filtered to supported image formats (PNG, JPEG, GIF, WebP, HEIC), allowsMultipleSelection = true. Process selected files through `ImageProcessor.shared.process()`, add to pendingAttachments.
- [x] T034 [US2] Verify file picker integration — manually test: click attachment → pick single file → thumbnail appears → send. Pick multiple files → all thumbnails appear. Pick non-image file → rejected by type filter.

**Checkpoint**: File picker attachment works independently alongside paste.

---

## Phase 6: User Story 3 — Drag and Drop Image (Priority: P2)

**Goal**: Users can drag image files from Finder or other apps into the prompt window.

**Independent Test**: Drag a JPEG from Finder onto the prompt input area, see drop zone indicator, drop, see thumbnail preview.

### Implementation for User Story 3

- [x] T035 [P] [US3] Create `ImageDropZoneView` overlay in `Extremis/UI/PromptWindow/ImageDropZoneView.swift` — semi-transparent overlay (DS.Colors.surfacePrimary at 0.8 opacity), dashed border (DS.Colors.borderFocused), centered "Drop images here" text with image icon. Only visible when isTargeted is true. Use DS.Animation.standard for enter/exit.
- [x] T036 [US3] Add drag-and-drop support to `ChatInputView` in `Extremis/UI/PromptWindow/ChatInputView.swift` — add `.onDrop(of: [.image], isTargeted: $isDropTargeted)` modifier. On drop: load image data from NSItemProvider, process via ImageProcessor, add to pendingAttachments. Show `ImageDropZoneView` when isDropTargeted and supportsVision. Reject non-image drops.
- [x] T037 [US3] Handle multi-file drops — when user drops multiple files at once, filter to valid image types only (silently ignore non-images per edge case spec). Process each valid image and add all to pendingAttachments.
- [x] T038 [US3] Verify drag and drop — manually test: drag image over input → drop zone appears → drop → thumbnail appears. Drag non-image → drop zone doesn't activate (or drop rejected). Drag from Finder, drag from browser, drag from Preview.

**Checkpoint**: All three attachment methods (paste, pick, drag) work independently and in combination.

---

## Phase 7: User Story 5 — Multiple Images in a Single Message (Priority: P3)

**Goal**: Users can attach up to 5 images to a single message via any combination of methods.

**Independent Test**: Attach 3+ images via different methods (paste one, pick one, drag one), all appear as thumbnails, send all together.

### Implementation for User Story 5

- [x] T039 [US5] Add image count limit enforcement in `ChatInputView` — when pendingAttachments.count reaches maxImagesPerMessage (5), show brief notification "Maximum 5 images per message" on further attach attempts. Disable attachment button at limit. Paste and drop also respect limit.
- [x] T040 [US5] Make thumbnail strip horizontally scrollable — update `ImageAttachmentView` to handle >3 thumbnails gracefully. Ensure horizontal ScrollView works for 5 thumbnails without layout issues. Verify individual removal still works at any position.
- [x] T041 [US5] Add multiple image grid layout in chat history — when a message has 2+ images, display in a 2-column grid layout within the chat bubble. Single image uses full-width layout. Preserve aspect ratios.
- [x] T042 [US5] Verify multi-image flow — manually test: attach 5 images via mix of methods → all thumbnails visible and scrollable → remove middle image → 4 remain → send → grid layout in history → try to add 6th → blocked with notification.

**Checkpoint**: All 5 user stories complete and working together.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final quality, documentation, and edge case hardening

- [x] T043 [P] Update `README.md` and `Extremis/docs/` with image attachment feature documentation — supported formats, how to use, model requirements
- [x] T044 [P] Update `CLAUDE.md` with new files, patterns, and architecture changes — add ImageAttachment, ImageProcessor, ImagePersistence to Key Files section, add image-related paths to Architecture section
- [x] T045 Run orphaned image cleanup — call `ImagePersistence.cleanupOrphaned()` during session garbage collection (if such a mechanism exists) or on app launch
- [x] T046 Edge case hardening — verify: very large image (>10MB) shows appropriate error, HEIC conversion works, clipboard with both text+image handles correctly, model switch mid-conversation disables new attachments but preserves history, failed send preserves attachments for retry
- [x] T047 Run full test suite and manual QA — `cd Extremis && ./scripts/run-tests.sh`, manual test all hotkey flows (Option+Space Quick Mode, Option+Tab Magic Mode, Chat Mode with and without images), verify zero regressions
- [x] T048 Run quickstart.md validation — walk through quickstart.md steps to confirm all phases are complete and all file paths are accurate

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **US4 Vision Detection (Phase 3)**: Depends on Foundational — BLOCKS UI user stories (US1, US2, US3, US5)
- **US1 Clipboard Paste (Phase 4)**: Depends on US4 — MVP milestone
- **US2 File Picker (Phase 5)**: Depends on US4 — can run parallel with US1 but easier after
- **US3 Drag and Drop (Phase 6)**: Depends on US4 — can run parallel with US1/US2
- **US5 Multiple Images (Phase 7)**: Depends on at least one attachment method (US1, US2, or US3) being complete
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US4 (Vision Detection)**: Foundational only — no story dependencies. Gates all other UI stories.
- **US1 (Paste)**: US4 only — independently testable. **MVP target.**
- **US2 (File Picker)**: US4 only — independently testable. Can parallelize with US1.
- **US3 (Drag and Drop)**: US4 only — independently testable. Can parallelize with US1/US2.
- **US5 (Multiple Images)**: At least one of US1/US2/US3 must be done to test meaningfully.

### Within Each User Story

- Tests (T004-T008) MUST be written first and FAIL before implementation
- Models before services (T009-T010 before T011-T012)
- Services before provider formatting (T011-T012 before T015-T019)
- Foundation before UI (Phase 2 before Phase 3+)
- Story complete before moving to next priority

### Parallel Opportunities

- **Phase 2**: T004-T007 (all test files) can run in parallel. T009-T010 (models) can run in parallel. T016-T019 (providers) can run in parallel after T015.
- **Phase 4-6**: US1 (paste), US2 (file picker), US3 (drag-drop) can all run in parallel after US4 is done (if team capacity allows).
- **Phase 8**: T043-T044 (documentation) can run in parallel.

---

## Parallel Example: Foundational Phase

```bash
# Launch all test files in parallel:
Task: "T004 - ImageAttachment model tests"
Task: "T005 - ImageProcessor tests"
Task: "T006 - ImagePersistence tests"
Task: "T007 - PromptBuilder multimodal tests"

# Launch all model files in parallel:
Task: "T009 - ImageAttachment model"
Task: "T010 - ImageRef persistence struct"

# Launch all provider updates in parallel (after PromptBuilder):
Task: "T016 - OpenAI multimodal"
Task: "T017 - Anthropic multimodal"
Task: "T018 - Gemini multimodal"
Task: "T019 - Ollama multimodal"
```

## Parallel Example: UI Phases (after US4 complete)

```bash
# Can run US1, US2, US3 in parallel if desired:
Task: "US1 - Clipboard paste (Phase 4)"
Task: "US2 - File picker (Phase 5)"
Task: "US3 - Drag and drop (Phase 6)"
```

---

## Implementation Strategy

### MVP First (User Story 1 + Vision Detection Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T020)
3. Complete Phase 3: US4 Vision Detection (T021-T024)
4. Complete Phase 4: US1 Paste from Clipboard (T025-T031)
5. **STOP and VALIDATE**: Paste image → send → see in history → persists across sessions
6. Deploy/demo if ready — this is the MVP

### Incremental Delivery

1. Setup + Foundational → Core pipeline ready
2. Add US4 (Vision Detection) → Capability gating ready
3. Add US1 (Paste) → **MVP!** Test independently → Deploy
4. Add US2 (File Picker) → Test independently → Deploy
5. Add US3 (Drag and Drop) → Test independently → Deploy
6. Add US5 (Multiple Images) → Test independently → Deploy
7. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All code changes are additive — existing text-only flows must remain untouched
- Run `./scripts/run-tests.sh` after every phase to catch regressions early
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Configuration constants (maxImagesPerMessage, jpegQuality, etc.) defined in ImageProcessor — single source of truth
