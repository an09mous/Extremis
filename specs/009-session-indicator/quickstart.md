# Quickstart: New Session Indicator Implementation

**Feature**: 009-session-indicator
**Date**: 2026-01-12
**Purpose**: Step-by-step implementation guide for the new session indicator feature.

---

## Prerequisites

Before starting implementation:
- [ ] Feature branch created: `git checkout -b 009-session-indicator`
- [ ] Build passes: `cd Extremis && swift build`
- [ ] Tests pass: `./scripts/run-tests.sh`

---

## Implementation Steps

### Step 1: Create NewSessionBadge Component

**File**: `Extremis/UI/PromptWindow/Components/NewSessionBadge.swift` (new file)

```swift
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
```

### Step 2: Add State to PromptViewModel

**File**: `Extremis/UI/PromptWindow/PromptWindowController.swift`

Add these properties and methods to `PromptViewModel`:

```swift
// MARK: - New Session Indicator State

/// Controls visibility of the "New Session" badge in the header
@Published var showNewSessionIndicator: Bool = false

/// Timer for auto-dismissing the indicator
private var indicatorDismissTimer: Timer?

/// Show the new session badge with auto-dismiss
func showNewSessionBadge() {
    // Cancel any existing timer
    indicatorDismissTimer?.invalidate()

    // Show badge with animation
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        showNewSessionIndicator = true
    }

    // Schedule auto-dismiss after 2.5 seconds
    indicatorDismissTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
        DispatchQueue.main.async {
            self?.hideNewSessionBadge()
        }
    }
}

/// Hide the new session badge
func hideNewSessionBadge() {
    indicatorDismissTimer?.invalidate()
    indicatorDismissTimer = nil

    withAnimation(.easeOut(duration: 0.2)) {
        showNewSessionIndicator = false
    }
}
```

Update `reset()` method to clean up timer:

```swift
func reset() {
    // Cancel indicator timer
    indicatorDismissTimer?.invalidate()
    indicatorDismissTimer = nil
    showNewSessionIndicator = false

    // ... existing reset code ...
}
```

Update `deinit` to clean up timer:

```swift
deinit {
    generationTask?.cancel()
    providerCancellable?.cancel()
    indicatorDismissTimer?.invalidate()  // Add this line
}
```

### Step 3: Trigger Badge on Session Creation

**In `PromptViewModel.ensureSession()`** - show badge when creating new session:

```swift
private func ensureSession(context: Context?, instruction: String?) {
    if session == nil {
        // Create a new session
        let sess = ChatSession(originalContext: context, initialRequest: instruction)
        session = sess
        sessionId = UUID()

        // Register with SessionManager immediately
        SessionManager.shared.setCurrentSession(sess, id: sessionId)
        print("📋 PromptViewModel: Created new session \(sessionId!)")

        // Show new session indicator
        showNewSessionBadge()  // Add this line
    }
}
```

**In `PromptWindowController.startNewSession()`** - show badge on explicit new session:

```swift
func startNewSession() async {
    // ... existing code ...

    await SessionManager.shared.startNewSession()

    // Show indicator for the new session
    viewModel.showNewSessionBadge()  // Add this line
}
```

### Step 4: Hide Badge on User Interaction

**In `PromptViewModel.generate()`** - hide badge when user sends message:

```swift
func generate(with context: Context) {
    // Hide new session indicator on first interaction
    hideNewSessionBadge()  // Add near the top

    // ... existing code ...
}
```

**In `PromptViewModel.sendChatMessage()`** - hide badge on chat message:

```swift
func sendChatMessage() {
    // Hide new session indicator on interaction
    hideNewSessionBadge()  // Add near the top

    // ... existing code ...
}
```

### Step 5: Integrate Badge in Header

**File**: `Extremis/UI/PromptWindow/PromptWindowController.swift`

In `PromptContainerView`, update the header section:

```swift
// Header - ChatGPT style minimal icons
HStack(spacing: 12) {
    // Sidebar toggle
    Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showSidebar.toggle() } }) {
        Image(systemName: "sidebar.left")
            .font(.system(size: 16))
            .foregroundColor(.secondary)
    }
    .buttonStyle(.plain)
    .help(showSidebar ? "Hide sidebar" : "Show sidebar")

    // New chat button
    Button(action: {
        if !sessionManager.isAnySessionGenerating {
            onNewSession()
        }
    }) {
        Image(systemName: sessionManager.isAnySessionGenerating ? "square.and.pencil.circle" : "square.and.pencil")
            .font(.system(size: 16))
            .foregroundColor(sessionManager.isAnySessionGenerating ? .secondary.opacity(0.4) : .secondary)
    }
    .buttonStyle(.plain)
    .help(sessionManager.isAnySessionGenerating ? "Generation in progress - wait or cancel to start new session" : "New session")

    // NEW: Session indicator badge
    NewSessionBadge(isVisible: $viewModel.showNewSessionIndicator)

    Spacer()

    // Provider status - compact
    HStack(spacing: 6) {
        Circle()
            .fill(viewModel.providerConfigured ? Color.green : Color.orange)
            .frame(width: 6, height: 6)
        Text(viewModel.providerName)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }
}
.padding(.horizontal, 12)
.padding(.vertical, 8)
.background(Color(NSColor.windowBackgroundColor))
```

### Step 6: Don't Show Badge for Restored Sessions

**In `PromptViewModel.setRestoredSession()`** - explicitly don't show badge:

```swift
func setRestoredSession(_ sess: ChatSession, id: UUID?) {
    // Hide any visible indicator (this is an existing session, not new)
    hideNewSessionBadge()

    session = sess
    sessionId = id

    // ... rest of existing code ...
}
```

---

## Verification Checklist

### Build & Test

```bash
cd Extremis

# Build
swift build

# Run all tests
./scripts/run-tests.sh
```

### Manual QA

1. **Quick Mode - New Session**
   - [ ] Select text in any app
   - [ ] Press Option+Space
   - [ ] Submit instruction
   - [ ] Verify "New Session" badge appears in header
   - [ ] Verify badge auto-dismisses after ~2.5 seconds

2. **Chat Mode - New Session**
   - [ ] Press Option+Space (no selection)
   - [ ] Verify badge appears immediately
   - [ ] Verify badge auto-dismisses

3. **Explicit New Session**
   - [ ] Have an existing session with messages
   - [ ] Click "New Session" button (pencil icon)
   - [ ] Verify badge appears

4. **Load Existing Session**
   - [ ] Have multiple sessions in sidebar
   - [ ] Click on an existing session
   - [ ] Verify NO badge appears (session was not new)

5. **Badge Dismissal on Interaction**
   - [ ] Start new session (badge visible)
   - [ ] Send a message before 2.5s
   - [ ] Verify badge disappears immediately

6. **Accessibility**
   - [ ] Enable VoiceOver
   - [ ] Create new session
   - [ ] Verify VoiceOver announces "New session started"

7. **Reduce Motion**
   - [ ] Enable "Reduce Motion" in System Settings > Accessibility
   - [ ] Create new session
   - [ ] Verify badge appears/disappears with simple fade (no scale)

---

## Troubleshooting

### Badge doesn't appear

1. Check `showNewSessionBadge()` is called after session creation
2. Verify `@Published` property is observed correctly
3. Check animation isn't being cancelled

### Badge doesn't auto-dismiss

1. Check timer is scheduled on main thread
2. Verify `[weak self]` doesn't cause early deallocation
3. Check timer isn't invalidated prematurely

### Layout shift when badge appears

1. Use `.fixedSize()` on badge
2. Consider using overlay instead of HStack

### Animation jank

1. Reduce animation complexity
2. Test on real hardware (not simulator)
3. Check for conflicting animations

---

## Files Modified/Created

| File | Change |
|------|--------|
| `Extremis/UI/PromptWindow/Components/NewSessionBadge.swift` | **NEW** - Badge component |
| `Extremis/UI/PromptWindow/PromptWindowController.swift` | Add state, methods, integrate badge |

---

## Next Steps

After implementation:

1. Run `/speckit.tasks` to generate detailed task breakdown
2. Commit changes to feature branch
3. Create PR with manual QA results
