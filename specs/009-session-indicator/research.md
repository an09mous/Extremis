# Research: New Session Indicator UI Best Practices

**Feature**: 009-session-indicator
**Date**: 2026-01-12
**Purpose**: Document research findings on UI patterns, animations, and best practices for inline status indicators in macOS apps.

---

## 1. Apple Human Interface Guidelines Analysis

### Status Indicators

From [Apple HIG - Status](https://developer.apple.com/design/human-interface-guidelines/status):

> Status indicators communicate information about system or app state. They should be **non-intrusive** and provide information that people can **understand at a glance**.

Key principles for our implementation:
- **Clarity**: The indicator should immediately communicate "this is a new session"
- **Non-intrusive**: Should not block user interaction or require acknowledgment
- **Contextual**: Placed near related UI elements (session controls in header)

### Notifications vs Status Indicators

From [Apple HIG - Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications):

> Notifications give people timely, high-value information they can understand at a glance.

Our "New Session" indicator is closer to a **status indicator** than a notification because:
- It's not time-critical external information
- It's state information about the current view
- It doesn't require user action

**Decision**: Use inline badge pattern (status indicator), not toast/banner pattern (notification).

---

## 2. SwiftUI Badge Patterns (2025)

### Native Badge Modifier

SwiftUI provides a `.badge()` modifier for standard use cases:

```swift
Text("Messages")
    .badge(3) // Shows count badge
```

However, for custom text badges in toolbar areas, a custom view is more appropriate.

### Custom Badge Components

From [Swift with Majid - Displaying Badges](https://swiftwithmajid.com/2021/11/10/displaying-badges-in-swiftui/):

```swift
// Common pattern for custom badges
HStack(spacing: 4) {
    Image(systemName: "sparkle")
        .font(.caption2)
    Text("New")
        .font(.caption2.weight(.medium))
}
.foregroundColor(.accentColor)
.padding(.horizontal, 8)
.padding(.vertical, 4)
.background(Color.accentColor.opacity(0.15))
.cornerRadius(6)
```

### Toolbar Integration

From [Design+Code - Toolbar](https://designcode.io/swiftui-handbook-toolbar/):

> Toolbar items should use **monochrome rendering** to reduce visual noise. Use tint only to convey meaning - a call to action or next step.

For our badge:
- Use accent color sparingly (background tint)
- Keep text readable with proper contrast
- Don't compete with action buttons

---

## 3. Animation Best Practices

### Spring Animations

From SwiftUI documentation and community standards:

```swift
// Natural, bouncy entry
.spring(response: 0.3, dampingFraction: 0.7)

// Smooth, quick exit
.easeOut(duration: 0.2)
```

### Transition Patterns

```swift
// Combined transition for badges
.transition(
    .asymmetric(
        insertion: .scale(scale: 0.9).combined(with: .opacity),
        removal: .opacity
    )
)
```

This pattern:
- Entry: Slight scale up + fade in (draws attention naturally)
- Exit: Simple fade out (unobtrusive)

### Auto-Dismiss Timing

Research on notification timing:
- **1-2 seconds**: Too fast, users miss it
- **2-3 seconds**: Optimal for acknowledgment without annoyance
- **4+ seconds**: Feels intrusive, users want to dismiss

**Decision**: 2.5 seconds auto-dismiss.

---

## 4. macOS 2025 Design Trends

### Liquid Glass Design Language

From [WWDC25 - Build SwiftUI with New Design](https://developer.apple.com/videos/play/wwdc2025/323/):

> The new design features translucent elements with "optical qualities of glass" that react to motion, content, and inputs.

For badges in toolbars:
- Consider subtle translucency
- Use adaptive text colors for legibility
- Maintain consistency with system appearance

### Glass Effect for Custom Views

From [Glassifying Toolbars in SwiftUI](https://swiftwithmajid.com/2025/07/01/glassifying-toolbars-in-swiftui/):

```swift
// Optional glass effect (macOS 26+)
.glassEffect(.capsule)
```

**Note**: Since we target macOS 13+, glass effect is optional/future enhancement.

---

## 5. Existing Codebase Analysis

### Current Header Layout

From `PromptContainerView` (lines 1074-1111):

```swift
HStack(spacing: 12) {
    // Left group
    Button(sidebar toggle) { ... }
    Button(new chat) { ... }

    Spacer()

    // Right group
    HStack(spacing: 6) {
        Circle() // provider status
        Text(providerName)
    }
}
```

### Design Constraints

1. **Spacing**: Header uses `spacing: 12` between major elements
2. **Font size**: Provider name uses `font(.system(size: 11))`
3. **Colors**: Secondary elements use `.secondary` or `.accentColor`
4. **Padding**: Header has `padding(.horizontal, 12)` and `padding(.vertical, 8)`

### Recommended Badge Placement

**Option A**: After "New Chat" button (left side)
```swift
Button(new chat) { ... }
NewSessionBadge(isVisible: $showIndicator)  // <-- Here
Spacer()
```

**Option B**: Before provider status (right side)
```swift
Spacer()
NewSessionBadge(isVisible: $showIndicator)  // <-- Here
HStack { provider status }
```

**Recommendation**: Option A - associates the indicator with session creation action.

---

## 6. Accessibility Considerations

### VoiceOver Support

The badge should announce itself when it appears:

```swift
.accessibilityLabel("New session started")
.accessibilityAddTraits(.isHeader)
```

### Motion Reduction

Respect user's motion preferences:

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

.transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
```

### Color Contrast

Ensure badge text meets WCAG guidelines:
- Accent color on accent-tinted background may have low contrast
- Alternative: Use `.primary` text color

---

## 7. Edge Case Handling

### Rapid Session Creation

Problem: User rapidly creates sessions → badges flicker

Solution: Debounce badge visibility:

```swift
private var badgeTimer: Timer?

func showBadge() {
    badgeTimer?.invalidate()
    withAnimation { showIndicator = true }
    badgeTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
        withAnimation { self.showIndicator = false }
    }
}
```

### Window Resize

Problem: Badge position shifts during window resize

Solution: Use fixed width or `fixedSize()` modifier:

```swift
NewSessionBadge()
    .fixedSize() // Prevents compression during resize
```

### Dark/Light Mode

SwiftUI handles this automatically with semantic colors:
- `.accentColor` adapts to system settings
- `.secondary` adapts to appearance
- Background opacity (0.15) works in both modes

---

## 8. Implementation Recommendations

### Final Component Design

```swift
import SwiftUI

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
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(6)
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
```

### State Management

```swift
// In PromptViewModel
@Published var showNewSessionIndicator: Bool = false
private var indicatorTimer: Timer?

func showNewSessionBadge() {
    indicatorTimer?.invalidate()

    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        showNewSessionIndicator = true
    }

    indicatorTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                self?.showNewSessionIndicator = false
            }
        }
    }
}

func hideNewSessionBadge() {
    indicatorTimer?.invalidate()
    indicatorTimer = nil

    withAnimation(.easeOut(duration: 0.2)) {
        showNewSessionIndicator = false
    }
}
```

---

## 9. Sources

1. [Apple HIG - Status](https://developer.apple.com/design/human-interface-guidelines/status)
2. [Apple HIG - Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications)
3. [Swift with Majid - Displaying Badges](https://swiftwithmajid.com/2021/11/10/displaying-badges-in-swiftui/)
4. [WWDC25 - Build SwiftUI with New Design](https://developer.apple.com/videos/play/wwdc2025/323/)
5. [Glassifying Toolbars in SwiftUI](https://swiftwithmajid.com/2025/07/01/glassifying-toolbars-in-swiftui/)
6. [Design+Code - SwiftUI Toolbar](https://designcode.io/swiftui-handbook-toolbar/)
7. [Understanding Toolbars in SwiftUI](https://tanaschita.com/swiftui-toolbars-guide/)
