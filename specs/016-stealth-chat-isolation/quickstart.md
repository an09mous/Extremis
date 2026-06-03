# Quickstart: Stealth Chat Isolation

**Branch**: `016-stealth-chat-isolation` | **Date**: 2026-06-03

## Overview

Add session-level stealth tagging so conversations created during stealth mode are hidden from the sidebar in normal mode. Minimal, additive changes to existing models and services.

## Implementation Order

### Step 1: Data Model (additive, no behavior change)
1. Add `isStealth: Bool` to `ChatSession` (init parameter, default `false`)
2. Add `isStealth: Bool` to `PersistedSession` (Codable, `decodeIfPresent` default `false`)
3. Add `isStealth: Bool` to `SessionIndexEntry` (Codable, `decodeIfPresent` default `false`)
4. Pass `isStealth` through in `PersistedSession.from(_:)` and `toSession()` conversions
5. Pass `isStealth` through in `JSONSessionStorage.saveSession()` index update

**Verification**: Build succeeds, all existing tests pass, no behavior change.

### Step 2: Session Tagging (creation-time tagging)
1. In `SessionManager.startNewSession()`, set `isStealth = StealthManager.shared.isStealthActive`
2. Ensure the tag flows through save → index → load round-trip

**Verification**: Create session in stealth → check persisted JSON has `isStealth: true`.

### Step 3: Sidebar Filtering (visibility)
1. In `SessionListView`, observe `StealthManager.shared.$isStealthActive`
2. Filter `sessions` array: if stealth off, exclude `isStealth == true` entries
3. Add stealth visual indicator (SF Symbol `lock.shield.fill`) on stealth sessions when stealth is active

**Verification**: Toggle stealth → stealth sessions appear/disappear in sidebar.

### Step 4: Active Session Auto-Switch (on stealth disable)
1. In `SessionManager`, subscribe to `StealthManager.shared.$isStealthActive`
2. When stealth goes `true → false` and current session is stealth: switch to most recent normal session or clear

**Verification**: View stealth session → disable stealth → active session switches.

### Step 5: Hotkey Guards (Quick Mode + Magic Mode)
1. In `AppDelegate.handleHotkeyActivation()`: add early return when stealth is active AND selection exists (Quick Mode path)
2. Verify existing Magic Mode guard at line 610 (already implemented)

**Verification**: In stealth, select text + Option+Space → no-op. Option+Tab → no-op (already works).

### Step 6: Unit Tests
1. Test `SessionIndexEntry` / `PersistedSession` backward compatibility (missing `isStealth` → `false`)
2. Test filtering logic (stealth on → all sessions, stealth off → only normal)
3. Test stealth tag immutability (tag set at creation, preserved through save/load)
4. Test auto-switch logic (stealth disable with active stealth session)

## Key Principles (per user request)

- **Simple & minimal**: Each step is a small, additive change
- **No regressions**: Backward-compatible Codable defaults, existing tests must pass at each step
- **Configurable**: Stealth tag driven by `StealthManager.isStealthActive` (already configurable)
- **High quality**: Follow existing patterns (filtering like `isArchived`, guards like Magic Mode)
- **Unit tested**: Every behavioral change has corresponding tests
