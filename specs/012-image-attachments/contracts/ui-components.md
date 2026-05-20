# Contract: UI Components for Image Attachments

**Module**: `UI/PromptWindow/`

## ImageAttachmentView

**File**: `UI/PromptWindow/ImageAttachmentView.swift`
**Type**: SwiftUI `View`

Displays a horizontal strip of thumbnail previews for pending image attachments.

```swift
struct ImageAttachmentView: View {
    let attachments: [ImageAttachment]
    let onRemove: (UUID) -> Void

    // Renders:
    // - Horizontal ScrollView of thumbnails (80-120px each)
    // - Each thumbnail has an "X" dismiss button (top-right corner)
    // - Label below each: originalFilename ?? "Pasted image"
    // - Uses DS.Radii.medium for thumbnail corners
    // - Uses DS.Spacing.sm between thumbnails
    // - Uses DS.Colors.borderSubtle for thumbnail border
}
```

## ImageDropZoneView

**File**: `UI/PromptWindow/ImageDropZoneView.swift`
**Type**: SwiftUI `View`

Overlay that appears when user drags an image file over the input area.

```swift
struct ImageDropZoneView: View {
    let isTargeted: Bool

    // Renders:
    // - Semi-transparent overlay (DS.Colors.surfacePrimary at 0.8 opacity)
    // - Dashed border (DS.Colors.borderFocused)
    // - "Drop images here" text with image icon
    // - Animated appearance/disappearance (DS.Animation.standard)
    // - Only visible when isTargeted == true
}
```

## ChatInputView Modifications

**File**: `UI/PromptWindow/ChatInputView.swift` (existing)

### New Properties

```swift
@Binding var pendingAttachments: [ImageAttachment]
let supportsVision: Bool  // From current model's capabilities
```

### New UI Elements

1. **Attachment button**: Paperclip icon to the left of send button. Hidden when `!supportsVision`.
2. **Attachment strip**: `ImageAttachmentView` shown above text editor when `pendingAttachments` is non-empty.
3. **Drop zone**: `.onDrop(of: [.image])` modifier on the entire input area.
4. **Paste handler**: Intercept Cmd+V to check for image content on NSPasteboard.

### Send Button Behavior Change

Currently: enabled when text is non-empty.
New: enabled when text is non-empty OR `pendingAttachments` is non-empty (FR-018).

### Non-Vision Model Behavior

- Attachment button: hidden
- Paste image: show brief toast "Current model doesn't support images"
- Drag image: drop zone doesn't activate

## Chat Bubble Image Display

**File**: `UI/PromptWindow/ChatBubbleView.swift` (or equivalent existing message view)

### Image Rendering in History

- Display images as inline thumbnails (max 300px width) above message text
- Multiple images: 2-column grid layout
- Click thumbnail: show full-size image via Quick Look popover or NSPanel
- Images use DS.Radii.medium corner radius
- Aspect ratio preserved

## Behavior Contract

1. **All DS tokens**: Use DesignSystem tokens for colors, spacing, radii, shadows. No hardcoded values.
2. **Responsive**: Thumbnail strip scrolls horizontally for >3 images. No layout jumps.
3. **Accessibility**: Thumbnails have accessibility labels ("Attached image: {filename}"). Remove buttons are keyboard accessible.
4. **Animation**: Drop zone uses DS.Animation.standard for enter/exit. Thumbnail addition/removal uses default SwiftUI transitions.
5. **Chat Mode only**: All image attachment UI is gated on Chat Mode (FR-019). Quick Mode and Magic Mode show no attachment controls.
