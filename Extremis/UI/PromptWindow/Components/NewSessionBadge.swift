// MARK: - New Session Badge
// Inline badge component indicating a new session has started

import SwiftUI

/// Non-intrusive badge displayed when a new session is created
/// Auto-dismisses after 2.5 seconds or on user interaction
struct NewSessionBadge: View {
    @Binding var isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                    Text("New Session")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DS.Colors.accentLight)
                .continuousCornerRadius(DS.Radii.medium)
                .fixedSize()
                .transition(reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .accessibilityLabel("New session started")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
    }
}

// MARK: - Preview

struct NewSessionBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Visible state
            NewSessionBadge(isVisible: .constant(true))

            // Hidden state (empty)
            NewSessionBadge(isVisible: .constant(false))
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
