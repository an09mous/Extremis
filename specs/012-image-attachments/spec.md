# Feature Specification: Image Attachments

**Feature Branch**: `012-image-attachments`
**Created**: 2026-05-19
**Status**: Draft
**Input**: User description: "Build the functionality to attach images, paste images and then feed it to llm if it supports in extremis"

## Clarifications

### Session 2026-05-19

- Q: How should Quick Mode (Option+Space with selection) handle images, given it auto-generates without a text input step? → A: Quick Mode remains text-only; image attachments are only available in Chat Mode.
- Q: Should Magic Mode (Option+Tab) support image-based summarization? → A: Out of scope; Magic Mode remains text-only.
- Q: Can users send an image with no accompanying text? → A: Yes, image-only sends are allowed with no injected default prompt; the LLM handles it as-is.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Paste Image from Clipboard (Priority: P1)

A user copies a screenshot or image to their clipboard and wants to include it in their conversation with the LLM. They open the Extremis prompt window and paste the image (Cmd+V). The image appears as a thumbnail preview in the input area. When they send their message, the image is included alongside the text and the LLM analyzes or responds based on the image content.

**Why this priority**: Pasting images from the clipboard is the fastest and most common way users share visual content. Screenshots are a primary use case for a context-aware assistant — users want to ask about what they see on screen.

**Independent Test**: Can be fully tested by copying any image to clipboard, pasting into the prompt window, and sending a message. Delivers immediate value by enabling visual context in conversations.

**Acceptance Scenarios**:

1. **Given** the user has an image on the clipboard, **When** they press Cmd+V in the prompt input area, **Then** a thumbnail preview of the image appears attached to the input area.
2. **Given** the user has pasted an image and typed a question, **When** they press Enter to send, **Then** the message is sent to the LLM with both the text and image content.
3. **Given** the user has pasted an image, **When** they click a remove/dismiss button on the image preview, **Then** the image is removed from the pending attachments.
4. **Given** the user has pasted an image, **When** the image is displayed in the conversation history, **Then** it appears as a properly sized thumbnail that can be viewed at full size.

---

### User Story 2 - Attach Image via File Picker (Priority: P2)

A user wants to attach an existing image file from their disk. They click an attachment button in the input area, which opens a file picker dialog. They select one or more image files, which appear as thumbnail previews. The images are included when the message is sent.

**Why this priority**: File attachment is the standard secondary method for sharing images. It covers cases where the image isn't on the clipboard — such as saved screenshots, design mockups, or reference images.

**Independent Test**: Can be fully tested by clicking the attach button, selecting an image file, and sending a message with it. Delivers value by supporting pre-existing image files.

**Acceptance Scenarios**:

1. **Given** the prompt window is open, **When** the user clicks the attachment button, **Then** a file picker dialog appears filtered to supported image formats.
2. **Given** the file picker is open, **When** the user selects one or more image files, **Then** thumbnail previews appear in the input area for each selected image.
3. **Given** multiple images are attached, **When** the user sends the message, **Then** all images are included with the message to the LLM.

---

### User Story 3 - Drag and Drop Image (Priority: P2)

A user drags an image file from Finder or another application into the Extremis prompt window. The image is accepted and appears as a thumbnail preview, ready to be sent with the next message.

**Why this priority**: Drag and drop is a natural macOS interaction pattern that complements paste and file picker. It shares implementation with the file attachment flow and provides a convenient alternative.

**Independent Test**: Can be fully tested by dragging an image file onto the prompt window and verifying it appears as an attachment.

**Acceptance Scenarios**:

1. **Given** the prompt window is open, **When** the user drags an image file over the input area, **Then** a visual drop zone indicator appears.
2. **Given** the drop zone is active, **When** the user drops the image file, **Then** a thumbnail preview appears in the input area.
3. **Given** the user drags a non-image file over the input area, **When** they attempt to drop it, **Then** the drop is rejected and an appropriate message is shown.

---

### User Story 4 - Vision Capability Detection (Priority: P1)

The system detects whether the currently selected LLM provider and model supports image/vision inputs. If the model does not support images, the image attachment controls are hidden or disabled, and the user is informed if they attempt to attach an image.

**Why this priority**: This is critical for preventing user frustration — attempting to send images to a text-only model would result in errors or silent failures. Users need clear feedback about what their current model supports.

**Independent Test**: Can be fully tested by switching between vision-capable and text-only models and verifying the UI updates accordingly.

**Acceptance Scenarios**:

1. **Given** the user has selected a vision-capable model, **When** the prompt window opens, **Then** the image attachment button is visible and paste/drop are enabled.
2. **Given** the user has selected a text-only model, **When** the prompt window opens, **Then** the image attachment button is hidden or disabled.
3. **Given** the user has selected a text-only model, **When** they attempt to paste an image, **Then** a brief, non-intrusive notification informs them that the current model does not support images.
4. **Given** the user switches from a vision-capable model to a text-only model mid-conversation, **When** images were previously sent in the conversation, **Then** the conversation history still displays the images but new image attachments are disabled.

---

### User Story 5 - Multiple Images in a Single Message (Priority: P3)

A user attaches multiple images to a single message — through any combination of paste, file picker, and drag-and-drop. All images appear as a scrollable row of thumbnails and are sent together with the text message.

**Why this priority**: While single image attachment covers most use cases, supporting multiple images enables comparison scenarios (e.g., "which design looks better?") and richer context sharing.

**Independent Test**: Can be fully tested by attaching 2+ images via different methods and verifying all are sent and displayed.

**Acceptance Scenarios**:

1. **Given** the user has attached one image, **When** they paste or attach another image, **Then** both images appear as thumbnails in the input area.
2. **Given** multiple images are attached, **When** the user removes one image, **Then** the remaining images stay attached.
3. **Given** the user attaches more images than the maximum allowed, **When** they attempt to add another, **Then** they are informed of the limit and the additional image is not added.

---

### Edge Cases

- What happens when the user pastes a very large image (e.g., 50MB+)? The system should resize/compress images above a reasonable size threshold before sending to the LLM, and inform the user if the image exceeds the maximum allowed size after compression.
- What happens when the user pastes non-image clipboard content (e.g., text, files)? Text paste should continue to work as normal; non-image files should be ignored for image attachment.
- What happens when the LLM provider's connection fails mid-upload? The message should fail gracefully with an appropriate error, and the user's text and image attachments should be preserved for retry.
- What happens when the user pastes an image in Quick Mode (with text selection)? Quick Mode is text-only; image paste is ignored and text paste continues to work as normal.
- What happens when the clipboard contains both text and an image? The system should attach the image and insert the text separately, allowing both to be sent.
- How does image attachment interact with the conversation persistence system? Images should be persisted as part of the conversation history so they are available when sessions are restored.
- What happens when a user drags multiple files at once, some of which are not images? Only the valid image files should be accepted; non-image files should be silently ignored.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow users to paste images from the clipboard into the prompt input area using Cmd+V.
- **FR-002**: System MUST allow users to attach image files via a file picker dialog accessible from an attachment button in the input area.
- **FR-003**: System MUST allow users to drag and drop image files into the prompt window.
- **FR-004**: System MUST display attached images as thumbnail previews in the input area before sending.
- **FR-005**: System MUST allow users to remove individual attached images before sending.
- **FR-006**: System MUST send attached images to the LLM alongside the text message when the user submits.
- **FR-007**: System MUST detect whether the active LLM provider and model supports image/vision inputs.
- **FR-008**: System MUST hide or disable image attachment controls when the active model does not support images.
- **FR-009**: System MUST inform the user with a brief notification when they attempt to attach an image to a non-vision model.
- **FR-010**: System MUST display sent images in the conversation history as viewable thumbnails.
- **FR-011**: System MUST support attaching multiple images to a single message, up to a configurable maximum (default: 5).
- **FR-012**: System MUST support common image formats: PNG, JPEG, GIF, WebP, HEIC.
- **FR-013**: System MUST resize or compress images that exceed a size threshold (10MB) before sending to the LLM.
- **FR-014**: System MUST show a visual drop zone indicator when an image file is dragged over the prompt window.
- **FR-015**: System MUST persist image attachments as part of conversation history for session restoration.
- **FR-016**: System MUST preserve the user's text and image attachments if sending fails, allowing retry.
- **FR-017**: System MUST continue to handle text-only paste (Cmd+V) as normal when no image is on the clipboard.
- **FR-018**: System MUST allow users to send a message containing only image(s) with no accompanying text.
- **FR-019**: System MUST limit image attachment support to Chat Mode only; Quick Mode and Magic Mode remain text-only.

### Key Entities

- **ImageAttachment**: Represents a single image attached to a message. Key attributes: unique identifier, image data, original filename (if from file), dimensions, file size, format, thumbnail representation.
- **VisionCapability**: Represents whether a given LLM provider/model combination supports image inputs. Associated with the model configuration.
- **AttachmentGroup**: Represents the collection of images attached to a single pending message. Tracks count against maximum limit.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can attach an image (via paste, file picker, or drag-and-drop) and send it with a message in under 5 seconds.
- **SC-002**: Image thumbnails render in the input area within 1 second of attachment.
- **SC-003**: 100% of image attachment attempts to non-vision models result in clear user feedback (no silent failures).
- **SC-004**: Users can attach and send up to 5 images in a single message without performance degradation.
- **SC-005**: Images persist correctly across session save and restore — 100% of images in conversation history are viewable after reopening a session.
- **SC-006**: All three attachment methods (paste, file picker, drag-and-drop) work independently and can be used in combination within a single message.
- **SC-007**: Images above the size threshold are automatically processed and sent successfully without user intervention.

## Assumptions

- LLM providers that support vision (e.g., OpenAI GPT-4o, Anthropic Claude 3+, Google Gemini) accept base64-encoded images or image URLs in their message payloads. The specific encoding format will be determined during implementation.
- The maximum number of images per message (default 5) is a reasonable limit that balances usability with provider constraints. This can be adjusted per-provider if needed.
- Image compression/resizing to stay under 10MB is sufficient for all supported LLM providers' size limits.
- HEIC format images (common on macOS) will be converted to a universally supported format (e.g., JPEG/PNG) before sending to providers.
- The existing conversation persistence system can be extended to store image data (either inline or as file references).
- Only Chat Mode supports image attachments. Quick Mode and Magic Mode remain text-only to preserve their instant, no-input-required workflows.
