# Quickstart: Memory & Persistence Testing Guide

**Feature Branch**: `007-memory-persistence`
**Created**: 2026-01-04
**Status**: Phase 1 POC Testing

---

## Overview

This guide explains how to test the proof-of-concept implementations for the Memory & Persistence feature.

---

## POC Files

| File | Purpose | Location |
|------|---------|----------|
| PersistencePOC.swift | Save/load cycle testing | `Extremis/Tests/Core/PersistencePOC.swift` |
| LifecyclePOC.swift | App lifecycle integration | `Extremis/Tests/Core/LifecyclePOC.swift` |

---

## Running Persistence POC Tests

### Option 1: From Xcode

1. Open `Extremis.xcodeproj`
2. Navigate to `Extremis/Tests/Core/PersistencePOC.swift`
3. Add a call to run tests from AppDelegate or a test target:

```swift
// In AppDelegate.applicationDidFinishLaunching or similar
#if DEBUG
Task { @MainActor in
    runPersistencePOC()
}
#endif
```

4. Run the app and check console output

### Option 2: Swift Playground

```swift
import Foundation

// Copy the contents of PersistencePOC.swift here
// Then call:
runPersistencePOC()
```

### Expected Output

```
============================================================
🧪 PERSISTENCE POC TESTS
============================================================

📝 Test 1: Basic Save/Load Cycle
[PersistencePOC] Saved conversation with 4 messages
[PersistencePOC] File: /Users/.../Extremis/current-conversation.json
[PersistencePOC] Loaded conversation with 4 messages
  ✅ Save/load cycle successful

📝 Test 2: Message Content Preservation
  ✅ Content preservation successful

📝 Test 3: Timestamp Preservation
  ✅ Timestamp preservation successful (diff: 0.0s)

📝 Test 4: Empty Conversation
  ✅ Empty conversation handled correctly

📝 Test 5: Context Serialization
  ✅ Context serialization successful

============================================================
📊 RESULTS: 5 passed, 0 failed
============================================================

✅ POC VALIDATION SUCCESSFUL
Persistence approach is viable for production implementation.
```

---

## Running Lifecycle POC Tests

### Setup

1. Navigate to `Extremis/Tests/Core/LifecyclePOC.swift`
2. Add observer initialization in AppDelegate:

```swift
// In AppDelegate
#if DEBUG
private var lifecycleObserver: LifecycleObserverPOC?

func applicationDidFinishLaunching(_ notification: Notification) {
    // Existing code...

    // POC: Test lifecycle observation
    Task { @MainActor in
        self.lifecycleObserver = LifecycleObserverPOC()
        runLifecyclePOC()
    }
}
#endif
```

### Testing Lifecycle Events

1. **App Hide (Cmd+H)**:
   - Hide the app with Cmd+H
   - Check console for: `[LifecyclePOC] 🟠 App will hide`
   - Expect debounced save scheduled

2. **App Switch (Cmd+Tab)**:
   - Switch to another app
   - Check console for: `[LifecyclePOC] 🟡 App will resign active`
   - Switch back quickly - debounce should cancel

3. **App Quit (Cmd+Q)**:
   - Quit the app normally
   - Check console for: `[LifecyclePOC] 🔴 App will terminate`
   - Expect synchronous save

### Expected Console Output

```
============================================================
🧪 LIFECYCLE POC TESTS
============================================================

📋 FINDINGS:

    1. RECOMMENDED SAVE TRIGGERS:
       - NSApplication.willTerminateNotification (CRITICAL)
       - NSApplication.willResignActiveNotification (with debounce)
       - After each message (debounced, 2s delay)

    2. FORCE-QUIT HANDLING:
       - Force-quit (Cmd+Option+Esc) does NOT trigger willTerminate
       - Mitigation: Save frequently with debouncing
       - Mitigation: Save after each message with short debounce

    3. TIMING CONSIDERATIONS:
       - willTerminate has ~5s before forced kill
       - JSON encoding + file write: typically <50ms for ~1000 messages
       - Use synchronous save in willTerminate (no async)

    4. DEBOUNCE STRATEGY:
       - Wait 2s after last change before saving
       - Cancel debounce if user returns quickly
       - Force save on explicit actions (New Conversation)

✅ LIFECYCLE POC COMPLETE
```

---

## Verifying Saved Data

### Finding the Save Location

```bash
# Default location
ls -la ~/Library/Application\ Support/Extremis/

# View saved conversation
cat ~/Library/Application\ Support/Extremis/current-conversation.json | jq .
```

### Expected JSON Structure

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "version": 1,
  "messages": [
    {
      "id": "...",
      "role": "user",
      "content": "Hello, this is a test",
      "timestamp": "2026-01-04T12:00:00Z"
    },
    {
      "id": "...",
      "role": "assistant",
      "content": "Hi there! This is a response.",
      "timestamp": "2026-01-04T12:00:01Z"
    }
  ],
  "createdAt": "2026-01-04T12:00:00Z",
  "updatedAt": "2026-01-04T12:00:01Z",
  "maxMessages": 20
}
```

---

## Cleaning Up Test Data

```bash
# Remove test files
rm -rf ~/Library/Application\ Support/Extremis/

# Or from Swift
try FileManager.default.removeItem(at: PersistenceStoragePOC.applicationSupportURL)
```

---

## Known Limitations (POC)

1. **No real persistence service**: POC uses standalone functions
2. **No debounce timer cleanup**: Timer may fire after deallocation in POC
3. **No error handling UI**: Errors only logged to console
4. **Force-quit not handled**: Data may be lost on Cmd+Opt+Esc

These will be addressed in Phase 2 implementation.

---

## Next Steps

After POC validation, proceed to Phase 2:

1. Implement `PersistenceService` singleton
2. Integrate with `ChatConversation`
3. Add lifecycle hooks to AppDelegate
4. Implement "New Conversation" UI action
5. Add restore-on-launch logic

See `tasks.md` Phase 2 section for detailed implementation tasks.
