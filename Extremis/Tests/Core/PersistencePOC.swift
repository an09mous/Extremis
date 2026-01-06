// MARK: - Persistence POC
// Proof of concept for conversation serialization/deserialization
// Part of Phase 1 investigation for 007-memory-persistence

import Foundation

// MARK: - Persisted Conversation Model (POC)

/// Lightweight Codable representation for persistence
/// This separates persistence concerns from the live ChatConversation model
struct PersistedConversation: Codable {
    let id: UUID
    let messages: [ChatMessage]
    let originalContextData: Data?  // Encoded Context, if available
    let initialRequest: String?
    let maxMessages: Int
    let createdAt: Date
    let updatedAt: Date

    /// Create from live ChatConversation
    @MainActor
    static func from(_ conversation: ChatConversation) -> PersistedConversation {
        // Encode originalContext if present
        var contextData: Data?
        if let context = conversation.originalContext {
            contextData = try? JSONEncoder().encode(context)
        }

        return PersistedConversation(
            id: UUID(),
            messages: conversation.messages,
            originalContextData: contextData,
            initialRequest: conversation.initialRequest,
            maxMessages: conversation.maxMessages,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Restore to live ChatConversation
    @MainActor
    func toConversation() -> ChatConversation {
        // Decode originalContext if present
        var originalContext: Context?
        if let data = originalContextData {
            originalContext = try? JSONDecoder().decode(Context.self, from: data)
        }

        let conv = ChatConversation(
            originalContext: originalContext,
            initialRequest: initialRequest,
            maxMessages: maxMessages
        )

        // Restore messages directly (avoid triggering trimIfNeeded for each)
        for message in messages {
            conv.messages.append(message)
        }

        return conv
    }
}

// MARK: - Storage Manager (POC)

/// Simple file-based storage for conversations
struct PersistenceStoragePOC {

    /// Get the Application Support directory for Extremis
    static var applicationSupportURL: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let extremisDir = appSupport.appendingPathComponent("Extremis", isDirectory: true)

        // Create directory if needed
        try? fileManager.createDirectory(at: extremisDir, withIntermediateDirectories: true)

        return extremisDir
    }

    /// Path to current conversation file
    static var currentConversationURL: URL {
        applicationSupportURL.appendingPathComponent("current-conversation.json")
    }

    /// Save conversation to disk
    static func save(_ persisted: PersistedConversation) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(persisted)
        try data.write(to: currentConversationURL, options: .atomic)

        print("[PersistencePOC] Saved conversation with \(persisted.messages.count) messages")
        print("[PersistencePOC] File: \(currentConversationURL.path)")
    }

    /// Load conversation from disk
    static func load() throws -> PersistedConversation {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try Data(contentsOf: currentConversationURL)
        let persisted = try decoder.decode(PersistedConversation.self, from: data)

        print("[PersistencePOC] Loaded conversation with \(persisted.messages.count) messages")
        return persisted
    }

    /// Check if a saved conversation exists
    static func exists() -> Bool {
        FileManager.default.fileExists(atPath: currentConversationURL.path)
    }

    /// Delete saved conversation
    static func delete() throws {
        try FileManager.default.removeItem(at: currentConversationURL)
        print("[PersistencePOC] Deleted saved conversation")
    }
}

// MARK: - POC Test Runner

@MainActor
struct PersistencePOCTests {

    static func runAllTests() {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 PERSISTENCE POC TESTS")
        print(String(repeating: "=", count: 60))

        var passed = 0
        var failed = 0

        // Test 1: Basic save/load cycle
        do {
            print("\n📝 Test 1: Basic Save/Load Cycle")

            // Create a conversation with messages
            let conversation = ChatConversation(
                initialRequest: "Test instruction",
                maxMessages: 20
            )
            conversation.addUserMessage("Hello, this is a test")
            conversation.addAssistantMessage("Hi there! This is a response.")
            conversation.addUserMessage("Follow-up question")
            conversation.addAssistantMessage("Follow-up answer")

            // Convert to persisted format
            let persisted = PersistedConversation.from(conversation)

            // Save to disk
            try PersistenceStoragePOC.save(persisted)

            // Load from disk
            let loaded = try PersistenceStoragePOC.load()

            // Verify
            assert(loaded.messages.count == 4, "Expected 4 messages")
            assert(loaded.initialRequest == "Test instruction", "Expected initial request")
            assert(loaded.messages[0].content == "Hello, this is a test", "Expected first message")
            assert(loaded.messages[1].role == .assistant, "Expected assistant role")

            print("  ✅ Save/load cycle successful")
            passed += 1

            // Clean up
            try PersistenceStoragePOC.delete()

        } catch {
            print("  ❌ Test 1 failed: \(error)")
            failed += 1
        }

        // Test 2: Message content preservation
        do {
            print("\n📝 Test 2: Message Content Preservation")

            let conversation = ChatConversation()

            // Add messages with special characters
            conversation.addUserMessage("Test with unicode: 你好 🎉 émojis")
            conversation.addAssistantMessage("Response with\nnewlines\nand\ttabs")
            conversation.addUserMessage("Code block:\n```swift\nlet x = 1\n```")

            let persisted = PersistedConversation.from(conversation)
            try PersistenceStoragePOC.save(persisted)
            let loaded = try PersistenceStoragePOC.load()

            // Restore to conversation
            let restored = loaded.toConversation()

            assert(restored.messages[0].content.contains("你好"), "Expected unicode preserved")
            assert(restored.messages[1].content.contains("\n"), "Expected newlines preserved")
            assert(restored.messages[2].content.contains("```"), "Expected code blocks preserved")

            print("  ✅ Content preservation successful")
            passed += 1

            try PersistenceStoragePOC.delete()

        } catch {
            print("  ❌ Test 2 failed: \(error)")
            failed += 1
        }

        // Test 3: Timestamp preservation
        do {
            print("\n📝 Test 3: Timestamp Preservation")

            let conversation = ChatConversation()
            conversation.addUserMessage("Time test")

            let originalTimestamp = conversation.messages[0].timestamp

            let persisted = PersistedConversation.from(conversation)
            try PersistenceStoragePOC.save(persisted)
            let loaded = try PersistenceStoragePOC.load()
            let restored = loaded.toConversation()

            let restoredTimestamp = restored.messages[0].timestamp

            // Timestamps should be within 1 second (ISO8601 might lose sub-second precision)
            let diff = abs(originalTimestamp.timeIntervalSince(restoredTimestamp))
            assert(diff < 1.0, "Expected timestamps to match within 1 second, got \(diff)s difference")

            print("  ✅ Timestamp preservation successful (diff: \(diff)s)")
            passed += 1

            try PersistenceStoragePOC.delete()

        } catch {
            print("  ❌ Test 3 failed: \(error)")
            failed += 1
        }

        // Test 4: Empty conversation
        do {
            print("\n📝 Test 4: Empty Conversation")

            let conversation = ChatConversation()

            let persisted = PersistedConversation.from(conversation)
            try PersistenceStoragePOC.save(persisted)
            let loaded = try PersistenceStoragePOC.load()
            let restored = loaded.toConversation()

            assert(restored.messages.isEmpty, "Expected empty messages")
            assert(restored.isEmpty, "Expected isEmpty to be true")

            print("  ✅ Empty conversation handled correctly")
            passed += 1

            try PersistenceStoragePOC.delete()

        } catch {
            print("  ❌ Test 4 failed: \(error)")
            failed += 1
        }

        // Test 5: Context serialization
        do {
            print("\n📝 Test 5: Context Serialization")

            let context = Context(
                source: ContextSource(
                    applicationName: "Test App",
                    bundleIdentifier: "com.test.app",
                    windowTitle: "Test Window"
                ),
                selectedText: "Selected text content",
                precedingText: "Text before cursor"
            )

            let conversation = ChatConversation(
                originalContext: context,
                initialRequest: "Help me with this"
            )
            conversation.addUserMessage("Question about the context")

            let persisted = PersistedConversation.from(conversation)
            try PersistenceStoragePOC.save(persisted)
            let loaded = try PersistenceStoragePOC.load()
            let restored = loaded.toConversation()

            assert(restored.originalContext != nil, "Expected context to be restored")
            assert(restored.originalContext?.source.applicationName == "Test App", "Expected app name")
            assert(restored.originalContext?.selectedText == "Selected text content", "Expected selected text")

            print("  ✅ Context serialization successful")
            passed += 1

            try PersistenceStoragePOC.delete()

        } catch {
            print("  ❌ Test 5 failed: \(error)")
            failed += 1
        }

        // Summary
        print("\n" + String(repeating: "=", count: 60))
        print("📊 RESULTS: \(passed) passed, \(failed) failed")
        print(String(repeating: "=", count: 60))

        if failed == 0 {
            print("\n✅ POC VALIDATION SUCCESSFUL")
            print("Persistence approach is viable for production implementation.")
        } else {
            print("\n❌ POC VALIDATION FAILED")
            print("Review failed tests before proceeding.")
        }
    }
}

// MARK: - Entry Point

/// Run POC tests (call from app or playground)
@MainActor
func runPersistencePOC() {
    PersistencePOCTests.runAllTests()
}
