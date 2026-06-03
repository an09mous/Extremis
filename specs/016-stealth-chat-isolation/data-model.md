# Data Model: Stealth Chat Isolation

**Branch**: `016-stealth-chat-isolation` | **Date**: 2026-06-03

## Entity Changes

### SessionIndexEntry (modified)

Lightweight index entry displayed in the sidebar. Add `isStealth` field.

```
SessionIndexEntry
├── id: UUID                    # (existing) Session identifier
├── title: String               # (existing) Display title
├── createdAt: Date             # (existing) Creation time
├── updatedAt: Date             # (existing) Last activity
├── messageCount: Int           # (existing) Message count
├── preview: String?            # (existing) First message preview
├── isArchived: Bool            # (existing) Soft-delete flag
└── isStealth: Bool             # (NEW) Whether created in stealth mode
                                # Default: false (backward compat)
                                # Immutable after creation
```

**Codable key**: `"isStealth"` — decoded via `decodeIfPresent` with `false` default for backward compatibility with existing index files.

### PersistedSession (modified)

Full session data stored on disk. Add `isStealth` field.

```
PersistedSession
├── id: UUID                    # (existing)
├── version: Int                # (existing) Schema version
├── messages: [PersistedMessage] # (existing)
├── initialRequest: String?     # (existing)
├── maxMessages: Int            # (existing)
├── createdAt: Date             # (existing)
├── updatedAt: Date             # (existing)
├── title: String?              # (existing)
├── isArchived: Bool            # (existing)
├── summary: SessionSummary?    # (existing)
└── isStealth: Bool             # (NEW) Whether created in stealth mode
                                # Default: false (backward compat)
                                # Immutable after creation
```

**Codable key**: `"isStealth"` — decoded via `decodeIfPresent` with `false` default.

### ChatSession (modified)

Live in-memory session. Add `isStealth` property set at creation time.

```
ChatSession
├── ... (all existing properties unchanged)
└── isStealth: Bool             # (NEW) Set at creation, never modified
                                # Default: false
                                # Read by SessionManager for tagging
```

**Not `@Published`** — this value never changes after init, so no observation needed.

## Filtering Logic

### SessionIndex.activeSessions (modified)

Current: `sessions.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }`

This computed property remains unchanged — it continues to return all non-archived sessions. Stealth filtering is applied at a higher layer (sidebar/SessionManager) because it depends on runtime state (`StealthManager.isStealthActive`).

### New Filtering (in SessionManager or SessionListView)

```
visibleSessions(isStealthActive: Bool) -> [SessionIndexEntry]:
  if isStealthActive:
    return activeSessions                    # Show all (stealth + normal)
  else:
    return activeSessions.filter { !$0.isStealth }  # Hide stealth sessions
```

## State Transitions

```
                    ┌─────────────────┐
                    │  Session Created │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ isStealth = X   │  (X = StealthManager.isStealthActive at creation)
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
     ┌────────▼────────┐          ┌────────▼────────┐
     │ isStealth=false │          │ isStealth=true  │
     │ (Normal Session) │          │ (Stealth Session)│
     └────────┬────────┘          └────────┬────────┘
              │                             │
              │ Always visible              │ Visible only when
              │                             │ StealthManager.isStealthActive
              │                             │
              ▼                             ▼
     ┌─────────────────┐          ┌─────────────────┐
     │ Can be deleted   │          │ Can be deleted   │
     │ in any mode      │          │ only in stealth  │
     └─────────────────┘          └─────────────────┘
```

## Backward Compatibility

- **Existing session files**: `isStealth` absent → decoded as `false` (normal session)
- **Existing index file**: `isStealth` absent per entry → decoded as `false`
- **No migration needed**: Codable `decodeIfPresent` handles missing field gracefully
- **Version field**: `PersistedSession.version` remains at 1 — this is an additive, non-breaking change
