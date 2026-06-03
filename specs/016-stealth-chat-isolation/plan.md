# Implementation Plan: Stealth Chat Isolation

**Branch**: `016-stealth-chat-isolation` | **Date**: 2026-06-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/016-stealth-chat-isolation/spec.md`

## Summary

Add session-level stealth tagging so conversations created while stealth mode is active are automatically hidden from the sidebar in normal mode and revealed when stealth is re-enabled. Disable Quick Mode and Magic Mode hotkeys in stealth. The approach is purely additive — a boolean `isStealth` flag on sessions, UI-layer filtering, and early-return hotkey guards. No changes to storage structure, no new files for core logic, no breaking changes.

## Technical Context

**Language/Version**: Swift 5.9+ with Swift Concurrency
**Primary Dependencies**: SwiftUI, AppKit (NSPanel), Combine, Carbon (hotkeys)
**Storage**: JSON files in `~/Library/Application Support/Extremis/sessions/` (existing)
**Testing**: Standalone Swift test files compiled with `swiftc`, run via `scripts/run-tests.sh`
**Target Platform**: macOS 13.0+ (Ventura)
**Project Type**: Single macOS app (Swift Package Manager)
**Performance Goals**: Sidebar update within 200ms on stealth toggle, no visible flicker
**Constraints**: Additive changes only, backward-compatible Codable, zero regressions
**Scale/Scope**: ~8 files modified, ~3 new test files, ~200-300 lines of new code

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Modularity & Separation of Concerns | PASS | Stealth tag is a data property; filtering is in UI layer; hotkey guards are in existing handler methods. No new coupling between modules. |
| II. Code Quality & Best Practices | PASS | Follows existing patterns (Codable defaults like `isArchived`, early guards like Magic Mode). No magic numbers. |
| III. Extensibility & Testability | PASS | `isStealth` is a simple boolean — testable without mocks. Filtering logic is a pure function on arrays. |
| IV. User Experience Excellence | PASS | Sidebar updates reactively via Combine. Visual indicator on stealth sessions. Auto-switch prevents content exposure. |
| V. Documentation Synchronization | PASS | CLAUDE.md and README to be updated with stealth isolation behavior. |
| VI. Testing Discipline | PASS | Unit tests for model backward compat, filtering logic, tagging, and auto-switch. |
| VII. Regression Prevention | PASS | All changes are additive. Existing sessions default to `isStealth: false`. Existing tests must pass at each step. |

**Post-design re-check**: All gates still PASS. No constitution violations.

## Project Structure

### Documentation (this feature)

```text
specs/016-stealth-chat-isolation/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 research decisions
├── data-model.md        # Entity changes and state transitions
├── quickstart.md        # Step-by-step implementation guide
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (files modified/created)

```text
Extremis/
├── Core/
│   ├── Models/
│   │   ├── ChatSession.swift              # ADD isStealth property
│   │   └── Persistence/
│   │       ├── PersistedSession.swift      # ADD isStealth field (Codable)
│   │       └── SessionIndex.swift          # ADD isStealth to SessionIndexEntry
│   └── Services/
│       ├── SessionManager.swift            # Tag new sessions, auto-switch on stealth disable
│       └── JSONSessionStorage.swift        # Pass isStealth through index updates
├── UI/
│   └── PromptWindow/
│       └── SessionListView.swift           # Filter by stealth, add visual indicator
├── App/
│   └── AppDelegate.swift                   # Add stealth guard for Quick Mode path
└── Tests/
    └── Core/
        ├── StealthSessionTaggingTests.swift    # NEW: tagging and backward compat tests
        ├── StealthSessionFilteringTests.swift   # NEW: filtering logic tests
        └── StealthAutoSwitchTests.swift         # NEW: auto-switch behavior tests
```

**Structure Decision**: All changes go into existing files following the established project structure. Three new test files in `Tests/Core/` following the standalone `TestRunner` pattern.

## Design Details

### 1. Data Model Changes

**ChatSession** — Add `let isStealth: Bool` (immutable, set at init):
```swift
init(originalContext: Context? = nil, initialRequest: String? = nil, isStealth: Bool = false)
```

**PersistedSession** — Add `let isStealth: Bool` with backward-compatible decoding:
```swift
isStealth = try container.decodeIfPresent(Bool.self, forKey: .isStealth) ?? false
```

**SessionIndexEntry** — Same pattern as PersistedSession. The `isStealth` value is copied from the session when the index is updated in `JSONSessionStorage.saveSession()`.

### 2. Session Tagging

In `SessionManager.startNewSession()`:
```swift
let session = ChatSession(
    originalContext: context,
    initialRequest: initialRequest,
    isStealth: StealthManager.shared.isStealthActive  // NEW
)
```

The tag flows through: `ChatSession.isStealth` → `PersistedSession.from()` → `JSONSessionStorage.saveSession()` → `SessionIndexEntry.isStealth`.

### 3. Sidebar Filtering

In `SessionListView`, add `@ObservedObject` for `StealthManager.shared` and filter:
```swift
let visibleSessions = stealthManager.isStealthActive
    ? sessions                                    // Stealth: show all
    : sessions.filter { !$0.isStealth }           // Normal: hide stealth
```

Refresh triggers: existing `sessionListVersion` + new `onChange(of: stealthManager.isStealthActive)`.

### 4. Visual Indicator

In `SessionRowView`, when `entry.isStealth && stealthManager.isStealthActive`:
- Show SF Symbol `lock.shield.fill` (small, muted color) next to session title
- Use `DS.Colors.textSecondary` for the icon

### 5. Active Session Auto-Switch

In `SessionManager.init()`, subscribe to stealth state:
```swift
StealthManager.shared.$isStealthActive
    .dropFirst()  // Skip initial value
    .sink { [weak self] isActive in
        if !isActive { self?.handleStealthDeactivation() }
    }
```

`handleStealthDeactivation()`:
1. Check if `currentSession?.isStealth == true`
2. If yes: load most recent normal session from index, or set `currentSession = nil`
3. Increment `sessionListVersion` to trigger sidebar refresh

### 6. Hotkey Guards

**Quick Mode** (Option+Space with selection): In `AppDelegate.captureContextAndShowPrompt()`, the existing stealth check at line 673 already skips selection detection. Extend this to fully skip the Quick Mode path — when stealth is active AND selection was detected, treat as Chat Mode (no selection) instead.

**Magic Mode** (Option+Tab): Already guarded at `handleMagicModeActivation()` line 610 — no change needed.

### 7. Testing Strategy

All tests follow the existing standalone `TestRunner` pattern:

**StealthSessionTaggingTests.swift**:
- Test `ChatSession` creation with `isStealth: true` and `false`
- Test `PersistedSession` encoding/decoding with `isStealth`
- Test backward compat: decode JSON without `isStealth` field → defaults to `false`
- Test `SessionIndexEntry` backward compat same way
- Test round-trip: `ChatSession` → `PersistedSession` → `ChatSession` preserves `isStealth`

**StealthSessionFilteringTests.swift**:
- Test filter: stealth active → returns all sessions
- Test filter: stealth inactive → excludes stealth sessions
- Test filter: no stealth sessions → same result in both modes
- Test filter: all stealth sessions + stealth off → empty list
- Test filter: mixed sessions sorted correctly

**StealthAutoSwitchTests.swift**:
- Test: stealth disable with active stealth session → switches to most recent normal
- Test: stealth disable with active normal session → no change
- Test: stealth disable with no normal sessions → clears active session
- Test: stealth enable → no session change

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Existing session files break on load | Low | High | `decodeIfPresent` with default — tested explicitly |
| Sidebar flicker on stealth toggle | Low | Medium | Combine-driven reactive update, same as existing `sessionListVersion` |
| Active session not switched on stealth disable | Medium | High | Explicit Combine subscription + unit test |
| Quick Mode accidentally works in stealth | Low | Medium | Early guard + manual QA verification |
| Performance regression with filtering | Very Low | Low | Simple array filter on <100 sessions |

## Complexity Tracking

No constitution violations — no entries needed.
