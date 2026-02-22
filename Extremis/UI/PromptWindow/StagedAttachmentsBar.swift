// MARK: - Staged Attachments Bar
// Displays thumbnail previews of images queued for the next message

import SwiftUI
import AppKit

/// Horizontal scrollable bar showing staged image thumbnails with remove buttons
struct StagedAttachmentsBar: View {
    let attachments: [MessageAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(attachments) { attachment in
                    if case .image(let img) = attachment {
                        StagedImageThumbnail(
                            imageAttachment: img,
                            onRemove: { onRemove(img.id) }
                        )
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
        }
    }
}

/// Single staged image thumbnail with remove button
struct StagedImageThumbnail: View {
    let imageAttachment: ImageAttachment
    let onRemove: () -> Void

    @State private var isHovered = false

    private let thumbnailSize: CGFloat = 60

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Image thumbnail
            if let nsImage = imageFromBase64(imageAttachment.base64Data, mediaType: imageAttachment.mediaType) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .clipped()
                    .continuousCornerRadius(DS.Radii.small)
            } else {
                // Fallback placeholder
                RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                    .fill(DS.Colors.surfaceSecondary)
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }

            // Remove button (visible on hover)
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: 1)
        )
    }

    /// Decode base64 image data to NSImage
    private func imageFromBase64(_ base64: String, mediaType: ImageMediaType) -> NSImage? {
        guard !base64.isEmpty, let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}
