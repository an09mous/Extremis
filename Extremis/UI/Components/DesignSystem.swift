// MARK: - Design System
// Centralized design tokens for the Extremis visual theme

import SwiftUI

// MARK: - Design Tokens

enum DS {

    // MARK: - Colors

    enum Colors {
        // Surfaces — layered hierarchy for visual depth
        static let windowBackground = Color(NSColor.windowBackgroundColor)
        static let surfacePrimary = Color(NSColor.controlBackgroundColor)
        static let surfaceSecondary = Color(nsColor: .init(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.05)
                : NSColor.black.withAlphaComponent(0.04)
        }))
        static let surfaceElevated = Color(NSColor.textBackgroundColor)

        // Text
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.secondary.opacity(0.6)

        // Borders — stronger in light mode for clear separation
        static let borderSubtle = Color(nsColor: .init(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.black.withAlphaComponent(0.12)
        }))
        static let borderMedium = Color(nsColor: .init(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.18)
        }))
        static let borderFocused = Color.accentColor.opacity(0.6)

        // Accents
        static let accentSubtle = Color.accentColor.opacity(0.12)
        static let accentLight = Color.accentColor.opacity(0.18)

        // Status — stronger tints in light mode
        static let successSubtle = Color(nsColor: .init(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.systemGreen.withAlphaComponent(0.08)
                : NSColor.systemGreen.withAlphaComponent(0.12)
        }))
        static let successBorder = Color.green.opacity(0.3)
        static let errorSubtle = Color(nsColor: .init(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.systemRed.withAlphaComponent(0.1)
                : NSColor.systemRed.withAlphaComponent(0.14)
        }))
        static let errorBorder = Color.red.opacity(0.3)
        static let warningSubtle = Color(nsColor: .init(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.systemOrange.withAlphaComponent(0.08)
                : NSColor.systemOrange.withAlphaComponent(0.12)
        }))
        static let warningBorder = Color.orange.opacity(0.3)
        static let infoSubtle = Color(nsColor: .init(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.systemBlue.withAlphaComponent(0.08)
                : NSColor.systemBlue.withAlphaComponent(0.12)
        }))
        static let infoBorder = Color.blue.opacity(0.3)

        // Hover — visible in both modes
        static let hoverSubtle = Color(nsColor: .init(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.black.withAlphaComponent(0.06)
        }))

        // Chat bubbles — user gets prominent accent tint, assistant has no bubble
        static let userBubble = Color.accentColor.opacity(0.15)
        static let userBubbleBorder = Color.accentColor.opacity(0.3)
        static let assistantBubble = Color.clear
        static let assistantBubbleBorder = Color.clear
    }

    // MARK: - Corner Radii (all use .continuous style)

    enum Radii {
        static let small: CGFloat = 4
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xLarge: CGFloat = 16
        static let pill: CGFloat = 20
    }

    // MARK: - Spacing (4pt grid)

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: - Shadows

    enum Shadows {
        static let subtle = ShadowStyle(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        static let medium = ShadowStyle(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
        static let elevated = ShadowStyle(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
    }

    // MARK: - Animation

    enum Animation {
        static let hoverTransition = SwiftUI.Animation.easeOut(duration: 0.12)
        static let expandCollapse = SwiftUI.Animation.easeInOut(duration: 0.15)
    }
}

// MARK: - Shadow Helper

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extensions

extension View {
    /// Apply a continuous corner radius (smoother squircle shape)
    func continuousCornerRadius(_ radius: CGFloat) -> some View {
        self.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// Apply a shadow from the design system
    func dsShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
