# Data Model: Image Attachments

**Feature**: 012-image-attachments
**Date**: 2026-05-19

## Entities

### ImageAttachment

Represents a single image attached to a chat message.

| Field | Type | Description | Constraints |
|-------|------|-------------|-------------|
| id | UUID | Unique identifier | Required, auto-generated |
| imageData | Data | Full-resolution processed image (JPEG/PNG) | Required, max 4MB after processing |
| thumbnailData | Data | Small preview image (200px, JPEG 0.6) | Required, generated from imageData, typically 5-15KB |
| originalFilename | String? | Original filename if from file picker/drag-drop | Optional, nil for clipboard pastes |
| width | Int | Image width in pixels (after processing) | Required, max 1568 |
| height | Int | Image height in pixels (after processing) | Required, max 1568 |
| fileSize | Int | Size of imageData in bytes | Required |
| format | ImageFormat | Output format (jpeg or png) | Required |
| mimeType | String | MIME type string (e.g., "image/jpeg") | Required, derived from format |
| sourceType | ImageSourceType | How the image was attached | Required |
| createdAt | Date | Timestamp of attachment | Required, auto-generated |

**Lifecycle**: Created on attach → stored in pending attachments → embedded in ChatMessage on send → persisted to disk on session save → restored on session load.

### ImageFormat (Enum)

| Case | Raw Value | MIME Type | Use Case |
|------|-----------|-----------|----------|
| jpeg | "jpeg" | "image/jpeg" | Photos, screenshots, most images |
| png | "png" | "image/png" | Images with transparency |

### ImageSourceType (Enum)

| Case | Raw Value | Description |
|------|-----------|-------------|
| clipboard | "clipboard" | Pasted from clipboard (Cmd+V) |
| filePicker | "file_picker" | Selected via NSOpenPanel |
| dragAndDrop | "drag_and_drop" | Dropped onto the window |

### ImageRef (Persistence Reference)

Stored in `PersistedMessage` to reference images on disk.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Matches ImageAttachment.id |
| filename | String | Filename on disk (e.g., "{uuid}.jpg") |
| thumbnailBase64 | String | Base64-encoded thumbnail for fast preview |
| originalFilename | String? | Original filename for display |
| width | Int | Image width |
| height | Int | Image height |
| format | String | "jpeg" or "png" |

### VisionCapability (Model Configuration Extension)

Extension to existing `LLMModel` and `models.json`.

| Field | Type | Description | Default |
|-------|------|-------------|---------|
| supportsVision | Bool | Whether the model accepts image inputs | false |

Added to the existing `capabilities` object in `models.json` alongside `supportsTools`.

## Modified Entities

### ChatMessage (Existing — Extended)

| New Field | Type | Description |
|-----------|------|-------------|
| imageAttachments | [ImageAttachment]? | Optional array of attached images, nil for text-only messages |

**Backward compatibility**: Property is optional with nil default. Existing text-only messages are unaffected. Codable conformance handles missing field gracefully.

### PersistedMessage (Existing — Extended)

| New Field | Type | Description |
|-----------|------|-------------|
| imageRefs | [ImageRef]? | Optional array of image file references with inline thumbnails |

**Backward compatibility**: Optional field. Existing persisted sessions without images load normally.

## Relationships

```text
ChatMessage 1 ──── 0..* ImageAttachment
    │
    └── (persisted as)
    │
PersistedMessage 1 ──── 0..* ImageRef
    │                         │
    │                         └── references file at:
    │                             ~/Library/Application Support/Extremis/images/{id}.{format}
    │
    └── (part of)
    │
PersistedSession
```

## State Transitions

### ImageAttachment Lifecycle

```text
[Created] ──attach──→ [Pending]
                         │
                    send message
                         │
                         ▼
                    [Sent] ──save session──→ [Persisted]
                         │                        │
                    display in                load session
                    chat history                   │
                         │                         ▼
                         └─────────────────── [Restored]

[Pending] ──remove──→ [Discarded] (image data released)
[Pending] ──send fails──→ [Pending] (preserved for retry)
```

### Vision Capability State

```text
Model selected → Check supportsVision
    │
    ├── true  → Show attachment controls, enable paste/drop
    │
    └── false → Hide attachment controls, show toast on paste attempt
```

## Storage Layout

```text
~/Library/Application Support/Extremis/
├── sessions/
│   └── {session-id}.json          # Contains PersistedMessage with ImageRef[]
└── images/
    ├── {uuid-1}.jpg               # Full-resolution processed image
    ├── {uuid-2}.jpg
    └── {uuid-3}.png               # PNG for transparency images
```

## Validation Rules

1. **Format validation**: Input must be PNG, JPEG, GIF, WebP, or HEIC. Others rejected with user notification.
2. **Size validation**: Input images >10MB trigger a warning. After processing, images must be <4MB.
3. **Count validation**: Maximum 5 images per message. Attempts to add more show limit notification.
4. **Dimension processing**: Images exceeding 1568px on longest edge are resized proportionally.
5. **Format conversion**: HEIC, GIF, and WebP inputs are converted to JPEG (or PNG if transparency detected).
6. **Vision gate**: Images can only be attached when active model has `supportsVision: true`.

## Configuration Constants

| Constant | Value | Description |
|----------|-------|-------------|
| maxImageLongEdge | 1568 | Maximum pixels on longest edge after resize |
| maxImageFileSize | 4,194,304 | Maximum bytes per image after processing (4MB) |
| maxInputImageSize | 10,485,760 | Maximum bytes for input image before processing (10MB) |
| maxImagesPerMessage | 5 | Maximum images per single message |
| thumbnailMaxSize | 200 | Maximum pixels on longest edge for thumbnails |
| jpegQuality | 0.85 | JPEG compression quality for full images |
| thumbnailJpegQuality | 0.6 | JPEG compression quality for thumbnails |
