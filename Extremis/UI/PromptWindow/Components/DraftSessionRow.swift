// MARK: - Draft Session Row
// Special row for displaying the current draft (unsaved) session in the sidebar

import SwiftUI

/// Row component for displaying a draft (unsaved) session in the sidebar
/// Visually distinct from saved sessions with italic title and "New" badge
struct DraftSessionRow: View {
    let isActive: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: {
            onSelect()
        }) {
            HStack(spacing: 0) {
                // Active indicator bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 4)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("New Session")
                                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                                .italic()
                                .foregroundColor(isActive ? .primary : .secondary)

                            // "New" badge - matches header badge style
                            Text("New")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(3)
                        }
                        .lineLimit(1)

                        Text("Just now")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.12) :
                          (isHovering ? Color.secondary.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Preview

struct DraftSessionRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 8) {
            // Active state
            DraftSessionRow(
                isActive: true,
                onSelect: {}
            )

            // Inactive state
            DraftSessionRow(
                isActive: false,
                onSelect: {}
            )
        }
        .padding()
        .frame(width: 180)
        .background(Color(NSColor.windowBackgroundColor))
        .previewLayout(.sizeThatFits)
    }
}
