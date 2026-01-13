# Implementation Plan: New Session Indicator

**Branch**: `009-session-indicator` | **Date**: 2026-01-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/009-session-indicator/spec.md`

## Summary

Add a non-intrusive inline text badge in the header area to indicate when a new session starts. The indicator will appear in both Quick Mode and Chat Mode when a new session is created, auto-dismiss after 2-3 seconds, and follow Apple Human Interface Guidelines for clean, minimal design.

## Technical Context

**Language/Version**: Swift 5.9+
**Primary Dependencies**: SwiftUI, AppKit (NSPanel), Combine
**Storage**: N/A (indicator is ephemeral UI state)
**Testing**: Standalone Swift test files (run via `./scripts/run-tests.sh`)
**Target Platform**: macOS 13.0+ (Ventura)
**Project Type**: Single macOS app
**Performance Goals**: Indicator appears within 100ms of session creation
**Constraints**: Non-blocking UI, no layout shifts, smooth animations
**Scale/Scope**: Affects PromptContainerView header area

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| Single responsibility | ✅ Pass | Indicator is a focused UI component with one job |
| Minimal dependencies | ✅ Pass | Uses only SwiftUI (already in codebase) |
| No breaking changes | ✅ Pass | Additive feature - does not modify existing behavior |
| Test coverage | ✅ Pass | ViewModel state can be unit tested |
| Apple HIG compliance | ✅ Pass | Inline badge follows HIG status indicator patterns |

## Project Structure

### Documentation (this feature)

```text
specs/009-session-indicator/
├── plan.md              # This file
├── research.md          # Phase 0 output - UI best practices research
├── data-model.md        # Phase 1 output - minimal (only state tracking)
├── quickstart.md        # Phase 1 output - implementation guide
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
Extremis/
├── UI/PromptWindow/
│   ├── PromptWindowController.swift  # Add isNewSession state tracking
│   └── Components/
│       └── NewSessionBadge.swift     # New: Inline badge component
└── Core/Services/
    └── SessionManager.swift          # Track session creation events
```

**Structure Decision**: Single project structure. The new session indicator requires:
1. A new SwiftUI component (`NewSessionBadge`) in the UI layer
2. State tracking in `PromptViewModel` (already exists)
3. Integration in the header of `PromptContainerView`

## Complexity Tracking

> No complexity violations - feature follows existing patterns

---

## Phase 0: Research

### UI Best Practices Research (2025)

Based on research from Apple HIG and SwiftUI community sources:

1. **Inline Status Indicators** (Apple HIG)
   - Status indicators should be non-intrusive and not block user interaction
   - Use clear, concise text labels when icons would be ambiguous
   - Indicators should adapt to light/dark mode automatically

2. **Badge Design Patterns**
   - Badges work well in toolbar/header areas
   - Capsule shapes with subtle backgrounds are modern and clean
   - Text + icon combinations improve comprehension

3. **Animation Best Practices**
   - Entry: Fade in with subtle scale (0.95 → 1.0)
   - Exit: Fade out after 2-3 seconds
   - Use `spring()` animations for natural feel
   - Never block or delay user interactions

4. **macOS 2025 Liquid Glass Design**
   - Translucent, glass-like effects are the new standard
   - Use `.glassEffect()` modifier where appropriate
   - Maintain legibility with adaptive text colors

### Existing Codebase Patterns

The header in `PromptContainerView` already has:
- Sidebar toggle button (left)
- New chat button (left)
- Provider status indicator (right) - uses `Circle()` + `Text`

The new session badge should integrate seamlessly:
- Position: Between new chat button and spacer (or right of provider status)
- Style: Match existing secondary text style
- Animation: Smooth entry/exit

### Research Sources

- [Apple Human Interface Guidelines - Status](https://developer.apple.com/design/human-interface-guidelines/status)
- [Apple HIG - Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications)
- [SwiftUI Badges - Swift with Majid](https://swiftwithmajid.com/2021/11/10/displaying-badges-in-swiftui/)
- [WWDC25 - Build SwiftUI with New Design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Glassifying Toolbars in SwiftUI](https://swiftwithmajid.com/2025/07/01/glassifying-toolbars-in-swiftui/)

---

## Phase 1: Design

### Data Model

Minimal state tracking required:

```swift
// In PromptViewModel or SessionManager
@Published var showNewSessionIndicator: Bool = false
```

The indicator is purely UI state - no persistence needed.

### Component Design: NewSessionBadge

```swift
struct NewSessionBadge: View {
    @Binding var isVisible: Bool

    var body: some View {
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
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}
```

### Integration Points

1. **Session Creation Events** (triggers badge visibility):
   - `PromptWindowController.startNewSession()` - explicit new session
   - `PromptViewModel.ensureSession()` - implicit new session creation
   - App launch with no previous session

2. **Badge Display Location**:
   - In `PromptContainerView` header, after new chat button
   - Animated entry, auto-dismiss after 2.5 seconds

3. **Badge Hide Conditions**:
   - Auto-dismiss timer (2.5 seconds)
   - User sends first message
   - User explicitly dismisses (optional)

### State Flow

```
Session Created → Set showNewSessionIndicator = true
                      ↓
              Show badge with animation
                      ↓
         ┌─── After 2.5s ───┐
         │                   │
         ↓                   ↓
  Set indicator = false   OR   User interaction
         │                   │
         └─────── Hide badge with animation ───────┘
```

### Edge Cases (from spec)

| Edge Case | Handling |
|-----------|----------|
| First launch, no sessions | Show indicator |
| Rapid session switching | Debounce - don't flicker |
| Session creation fails | Don't show indicator (show error instead) |
| Auto-dismiss timing | 2.5 seconds or on first user interaction |

### Contracts

**NewSessionBadge Component Contract**:
- Input: `@Binding var isVisible: Bool`
- Output: Animated badge or empty view
- Side effects: None

**Session Indicator State Contract** (in PromptViewModel):
- `showNewSessionIndicator: Bool` - published state
- `showNewSessionBadge()` - sets true, starts timer
- `hideNewSessionBadge()` - sets false

---

## Implementation Approach

### Option A: ViewModel State (Recommended)

Track indicator state in `PromptViewModel`:
- Simple, centralized state management
- Easy to test
- Natural integration with existing patterns

### Option B: SessionManager Events

Use Combine publishers from SessionManager:
- More decoupled
- Requires observer setup
- Better for multi-window scenarios (not needed currently)

**Decision**: Option A - keeps complexity low and matches existing patterns.

### Animation Details

```swift
// Entry animation
withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
    showNewSessionIndicator = true
}

// Exit animation (after delay)
DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
    withAnimation(.easeOut(duration: 0.2)) {
        showNewSessionIndicator = false
    }
}
```

### Testing Strategy

1. **Unit Tests**: Test `showNewSessionBadge()` and `hideNewSessionBadge()` methods
2. **Manual QA**:
   - Quick Mode: Select text → invoke → verify badge appears
   - Chat Mode: No selection → invoke → verify badge appears
   - Session switch: Select existing session → verify NO badge
   - New Session button: Click → verify badge appears

---

## Non-Goals

- No toast/snackbar style (per spec - inline badge only)
- No animation beyond fade/scale
- No user preference to disable indicator
- No indicator persistence across app restart

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Layout shift when badge appears | Low | Low | Use fixed space or overlay |
| Animation jank | Low | Medium | Use spring animations, test on real hardware |
| Indicator doesn't auto-dismiss | Low | Low | Defensive timer cancellation |
| Regressions in session flow | Low | High | Add unit tests, manual QA checklist |

---

## Definition of Done

- [ ] NewSessionBadge component created
- [ ] Indicator appears for new sessions in Quick Mode
- [ ] Indicator appears for new sessions in Chat Mode
- [ ] Indicator does NOT appear when loading existing session
- [ ] Auto-dismiss after ~2.5 seconds
- [ ] Smooth entry/exit animations
- [ ] No layout shifts
- [ ] All existing tests pass
- [ ] Manual QA checklist completed
