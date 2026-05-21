// MARK: - Image Attachment View
// Horizontal thumbnail strip for pending and displayed image attachments

import SwiftUI

/// Horizontal scrollable strip of image thumbnails with remove buttons
struct ImageAttachmentView: View {
    let attachments: [ImageAttachment]
    let onRemove: ((UUID) -> Void)?

    init(attachments: [ImageAttachment], onRemove: ((UUID) -> Void)? = nil) {
        self.attachments = attachments
        self.onRemove = onRemove
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(attachments) { attachment in
                    ImageThumbnailView(
                        attachment: attachment,
                        onRemove: onRemove != nil ? { onRemove?(attachment.id) } : nil
                    )
                }
            }
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.xs)
        }
    }
}

/// Single image thumbnail with optional remove button
struct ImageThumbnailView: View {
    let attachment: ImageAttachment
    var onRemove: (() -> Void)?

    @State private var isHovering = false

    private let thumbnailSize: CGFloat = 80

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                thumbnailImage
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .continuousCornerRadius(DS.Radii.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radii.medium, style: .continuous)
                            .stroke(DS.Colors.borderSubtle, lineWidth: 1)
                    )

                if let onRemove, isHovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.secondary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .transition(.opacity)
                }
            }
            .onHover { hovering in
                withAnimation(DS.Animation.hoverTransition) {
                    isHovering = hovering
                }
            }

            Text(attachment.displayLabel)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: thumbnailSize)
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let nsImage = NSImage(data: attachment.thumbnailData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipped()
        } else {
            // Fallback placeholder
            Rectangle()
                .fill(DS.Colors.surfaceElevated)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
        }
    }
}

// MARK: - Chat History Image View

/// Renders image thumbnails inline within chat message bubbles (read-only, no remove)
/// Single image: full-width. 2+ images: 2-column grid layout.
/// Click on any image to expand it to full size.
struct ChatMessageImageView: View {
    let attachments: [ImageAttachment]

    @State private var expandedAttachment: ImageAttachment?

    private let maxSingleImageWidth: CGFloat = 300
    private let gridSpacing: CGFloat = 4
    private let gridThumbnailSize: CGFloat = 120

    var body: some View {
        Group {
            if attachments.count == 1, let attachment = attachments.first {
                singleImageView(attachment)
            } else {
                gridImageView
            }
        }
        .sheet(item: $expandedAttachment) { attachment in
            ExpandedImageView(attachment: attachment)
        }
    }

    @ViewBuilder
    private func singleImageView(_ attachment: ImageAttachment) -> some View {
        if let nsImage = NSImage(data: attachment.thumbnailData) {
            let aspectRatio = CGFloat(attachment.width) / max(CGFloat(attachment.height), 1)
            let displayWidth = min(maxSingleImageWidth, CGFloat(attachment.width))
            let displayHeight = displayWidth / aspectRatio

            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: displayWidth, maxHeight: displayHeight)
                .continuousCornerRadius(DS.Radii.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radii.medium, style: .continuous)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                )
                .onTapGesture { expandedAttachment = attachment }
                .cursor(.pointingHand)
        } else {
            imagePlaceholder
        }
    }

    private var gridImageView: some View {
        let columns = [
            GridItem(.fixed(gridThumbnailSize), spacing: gridSpacing),
            GridItem(.fixed(gridThumbnailSize), spacing: gridSpacing)
        ]
        return LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(attachments) { attachment in
                if let nsImage = NSImage(data: attachment.thumbnailData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: gridThumbnailSize, height: gridThumbnailSize)
                        .clipped()
                        .continuousCornerRadius(DS.Radii.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
                        )
                        .onTapGesture { expandedAttachment = attachment }
                        .cursor(.pointingHand)
                } else {
                    imagePlaceholder
                        .frame(width: gridThumbnailSize, height: gridThumbnailSize)
                }
            }
        }
    }

    private var imagePlaceholder: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .foregroundColor(.secondary)
            Text("Image unavailable")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(DS.Spacing.sm)
        .background(DS.Colors.surfaceElevated)
        .continuousCornerRadius(DS.Radii.medium)
    }
}

// MARK: - Expanded Image View

/// Full-size image viewer shown as a sheet when clicking a chat image.
/// Adapts to image aspect ratio and screen size (Quick Look style).
struct ExpandedImageView: View {
    let attachment: ImageAttachment
    @Environment(\.dismiss) private var dismiss

    /// Compute display size: fit image within 75% of screen, preserving aspect ratio
    private var displaySize: CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let maxWidth = screen.width * 0.75
        let maxHeight = screen.height * 0.75
        let headerHeight: CGFloat = 50

        let imgW = CGFloat(attachment.width)
        let imgH = CGFloat(attachment.height)
        let aspectRatio = imgW / max(imgH, 1)

        // Start with image's natural size
        var width = imgW
        var height = imgH

        // Scale down to fit screen constraints
        if width > maxWidth {
            width = maxWidth
            height = width / aspectRatio
        }
        if height > (maxHeight - headerHeight) {
            height = maxHeight - headerHeight
            width = height * aspectRatio
        }

        // Enforce minimum
        width = max(width, 320)
        height = max(height, 200)

        return CGSize(width: width, height: height + headerHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text(attachment.originalFilename ?? "Image")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("\(attachment.width) × \(attachment.height)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // Image area with dark background
            ZStack {
                Color.black.opacity(0.85)

                if let nsImage = NSImage(data: attachment.imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.trianglebadge.exclamationmark")
                            .font(.largeTitle)
                        Text("Unable to load image")
                            .font(.callout)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
    }
}

// MARK: - Cursor Helper

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - ImageAttachment Display Label Extension

extension ImageAttachment {
    /// Display label for the thumbnail — filename or generic label based on source
    var displayLabel: String {
        if let name = originalFilename, !name.isEmpty {
            return name
        }
        switch sourceType {
        case .clipboard:
            return "Pasted image"
        case .filePicker:
            return "Selected image"
        case .dragAndDrop:
            return "Dropped image"
        case .screenshot:
            return "Screenshot"
        }
    }
}
