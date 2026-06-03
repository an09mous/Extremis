# Research: Stealth Chat Isolation

**Branch**: `016-stealth-chat-isolation` | **Date**: 2026-06-03

## Decision 1: Isolation Granularity — Session-Level vs Message-Level

**Decision**: Session-level isolation (entire sessions tagged as stealth or normal).

**Rationale**: Message-level isolation creates LLM conversation coherence problems — the assistant may reference stealth content in a normal-mode response, leaking context. Session-level follows proven patterns (WhatsApp Chat Lock, Telegram Secret Chats) and is simpler to implement.

**Alternatives considered**:
- Message-level tagging (Instagram Vanish Mode pattern) — rejected due to LLM context leak risk and rendering complexity
- Hybrid (session with message overrides) — over-engineered for the use case

## Decision 2: Storage Approach — UI Filtering vs Separate Storage

**Decision**: UI-layer filtering with shared storage. The `isStealth` flag is added to `SessionIndexEntry` and `PersistedSession`. Filtering happens in the sidebar view, not at the storage layer.

**Rationale**: Shared storage is simpler — no need for separate directories, backup strategies, or migration logic. The threat model is screen-sharing observers, not filesystem attackers. Existing `SessionIndex.activeSessions` computed property already demonstrates the filtering pattern (filters `isArchived`).

**Alternatives considered**:
- Separate storage directory for stealth sessions — more complex, minimal security benefit for the use case
- Encrypted stealth storage — over-engineered; the user's filesystem is already trusted

## Decision 3: Stealth Tag Mutability

**Decision**: Immutable after session creation. A session created in stealth stays stealth forever.

**Rationale**: Prevents accidental exposure through tag toggling. Matches the mental model — "this conversation happened during stealth." Simplifies UI (no toggle controls needed).

**Alternatives considered**:
- User-togglable tag — risk of accidental exposure, more UI complexity
- Auto-convert on mode switch — confusing, violates user expectations

## Decision 4: Quick Mode / Magic Mode in Stealth

**Decision**: Disable both (no-op) when stealth is active.

**Rationale**: Quick Mode inserts text into the active app and Magic Mode copies to clipboard — both leave traces outside Extremis. Chat Mode remains functional (creates stealth sessions). Existing pattern: Magic Mode already has a stealth guard at `AppDelegate.handleMagicModeActivation()` line 610.

**Alternatives considered**:
- Allow but don't persist — traces still left in clipboard/target app
- Allow with warning — adds UI complexity for minimal value

## Decision 5: Active Session Behavior on Stealth Toggle

**Decision**:
- **On stealth enable**: No change to active session (keep current normal session active)
- **On stealth disable**: Auto-switch away from stealth session to most recent normal session (or empty state)

**Rationale**: Enabling stealth is a background action — user shouldn't lose context. Disabling stealth must hide stealth content immediately — can't leave it on screen.

## Decision 6: Backward Compatibility for Existing Sessions

**Decision**: Existing sessions (created before this feature) default to `isStealth = false`. The `SessionIndexEntry` and `PersistedSession` decoders use `decodeIfPresent` with a `false` default.

**Rationale**: All pre-existing sessions were created in normal mode. No migration needed — just a Codable default.

## Key Codebase Findings

### Files to Modify

| File | Change |
|------|--------|
| `Core/Models/Persistence/SessionIndex.swift` | Add `isStealth: Bool` to `SessionIndexEntry` |
| `Core/Models/Persistence/PersistedSession.swift` | Add `isStealth: Bool` to `PersistedSession` |
| `Core/Models/ChatSession.swift` | Add `isStealth: Bool` property (set at creation) |
| `Core/Services/SessionManager.swift` | Tag new sessions, filter on stealth toggle, auto-switch on disable |
| `Core/Services/JSONSessionStorage.swift` | Pass through `isStealth` in index updates |
| `UI/PromptWindow/SessionListView.swift` | Filter sessions by stealth state, add visual indicator |
| `App/AppDelegate.swift` | Add stealth guard to `handleHotkeyActivation()` for Quick Mode path |

### Existing Patterns to Follow

1. **Filtering**: `SessionIndex.activeSessions` filters `isArchived` — extend with `isStealth` filtering
2. **Stealth guards**: `handleMagicModeActivation()` line 610 uses early `guard` — replicate for Quick Mode
3. **Reactive observation**: `VoiceInputManager` subscribes to `StealthManager.$isStealthActive` via Combine — SessionManager should do the same for auto-switch
4. **Codable backward compat**: `SessionIndexEntry` already handles schema evolution with `decodeIfPresent` — follow same pattern
