// MARK: - Persistence POC
// Proof of concept for conversation serialization/deserialization
// Part of Phase 1 investigation for 007-memory-persistence
//
// Design Decisions Incorporated:
// - Per-message contextData (not per-conversation)
// - Separate PersistedConversation struct
// - Embedded summary in conversation file
// - Multi-session file structure (index.json + {uuid}.json)
// - Title auto-generation from first user message

import Foundation

// MARK: - Persisted Models (POC)

/// Index entry for a single conversation (for fast listing)
struct ConversationIndexEntry: Codable, Identifiable {
    let id: UUID                        // Matches conversation file name
    var title: String                   // Display title
    let createdAt: Date                 // When conversation started
    var updatedAt: Date                 // Last activity
    var messageCount: Int               // Total messages
    var preview: String?                // First user message (truncated)
}

/// Index file containing all conversation metadata
struct ConversationIndex: Codable {
    let version: Int
    var conversations: [ConversationIndexEntry]
    var activeConversationId: UUID?     // Currently open conversation
    var lastUpdated: Date

    static let currentVersion = 1
}

/// Extended ChatMessage with per-message context support
/// Note: In production, this would extend the existing ChatMessage model
struct PersistedChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    let contextData: Data?              // Encoded Context (optional, for user messages)

    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date(), contextData: Data? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextData = contextData
    }

    /// Convert from existing ChatMessage (without context)
    init(from message: ChatMessage, contextData: Data? = nil) {
        self.id = message.id
        self.role = message.role
        self.content = message.content
        self.timestamp = message.timestamp
        self.contextData = contextData
    }

    /// Convert to existing ChatMessage (loses context)
    func toChatMessage() -> ChatMessage {
        ChatMessage(id: id, role: role, content: content, timestamp: timestamp)
    }
}

/// Codable representation of a conversation for persistence
/// Separates persistence concerns from the live ChatConversation model
struct PersistedConversation: Codable {
    // MARK: - Identity
    let id: UUID                        // Conversation identifier
    let version: Int                    // Schema version for migrations

    // MARK: - Core Data
    let messages: [PersistedChatMessage] // ALL messages with per-message context
    let initialRequest: String?         // Original user instruction
    let maxMessages: Int                // Max messages setting

    // MARK: - Metadata
    let createdAt: Date                 // When conversation started
    var updatedAt: Date                 // Last modification time
    var title: String?                  // Auto-generated or user-set title

    // MARK: - Summary State (P2)
    var summary: String?                // LLM-generated summary of older messages
    var summaryCoversMessageCount: Int? // Number of messages covered by summary
    var summaryCreatedAt: Date?         // When summary was generated

    // MARK: - Schema Version
    static let currentVersion = 1

    // MARK: - Create from live ChatConversation

    @MainActor
    static func from(_ conversation: ChatConversation, id: UUID? = nil, currentContext: Context? = nil) -> PersistedConversation {
        // Convert messages, adding context to user messages if provided
        let persistedMessages = conversation.messages.enumerated().map { index, message -> PersistedChatMessage in
            var contextData: Data? = nil

            // For the first user message, encode the current context if available
            // In production, context would be stored per-message as user sends from different apps
            if message.role == .user && index == 0, let ctx = currentContext ?? conversation.originalContext {
                contextData = try? JSONEncoder().encode(ctx)
            }

            return PersistedChatMessage(from: message, contextData: contextData)
        }

        return PersistedConversation(
            id: id ?? UUID(),
            version: currentVersion,
            messages: persistedMessages,
            initialRequest: conversation.initialRequest,
            maxMessages: conversation.maxMessages,
            createdAt: Date(),
            updatedAt: Date(),
            title: generateTitle(from: persistedMessages)
        )
    }

    // MARK: - Restore to live ChatConversation

    @MainActor
    func toConversation() -> ChatConversation {
        // Decode originalContext from first user message if present
        var originalContext: Context?
        if let firstUserMessage = messages.first(where: { $0.role == .user }),
           let data = firstUserMessage.contextData {
            originalContext = try? JSONDecoder().decode(Context.self, from: data)
        }

        let conv = ChatConversation(
            originalContext: originalContext,
            initialRequest: initialRequest,
            maxMessages: maxMessages
        )

        // Restore messages directly (avoid triggering trimIfNeeded for each)
        for message in messages {
            conv.messages.append(message.toChatMessage())
        }

        return conv
    }

    // MARK: - LLM Context Building

    /// Build messages array for LLM API call (uses summary if available)
    func buildLLMContext() -> [PersistedChatMessage] {
        if let summary = summary, let coveredCount = summaryCoversMessageCount, coveredCount > 0 {
            // Use summary + messages after the summarized portion
            let summaryMessage = PersistedChatMessage(
                id: UUID(),
                role: .system,
                content: "Previous conversation context: \(summary)",
                timestamp: summaryCreatedAt ?? createdAt
            )
            let recentMessages = Array(messages.suffix(from: min(coveredCount, messages.count)))
            return [summaryMessage] + recentMessages
        } else {
            // No summary, use all messages
            return messages
        }
    }

    // MARK: - Title Generation

    /// Auto-generate title from first user message (truncated to ~50 chars)
    static func generateTitle(from messages: [PersistedChatMessage]) -> String? {
        guard let firstUserMessage = messages.first(where: { $0.role == .user }) else {
            return nil
        }

        let content = firstUserMessage.content
        if content.count <= 50 {
            return content
        }

        // Truncate at word boundary
        let truncated = String(content.prefix(50))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
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

    /// Path to conversations directory
    static var conversationsURL: URL {
        let url = applicationSupportURL.appendingPathComponent("conversations", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Path to index file
    static var indexURL: URL {
        conversationsURL.appendingPathComponent("index.json")
    }

    /// Path to conversation file
    static func conversationURL(id: UUID) -> URL {
        conversationsURL.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Index Operations

    /// Load conversation index
    static func loadIndex() throws -> ConversationIndex {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if FileManager.default.fileExists(atPath: indexURL.path) {
            let data = try Data(contentsOf: indexURL)
            return try decoder.decode(ConversationIndex.self, from: data)
        } else {
            // Return empty index
            return ConversationIndex(
                version: ConversationIndex.currentVersion,
                conversations: [],
                activeConversationId: nil,
                lastUpdated: Date()
            )
        }
    }

    /// Save conversation index
    static func saveIndex(_ index: ConversationIndex) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)

        print("[PersistencePOC] Saved index with \(index.conversations.count) entries")
    }

    // MARK: - Conversation Operations

    /// Save conversation to disk
    static func save(_ persisted: PersistedConversation) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(persisted)
        let fileURL = conversationURL(id: persisted.id)
        try data.write(to: fileURL, options: .atomic)

        print("[PersistencePOC] Saved conversation \(persisted.id) with \(persisted.messages.count) messages")
        print("[PersistencePOC] File: \(fileURL.path)")

        // Update index
        var index = try loadIndex()
        let entry = ConversationIndexEntry(
            id: persisted.id,
            title: persisted.title ?? "New Conversation",
            createdAt: persisted.createdAt,
            updatedAt: persisted.updatedAt,
            messageCount: persisted.messages.count,
            preview: persisted.messages.first(where: { $0.role == .user })?.content.prefix(100).description
        )

        if let existingIndex = index.conversations.firstIndex(where: { $0.id == persisted.id }) {
            index.conversations[existingIndex] = entry
        } else {
            index.conversations.append(entry)
        }
        index.lastUpdated = Date()

        try saveIndex(index)
    }

    /// Load conversation from disk
    static func load(id: UUID) throws -> PersistedConversation {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let fileURL = conversationURL(id: id)
        let data = try Data(contentsOf: fileURL)
        let persisted = try decoder.decode(PersistedConversation.self, from: data)

        print("[PersistencePOC] Loaded conversation \(id) with \(persisted.messages.count) messages")
        return persisted
    }

    /// Check if a saved conversation exists
    static func exists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: conversationURL(id: id).path)
    }

    /// Delete saved conversation
    static func delete(id: UUID) throws {
        let fileURL = conversationURL(id: id)
        try FileManager.default.removeItem(at: fileURL)

        // Update index
        var index = try loadIndex()
        index.conversations.removeAll { $0.id == id }
        index.lastUpdated = Date()
        try saveIndex(index)

        print("[PersistencePOC] Deleted conversation \(id)")
    }

    /// Delete all data
    static func deleteAll() throws {
        try FileManager.default.removeItem(at: conversationsURL)
        print("[PersistencePOC] Deleted all conversation data")
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
            let loaded = try PersistenceStoragePOC.load(id: persisted.id)

            // Verify
            assert(loaded.messages.count == 4, "Expected 4 messages")
            assert(loaded.initialRequest == "Test instruction", "Expected initial request")
            assert(loaded.messages[0].content == "Hello, this is a test", "Expected first message")
            assert(loaded.messages[1].role == .assistant, "Expected assistant role")
            assert(loaded.title != nil, "Expected auto-generated title")

            print("  ✅ Save/load cycle successful")
            print("  📌 Title: \(loaded.title ?? "nil")")
            passed += 1

            // Clean up
            try PersistenceStoragePOC.delete(id: persisted.id)

        } catch {
            print("  ❌ Test 1 failed: \(error)")
            failed += 1
        }

        // Test 2: Per-message context storage
        do {
            print("\n📝 Test 2: Per-Message Context Storage")

            // Simulate context from different apps
            let slackContext = Context(
                source: ContextSource(
                    applicationName: "Slack",
                    bundleIdentifier: "com.slack.app",
                    windowTitle: "General Channel"
                ),
                selectedText: "Message from Slack"
            )

            let gmailContext = Context(
                source: ContextSource(
                    applicationName: "Gmail",
                    bundleIdentifier: "com.google.gmail",
                    windowTitle: "Inbox"
                ),
                selectedText: "Email content"
            )

            // Create messages with different contexts
            let messages: [PersistedChatMessage] = [
                PersistedChatMessage(
                    role: .user,
                    content: "Help me respond to this Slack message",
                    contextData: try? JSONEncoder().encode(slackContext)
                ),
                PersistedChatMessage(
                    role: .assistant,
                    content: "Here's a suggested response..."
                ),
                PersistedChatMessage(
                    role: .user,
                    content: "Now help me with this email",
                    contextData: try? JSONEncoder().encode(gmailContext)
                ),
                PersistedChatMessage(
                    role: .assistant,
                    content: "Sure, here's help with the email..."
                )
            ]

            let persisted = PersistedConversation(
                id: UUID(),
                version: 1,
                messages: messages,
                initialRequest: nil,
                maxMessages: 20,
                createdAt: Date(),
                updatedAt: Date(),
                title: "Multi-context test"
            )

            try PersistenceStoragePOC.save(persisted)
            let loaded = try PersistenceStoragePOC.load(id: persisted.id)

            // Verify per-message context
            assert(loaded.messages[0].contextData != nil, "Expected Slack context on first message")
            assert(loaded.messages[1].contextData == nil, "Assistant should have no context")
            assert(loaded.messages[2].contextData != nil, "Expected Gmail context on third message")
            assert(loaded.messages[3].contextData == nil, "Assistant should have no context")

            // Decode and verify contexts
            if let slackData = loaded.messages[0].contextData {
                let decoded = try JSONDecoder().decode(Context.self, from: slackData)
                assert(decoded.source.applicationName == "Slack", "Expected Slack app name")
            }

            if let gmailData = loaded.messages[2].contextData {
                let decoded = try JSONDecoder().decode(Context.self, from: gmailData)
                assert(decoded.source.applicationName == "Gmail", "Expected Gmail app name")
            }

            print("  ✅ Per-message context storage successful")
            passed += 1

            try PersistenceStoragePOC.delete(id: persisted.id)

        } catch {
            print("  ❌ Test 2 failed: \(error)")
            failed += 1
        }

        // Test 3: Message content preservation
        do {
            print("\n📝 Test 3: Message Content Preservation")

            let conversation = ChatConversation()

            // Add messages with special characters
            conversation.addUserMessage("Test with unicode: 你好 🎉 émojis")
            conversation.addAssistantMessage("Response with\nnewlines\nand\ttabs")
            conversation.addUserMessage("Code block:\n```swift\nlet x = 1\n```")

            let persisted = PersistedConversation.from(conversation)
            try PersistenceStoragePOC.save(persisted)
            let loaded = try PersistenceStoragePOC.load(id: persisted.id)

            // Restore to conversation
            let restored = loaded.toConversation()

            assert(restored.messages[0].content.contains("你好"), "Expected unicode preserved")
            assert(restored.messages[1].content.contains("\n"), "Expected newlines preserved")
            assert(restored.messages[2].content.contains("```"), "Expected code blocks preserved")

            print("  ✅ Content preservation successful")
            passed += 1

            try PersistenceStoragePOC.delete(id: persisted.id)

        } catch {
            print("  ❌ Test 3 failed: \(error)")
            failed += 1
        }

        // Test 4: Timestamp preservation
        do {
            print("\n📝 Test 4: Timestamp Preservation")

            let conversation = ChatConversation()
            conversation.addUserMessage("Time test")

            let originalTimestamp = conversation.messages[0].timestamp

            let persisted = PersistedConversation.from(conversation)
            try PersistenceStoragePOC.save(persisted)
            let loaded = try PersistenceStoragePOC.load(id: persisted.id)
            let restored = loaded.toConversation()

            let restoredTimestamp = restored.messages[0].timestamp

            // Timestamps should be within 1 second (ISO8601 might lose sub-second precision)
            let diff = abs(originalTimestamp.timeIntervalSince(restoredTimestamp))
            assert(diff < 1.0, "Expected timestamps to match within 1 second, got \(diff)s difference")

            print("  ✅ Timestamp preservation successful (diff: \(diff)s)")
            passed += 1

            try PersistenceStoragePOC.delete(id: persisted.id)

        } catch {
            print("  ❌ Test 4 failed: \(error)")
            failed += 1
        }

        // Test 5: Empty conversation
        do {
            print("\n📝 Test 5: Empty Conversation")

            let conversation = ChatConversation()

            let persisted = PersistedConversation.from(conversation)
            try PersistenceStoragePOC.save(persisted)
            let loaded = try PersistenceStoragePOC.load(id: persisted.id)
            let restored = loaded.toConversation()

            assert(restored.messages.isEmpty, "Expected empty messages")
            assert(restored.isEmpty, "Expected isEmpty to be true")

            print("  ✅ Empty conversation handled correctly")
            passed += 1

            try PersistenceStoragePOC.delete(id: persisted.id)

        } catch {
            print("  ❌ Test 5 failed: \(error)")
            failed += 1
        }

        // Test 6: Context serialization (conversation-level for backward compat)
        do {
            print("\n📝 Test 6: Context Serialization")

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
            let loaded = try PersistenceStoragePOC.load(id: persisted.id)
            let restored = loaded.toConversation()

            assert(restored.originalContext != nil, "Expected context to be restored")
            assert(restored.originalContext?.source.applicationName == "Test App", "Expected app name")
            assert(restored.originalContext?.selectedText == "Selected text content", "Expected selected text")

            print("  ✅ Context serialization successful")
            passed += 1

            try PersistenceStoragePOC.delete(id: persisted.id)

        } catch {
            print("  ❌ Test 6 failed: \(error)")
            failed += 1
        }

        // Test 7: Index operations
        do {
            print("\n📝 Test 7: Index Operations")

            // Create multiple conversations
            let conv1 = ChatConversation()
            conv1.addUserMessage("First conversation")
            let persisted1 = PersistedConversation.from(conv1)
            try PersistenceStoragePOC.save(persisted1)

            let conv2 = ChatConversation()
            conv2.addUserMessage("Second conversation")
            let persisted2 = PersistedConversation.from(conv2)
            try PersistenceStoragePOC.save(persisted2)

            // Load index
            let index = try PersistenceStoragePOC.loadIndex()

            assert(index.conversations.count >= 2, "Expected at least 2 conversations in index")
            assert(index.conversations.contains(where: { $0.id == persisted1.id }), "Expected first conversation in index")
            assert(index.conversations.contains(where: { $0.id == persisted2.id }), "Expected second conversation in index")

            print("  ✅ Index operations successful")
            print("  📌 Index has \(index.conversations.count) entries")
            passed += 1

            // Clean up
            try PersistenceStoragePOC.delete(id: persisted1.id)
            try PersistenceStoragePOC.delete(id: persisted2.id)

        } catch {
            print("  ❌ Test 7 failed: \(error)")
            failed += 1
        }

        // Test 8: Summary embedding
        do {
            print("\n📝 Test 8: Summary Embedding")

            var persisted = PersistedConversation(
                id: UUID(),
                version: 1,
                messages: [
                    PersistedChatMessage(role: .user, content: "Question 1"),
                    PersistedChatMessage(role: .assistant, content: "Answer 1"),
                    PersistedChatMessage(role: .user, content: "Question 2"),
                    PersistedChatMessage(role: .assistant, content: "Answer 2")
                ],
                initialRequest: nil,
                maxMessages: 20,
                createdAt: Date(),
                updatedAt: Date(),
                title: "Summary test",
                summary: "User asked two questions about topics X and Y.",
                summaryCoversMessageCount: 2,
                summaryCreatedAt: Date()
            )

            try PersistenceStoragePOC.save(persisted)
            let loaded = try PersistenceStoragePOC.load(id: persisted.id)

            assert(loaded.summary == "User asked two questions about topics X and Y.", "Expected summary")
            assert(loaded.summaryCoversMessageCount == 2, "Expected summary count")

            // Test LLM context building
            let llmContext = loaded.buildLLMContext()
            assert(llmContext[0].role == .system, "Expected system message with summary")
            assert(llmContext[0].content.contains("Previous conversation context"), "Expected summary prefix")

            print("  ✅ Summary embedding successful")
            passed += 1

            try PersistenceStoragePOC.delete(id: persisted.id)

        } catch {
            print("  ❌ Test 8 failed: \(error)")
            failed += 1
        }

        // Test 9: Title auto-generation
        do {
            print("\n📝 Test 9: Title Auto-Generation")

            // Short message - full content as title
            let shortConv = ChatConversation()
            shortConv.addUserMessage("Help me with Swift")
            let shortPersisted = PersistedConversation.from(shortConv)
            assert(shortPersisted.title == "Help me with Swift", "Expected full short message as title")

            // Long message - truncated at word boundary
            let longConv = ChatConversation()
            longConv.addUserMessage("I need help understanding how to implement a complex persistence layer for my macOS application")
            let longPersisted = PersistedConversation.from(longConv)
            assert(longPersisted.title?.count ?? 0 <= 52, "Expected truncated title") // 50 + "…"
            assert(longPersisted.title?.hasSuffix("…") == true, "Expected ellipsis")

            print("  ✅ Title auto-generation successful")
            print("  📌 Short: \(shortPersisted.title ?? "nil")")
            print("  📌 Long: \(longPersisted.title ?? "nil")")
            passed += 1

        } catch {
            print("  ❌ Test 9 failed: \(error)")
            failed += 1
        }

        // Summary
        print("\n" + String(repeating: "=", count: 60))
        print("📊 RESULTS: \(passed) passed, \(failed) failed")
        print(String(repeating: "=", count: 60))

        if failed == 0 {
            print("\n✅ POC VALIDATION SUCCESSFUL")
            print("Persistence approach is viable for production implementation.")
            print("\nDesign decisions validated:")
            print("  • Per-message contextData storage")
            print("  • Multi-session file structure (index.json + {uuid}.json)")
            print("  • Embedded summary in conversation file")
            print("  • Title auto-generation from first user message")
            print("  • Atomic writes for crash safety")
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
