# Data Model: New Session Indicator

**Feature**: 009-session-indicator
**Date**: 2026-01-12
**Purpose**: Define the minimal data model and state management for the new session indicator.

---

## Overview

The new session indicator is a **purely ephemeral UI state** feature. It requires no persistent storage - only in-memory state tracking to control badge visibility.

---

## State Model

### PromptViewModel Extensions

```swift
// Add to existing PromptViewModel class
@MainActor
final class PromptViewModel: ObservableObject {
    // ... existing properties ...

    // MARK: - New Session Indicator State

    /// Controls visibility of the "New Session" badge in the header
    @Published var showNewSessionIndicator: Bool = false

    /// Timer for auto-dismissing the indicator
    private var indicatorDismissTimer: Timer?
}
```

### State Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    Session Indicator State                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Initial State                                                  │
│   ┌──────────────────────┐                                       │
│   │ showNewSessionIndicator = false                              │
│   │ indicatorDismissTimer = nil                                  │
│   └──────────────────────┘                                       │
│              │                                                   │
│              │ New session created                               │
│              ▼                                                   │
│   ┌──────────────────────┐                                       │
│   │ showNewSessionIndicator = true                               │
│   │ indicatorDismissTimer = 2.5s timer                           │
│   └──────────────────────┘                                       │
│              │                                                   │
│              │ Timer fires OR user interaction                   │
│              ▼                                                   │
│   ┌──────────────────────┐                                       │
│   │ showNewSessionIndicator = false                              │
│   │ indicatorDismissTimer = nil                                  │
│   └──────────────────────┘                                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## No Persistence Required

This feature intentionally **does not persist** the indicator state because:

1. **Ephemeral by design**: The indicator only matters during the moment of session creation
2. **State resets on app launch**: New launch = fresh state
3. **No user preference**: No setting to enable/disable (per spec non-goals)

---

## Integration Points

### Trigger Conditions

The indicator should be shown when:

| Trigger | Location | Method |
|---------|----------|--------|
| Explicit new session | `PromptWindowController.startNewSession()` | Call `showNewSessionBadge()` after session creation |
| Implicit new session | `PromptViewModel.ensureSession()` | Call `showNewSessionBadge()` when `session == nil` and we create one |
| First launch | App launch path | If no session to restore, indicator shown |

### Hide Conditions

The indicator should be hidden when:

| Trigger | Location | Method |
|---------|----------|--------|
| Auto-dismiss timer | Timer callback | `hideNewSessionBadge()` |
| First message sent | `PromptViewModel.generate()` | `hideNewSessionBadge()` before generation |
| Session loaded | `PromptViewModel.setRestoredSession()` | Don't show indicator (session existed) |
| User switches session | `selectSession()` | Don't show indicator (session existed) |

---

## SwiftUI Binding

### In PromptContainerView

```swift
struct PromptContainerView: View {
    @ObservedObject var viewModel: PromptViewModel
    // ...

    var body: some View {
        HStack(spacing: 0) {
            // ... sidebar ...

            VStack(spacing: 0) {
                // Header with new session indicator
                HeaderView(
                    showSidebar: $showSidebar,
                    showNewSessionIndicator: $viewModel.showNewSessionIndicator,
                    // ...
                )

                // ... rest of content ...
            }
        }
    }
}
```

### In NewSessionBadge

```swift
struct NewSessionBadge: View {
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            // Badge content
        }
    }
}
```

---

## Thread Safety

All state mutations occur on `@MainActor`:

- `PromptViewModel` is `@MainActor` isolated
- Timer callbacks use `DispatchQueue.main.async`
- SwiftUI bindings are main-thread safe

---

## Memory Management

### Timer Cleanup

```swift
// In PromptViewModel
deinit {
    indicatorDismissTimer?.invalidate()
    // ... other cleanup ...
}

func reset() {
    // Cancel timer when resetting state
    indicatorDismissTimer?.invalidate()
    indicatorDismissTimer = nil
    showNewSessionIndicator = false
    // ... other resets ...
}
```

### No Retain Cycles

Timer callbacks use `[weak self]`:

```swift
indicatorDismissTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
    DispatchQueue.main.async {
        self?.hideNewSessionBadge()
    }
}
```

---

## Testing Considerations

### Unit Test Points

1. **Initial state**: `showNewSessionIndicator` starts as `false`
2. **Show trigger**: After `showNewSessionBadge()`, state is `true`
3. **Hide trigger**: After `hideNewSessionBadge()`, state is `false`
4. **Timer behavior**: State becomes `false` after delay (test with expectation)
5. **Debounce**: Rapid calls don't break state

### Mock Timer for Testing

```swift
// Protocol for testability
protocol TimerProvider {
    func schedule(after: TimeInterval, action: @escaping () -> Void)
    func cancel()
}

// Production implementation
class RealTimerProvider: TimerProvider {
    private var timer: Timer?

    func schedule(after interval: TimeInterval, action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            action()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
```

---

## Summary

| Aspect | Decision |
|--------|----------|
| Persistence | None required |
| State location | `PromptViewModel.showNewSessionIndicator` |
| State type | `@Published Bool` |
| Timer | `Timer` with 2.5s delay |
| Thread safety | `@MainActor` isolation |
| Memory | Weak self in timer callback |
