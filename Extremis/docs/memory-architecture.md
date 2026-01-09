# Memory Architecture

Extremis implements a long-term memory system using **hierarchical summarization** to maintain conversation context efficiently across extended sessions. This document describes the memory model, summarization triggers, and context management strategy.

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Chat Session                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  Messages Array (ALL messages preserved)                             │    │
│  │  [M1] [M2] [M3] ... [M10] │ [M11] [M12] ... [M20] │ [M21] ... [M30]  │    │
│  │       ▲                    │        ▲              │                 │    │
│  │       │                    │        │              │                 │    │
│  │  Summarized (10)          │  Summarized (10)      │  Recent (10)    │    │
│  │       │                    │        │              │                 │    │
│  │       └────────────────────┴────────┘              │                 │    │
│  │                  │                                 │                 │    │
│  │                  ▼                                 │                 │    │
│  │         ┌──────────────────┐                       │                 │    │
│  │         │  SessionSummary  │                       │                 │    │
│  │         │  covers: 20 msgs │───────────────────────┘                 │    │
│  │         └──────────────────┘                                         │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  LLM Context = [Summary Message] + [Recent 10 Messages]                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Concepts

### 1. Full Message Preservation
All messages are **always preserved** in the session. The summary is an optimization for LLM context windows, not a replacement for message storage.

### 2. Sliding Window with Summary
When sending messages to the LLM:
- If no summary exists: all messages (up to `maxMessages` limit)
- If summary exists: summary as system message + recent unsummarized messages

### 3. Hierarchical Summarization
When regenerating a summary, we use **previous summary + new messages** instead of re-processing all raw messages. This saves tokens and scales to very long conversations.

---

## Data Model

### SessionSummary

| Field | Type | Description |
|-------|------|-------------|
| `content` | String | The summary text |
| `coversMessageCount` | Int | Number of messages summarized |
| `createdAt` | Date | When summary was generated |
| `modelUsed` | String? | Which LLM generated it |

**Computed Properties**:
- `isValid`: True if `coversMessageCount > 0` and `content` is not empty
- `needsRegeneration(totalMessages:threshold:)`: Determines if summary needs updating

### ChatSession Memory Fields

| Field | Type | Description |
|-------|------|-------------|
| `messages` | [ChatMessage] | ALL messages (never truncated) |
| `summary` | SessionSummary? | Current summary (if any) |
| `summaryCoversCount` | Int | Messages covered by summary |

**Key Methods**:
- `messagesForLLM()`: Returns optimized context for LLM API calls
- `updateSummary(_:coversCount:)`: Called after summarization completes

---

## Configuration

| Parameter | Value | Description |
|-----------|-------|-------------|
| `messageThreshold` | 20 | Summarize when message count reaches this |
| `tokenThreshold` | 8000 | Summarize when estimated tokens reach this |
| `recentMessagesToKeep` | 10 | Always keep this many recent messages unsummarized |
| `maxSummaryLength` | 2000 | Maximum characters for generated summary |

**Token Estimation**: 1 token ≈ 4 characters

---

## Summarization Triggers

### First-Time Summarization
Triggered when session has **no existing summary** AND meets threshold:

- **Condition**: (messageCount >= 20) OR (estimatedTokens >= 8000)
- **Action**: Summarize oldest messages, keep recent 10 as-is
- **Result**: summary covers messages that were summarized

### Summary Regeneration
Triggered when session **has an existing summary** AND enough new messages accumulated:

**Formula**: `needsRegeneration = (totalMessages - (coversMessageCount + recentToKeep)) >= threshold`

**Example at 30 messages with summary covering 10**:
- coveredWhenCreated = 10 + 10 = 20
- newMessages = 30 - 20 = 10
- 10 >= 10 → regeneration needed!

---

## Hierarchical Summarization Flow

### Example: Conversation Growth

#### State 1: 20 Messages (First Summarization)
- **Trigger**: 20 messages >= threshold (20)
- **Action**: First-time summarization of oldest 10 messages
- **Output**: Summary S1 (covers 10 messages)
- **LLM Context after**: [S1] + [M11..M20] (summary + 10 recent)

#### State 2: 30 Messages (Regeneration)
- **Existing**: S1 covers 10 messages
- **Check**: coveredWhenCreated = 10 + 10 = 20, newMessages = 30 - 20 = 10 → regenerate!
- **Action**: Hierarchical summarization (S1 + messages 11-20)
- **Output**: Summary S2 (covers 20 messages)
- **LLM Context after**: [S2] + [M21..M30]

#### State 3: 40 Messages (Another Regeneration)
- **Existing**: S2 covers 20 messages
- **Check**: coveredWhenCreated = 20 + 10 = 30, newMessages = 40 - 30 = 10 → regenerate!
- **Action**: Hierarchical summarization (S2 + messages 21-30)
- **Output**: Summary S3 (covers 30 messages)
- **LLM Context after**: [S3] + [M31..M40]

### Visual Timeline

```
Messages:    1    10   20   30   40   50   60
             │    │    │    │    │    │    │
             ▼    ▼    ▼    ▼    ▼    ▼    ▼
             ┌────┬────┬────┬────┬────┬────┐
             │ M1-M10  │ M11-M20 │ M21-M30 │ M31-M40 │ M41-M50 │ M51-M60 │
             └────┴────┴────┴────┴────┴────┘
                  │         │         │         │
At 20 msgs:  [summarize]   [recent]
             S1 covers 10   keep 10

At 30 msgs:  [─── S1 ───]  [summarize] [recent]
             prev summary   new 10     keep 10
             S2 covers 20

At 40 msgs:  [───── S2 ─────]  [summarize] [recent]
             prev summary       new 10     keep 10
             S3 covers 30

At 50 msgs:  [─────── S3 ───────]  [summarize] [recent]
             S4 covers 40

...and so on
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              User Interaction                            │
│                                    │                                     │
│                                    ▼                                     │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                         ChatSession                               │   │
│  │  messages: [M1, M2, ..., M30]                                    │   │
│  │  summary: SessionSummary?                                        │   │
│  │  summaryCoversCount: Int                                         │   │
│  └────────────────────────────┬─────────────────────────────────────┘   │
│                               │                                          │
│              ┌────────────────┴────────────────┐                        │
│              │                                 │                        │
│              ▼                                 ▼                        │
│  ┌───────────────────────┐       ┌───────────────────────────────┐     │
│  │  messagesForLLM()     │       │      SessionManager           │     │
│  │  Returns optimized    │       │  - Observes message changes   │     │
│  │  context for API      │       │  - Debounced save (2s)        │     │
│  └───────────────────────┘       │  - Triggers summarization     │     │
│                                  └───────────────┬───────────────┘     │
│                                                  │                      │
│                                                  ▼                      │
│                                  ┌───────────────────────────────┐     │
│                                  │    SummarizationManager       │     │
│                                  │  - needsSummarization()       │     │
│                                  │  - summarize() (hierarchical) │     │
│                                  │  - summarizeIfNeeded()        │     │
│                                  └───────────────┬───────────────┘     │
│                                                  │                      │
│                                                  ▼                      │
│                                  ┌───────────────────────────────┐     │
│                                  │       LLM Provider            │     │
│                                  └───────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Integration Flow

1. **Message Added** → ChatSession messages updated
2. **SessionManager Observes** → Schedules debounced save (2s)
3. **Save Triggers** → SummarizationManager checks if summarization needed
4. **If Threshold Met**:
   - First-time: Summarize oldest messages
   - Regeneration: Previous summary + new messages (hierarchical)
5. **Summary Generated** → Synced back to live ChatSession
6. **Next LLM Call** → messagesForLLM() returns summary + recent messages

---

## Trade-offs

### Hierarchical vs. Full Re-summarization

| Approach | Pros | Cons |
|----------|------|------|
| **Hierarchical** (current) | Lower token cost, faster, scales to long conversations | Some detail loss over many iterations |
| **Full re-summarization** | More accurate, no accumulated summarization artifacts | Higher token cost, doesn't scale |

We chose hierarchical because:
1. Token savings are significant for long conversations
2. The summary only needs to provide enough context for continuation
3. Full message history is always preserved for reference

### Summary Window Size

| `recentMessagesToKeep` | Effect |
|------------------------|--------|
| 5 | More aggressive summarization, smaller context |
| 10 (current) | Balanced - recent context preserved |
| 20 | Less summarization, larger context windows needed |

---

## File Locations

| File | Purpose |
|------|---------|
| `Core/Models/Persistence/SessionSummary.swift` | Summary data model |
| `Core/Models/ChatMessage.swift` | ChatSession with memory fields |
| `Core/Services/SummarizationManager.swift` | Summarization logic |
| `Core/Services/SessionManager.swift` | Integration and sync |
| `Core/Models/Persistence/PersistedSession.swift` | Summary persistence |

---

## Future Enhancements

1. **Configurable thresholds**: Allow users to adjust summarization triggers
2. **Summary quality metrics**: Track and improve summary quality over time
3. **Selective summarization**: Summarize based on topic changes, not just message count
4. **Multi-level summaries**: Keep both detailed and high-level summaries
5. **User-editable summaries**: Allow manual correction of summaries
