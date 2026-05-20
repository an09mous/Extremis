// MARK: - Image Drop Zone View
// Overlay shown when user drags images over the chat input area

import SwiftUI

/// Semi-transparent overlay indicating a valid drop zone for images
struct ImageDropZoneView: View {
    var body: some View {
        ZStack {
            // Background overlay
            DS.Colors.surfacePrimary
                .opacity(0.85)

            // Drop indicator
            VStack(spacing: DS.Spacing.sm) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)

                Text("Drop images here")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(DS.Spacing.lg)
            .background(.ultraThinMaterial)
            .continuousCornerRadius(DS.Radii.large)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radii.large, style: .continuous)
                    .strokeBorder(DS.Colors.borderFocused, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
            )
        }
        .continuousCornerRadius(DS.Radii.pill)
    }
}
