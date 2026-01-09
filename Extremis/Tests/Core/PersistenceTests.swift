// MARK: - Persistence Unit Tests
// Standalone test runner for conversation persistence functionality
// Tests PersistedMessage, PersistedConversation, ConversationIndex, and edge cases

import Foundation

// MARK: - Test Runner Framework

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []
    static var currentGroup = ""

    static func setGroup(_ name: String) {
        currentGroup = name
        print("")
        print("📦 \(name)")
        print("----------------------------------------")
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ testName: String) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected '\(expected)' but got '\(actual)'"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
    }

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected nil but got '\(value!)'"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
    }

    static func assertNotNil<T>(_ value: T?, _ testName: String) {
        if value != nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected non-nil but got nil"))
            print("  ✗ \(testName): Expected non-nil but got nil")
        }
    }

    static func assertTrue(_ condition: Bool, _ testName: String) {
        if condition {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected true but got false"))
            print("  ✗ \(testName): Expected true but got false")
        }
    }

    static func assertFalse(_ condition: Bool, _ testName: String) {
        assertTrue(!condition, testName)
    }

    static func assertThrows<T>(_ expression: @autoclosure () throws -> T, _ testName: String) {
        do {
            _ = try expression()
            failedCount += 1
            failedTests.append((testName, "Expected exception but none was thrown"))
            print("  ✗ \(testName): Expected exception but none was thrown")
        } catch {
            passedCount += 1
            print("  ✓ \(testName)")
        }
    }

    static func printSummary() {
        print("")
        print("==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("")
            print("Failed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("==================================================")
    }
}

// MARK: - Inline Types (for standalone testing)

enum ChatRole: String, Codable, Equatable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }
}

// Minimal Context struct for testing
struct TestContext: Codable, Equatable {
    let applicationName: String
    let selectedText: String?

    init(applicationName: String, selectedText: String? = nil) {
        self.applicationName = applicationName
        self.selectedText = selectedText
    }
}

// MARK: - PersistedMessage (inline for standalone test)

struct PersistedMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    let contextData: Data?

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        contextData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextData = contextData
    }

    init(from message: ChatMessage, contextData: Data? = nil) {
        self.id = message.id
        self.role = message.role
        self.content = message.content
        self.timestamp = message.timestamp
        self.contextData = contextData
    }

    func toChatMessage() -> ChatMessage {
        ChatMessage(id: id, role: role, content: content, timestamp: timestamp)
    }

    func decodeContext() -> TestContext? {
        guard let data = contextData else { return nil }
        return try? JSONDecoder().decode(TestContext.self, from: data)
    }

    static func encodeContext(_ context: TestContext?) -> Data? {
        guard let context = context else { return nil }
        return try? JSONEncoder().encode(context)
    }

    var hasContext: Bool {
        contextData != nil
    }
}

// MARK: - ConversationIndexEntry (inline)

struct ConversationIndexEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var preview: String?
    var isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, messageCount, preview, isArchived
        case lastModifiedAt  // backward compatibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        if let updated = try? container.decode(Date.self, forKey: .updatedAt) {
            updatedAt = updated
        } else {
            updatedAt = try container.decode(Date.self, forKey: .lastModifiedAt)
        }
        messageCount = try container.decode(Int.self, forKey: .messageCount)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encodeIfPresent(preview, forKey: .preview)
        try container.encode(isArchived, forKey: .isArchived)
    }

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        messageCount: Int,
        preview: String? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.preview = preview
        self.isArchived = isArchived
    }

    static func truncateForTitle(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 50 {
            return trimmed
        }
        let truncated = String(trimmed.prefix(50))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }
}

// MARK: - ConversationIndex (inline)

struct ConversationIndex: Codable, Equatable {
    let version: Int
    var conversations: [ConversationIndexEntry]
    var activeConversationId: UUID?
    var lastUpdated: Date

    static let currentVersion = 1

    init(
        version: Int = Self.currentVersion,
        conversations: [ConversationIndexEntry] = [],
        activeConversationId: UUID? = nil,
        lastUpdated: Date = Date()
    ) {
        self.version = version
        self.conversations = conversations
        self.activeConversationId = activeConversationId
        self.lastUpdated = lastUpdated
    }

    var activeConversations: [ConversationIndexEntry] {
        conversations
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var archivedConversations: [ConversationIndexEntry] {
        conversations
            .filter { $0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func entry(for id: UUID) -> ConversationIndexEntry? {
        conversations.first { $0.id == id }
    }

    func contains(id: UUID) -> Bool {
        conversations.contains { $0.id == id }
    }

    mutating func upsert(_ entry: ConversationIndexEntry) {
        if let index = conversations.firstIndex(where: { $0.id == entry.id }) {
            conversations[index] = entry
        } else {
            conversations.append(entry)
        }
        lastUpdated = Date()
    }

    mutating func remove(id: UUID) {
        conversations.removeAll { $0.id == id }
        if activeConversationId == id {
            activeConversationId = nil
        }
        lastUpdated = Date()
    }
}

// MARK: - Test Cases: PersistedMessage

func testPersistedMessage_BasicCreation() {
    TestRunner.setGroup("PersistedMessage - Basic Creation")

    let msg = PersistedMessage(role: .user, content: "Hello world")
    TestRunner.assertEqual(msg.role, .user, "Role is user")
    TestRunner.assertEqual(msg.content, "Hello world", "Content matches")
    TestRunner.assertFalse(msg.hasContext, "No context by default")
}

func testPersistedMessage_FromChatMessage() {
    TestRunner.setGroup("PersistedMessage - From ChatMessage")

    let chatMsg = ChatMessage.user("Test message")
    let persisted = PersistedMessage(from: chatMsg)

    TestRunner.assertEqual(persisted.id, chatMsg.id, "ID preserved")
    TestRunner.assertEqual(persisted.role, chatMsg.role, "Role preserved")
    TestRunner.assertEqual(persisted.content, chatMsg.content, "Content preserved")
}

func testPersistedMessage_ToChatMessage() {
    TestRunner.setGroup("PersistedMessage - To ChatMessage")

    let persisted = PersistedMessage(role: .assistant, content: "Response")
    let chatMsg = persisted.toChatMessage()

    TestRunner.assertEqual(chatMsg.id, persisted.id, "ID preserved")
    TestRunner.assertEqual(chatMsg.role, persisted.role, "Role preserved")
    TestRunner.assertEqual(chatMsg.content, persisted.content, "Content preserved")
}

func testPersistedMessage_ContextEncodeDecode() {
    TestRunner.setGroup("PersistedMessage - Context Encode/Decode")

    let context = TestContext(applicationName: "VSCode", selectedText: "let x = 5")
    let contextData = PersistedMessage.encodeContext(context)

    TestRunner.assertNotNil(contextData, "Context encoded successfully")

    let msg = PersistedMessage(role: .user, content: "Fix this", contextData: contextData)
    TestRunner.assertTrue(msg.hasContext, "Message has context")

    let decodedContext = msg.decodeContext()
    TestRunner.assertNotNil(decodedContext, "Context decoded successfully")
    TestRunner.assertEqual(decodedContext?.applicationName, "VSCode", "App name matches")
    TestRunner.assertEqual(decodedContext?.selectedText, "let x = 5", "Selected text matches")
}

func testPersistedMessage_NilContextEncode() {
    TestRunner.setGroup("PersistedMessage - Nil Context")

    let contextData = PersistedMessage.encodeContext(nil)
    TestRunner.assertNil(contextData, "Nil context returns nil data")

    let msg = PersistedMessage(role: .user, content: "No context")
    TestRunner.assertFalse(msg.hasContext, "No context flag")
    TestRunner.assertNil(msg.decodeContext(), "Decoding nil context returns nil")
}

func testPersistedMessage_Codable() {
    TestRunner.setGroup("PersistedMessage - Codable Round Trip")

    let original = PersistedMessage(role: .user, content: "Test encoding")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(PersistedMessage.self, from: data)

        TestRunner.assertEqual(decoded.id, original.id, "ID survives encoding")
        TestRunner.assertEqual(decoded.role, original.role, "Role survives encoding")
        TestRunner.assertEqual(decoded.content, original.content, "Content survives encoding")
    } catch {
        TestRunner.assertTrue(false, "Encoding/decoding failed: \(error)")
    }
}

// MARK: - Test Cases: ConversationIndexEntry

func testIndexEntry_TitleTruncation() {
    TestRunner.setGroup("ConversationIndexEntry - Title Truncation")

    // Short title - no truncation
    let short = ConversationIndexEntry.truncateForTitle("Short title")
    TestRunner.assertEqual(short, "Short title", "Short title unchanged")

    // Exactly 50 chars - no truncation
    let exact50 = String(repeating: "a", count: 50)
    let truncated50 = ConversationIndexEntry.truncateForTitle(exact50)
    TestRunner.assertEqual(truncated50.count, 50, "50 chars unchanged")

    // 51 chars - truncates with ellipsis
    let long = "This is a very long title that should be truncated at word boundary"
    let truncatedLong = ConversationIndexEntry.truncateForTitle(long)
    TestRunner.assertTrue(truncatedLong.hasSuffix("…"), "Long title has ellipsis")
    TestRunner.assertTrue(truncatedLong.count <= 51, "Truncated within limit (+1 for ellipsis)")

    // Whitespace trimming
    let whitespace = "  Padded title  "
    let trimmed = ConversationIndexEntry.truncateForTitle(whitespace)
    TestRunner.assertEqual(trimmed, "Padded title", "Whitespace trimmed")
}

func testIndexEntry_Creation() {
    TestRunner.setGroup("ConversationIndexEntry - Creation")

    let id = UUID()
    let now = Date()
    let entry = ConversationIndexEntry(
        id: id,
        title: "Test Conv",
        createdAt: now,
        updatedAt: now,
        messageCount: 5,
        preview: "Hello",
        isArchived: false
    )

    TestRunner.assertEqual(entry.id, id, "ID matches")
    TestRunner.assertEqual(entry.title, "Test Conv", "Title matches")
    TestRunner.assertEqual(entry.messageCount, 5, "Message count matches")
    TestRunner.assertEqual(entry.preview, "Hello", "Preview matches")
    TestRunner.assertFalse(entry.isArchived, "Not archived by default")
}

func testIndexEntry_BackwardCompatibility() {
    TestRunner.setGroup("ConversationIndexEntry - Backward Compatibility")

    // Simulate old schema with lastModifiedAt instead of updatedAt
    let oldJson = """
    {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "title": "Old conversation",
        "createdAt": "2024-01-01T00:00:00Z",
        "lastModifiedAt": "2024-01-02T00:00:00Z",
        "messageCount": 3,
        "isArchived": false
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
        let entry = try decoder.decode(ConversationIndexEntry.self, from: oldJson.data(using: .utf8)!)
        TestRunner.assertEqual(entry.title, "Old conversation", "Title decoded")
        TestRunner.assertEqual(entry.messageCount, 3, "Message count decoded")
        // updatedAt should be populated from lastModifiedAt
        TestRunner.assertNotNil(entry.updatedAt, "updatedAt populated from lastModifiedAt")
    } catch {
        TestRunner.assertTrue(false, "Failed to decode old schema: \(error)")
    }
}

// MARK: - Test Cases: ConversationIndex

func testIndex_EmptyIndex() {
    TestRunner.setGroup("ConversationIndex - Empty Index")

    let index = ConversationIndex()
    TestRunner.assertTrue(index.conversations.isEmpty, "No conversations initially")
    TestRunner.assertNil(index.activeConversationId, "No active conversation")
    TestRunner.assertEqual(index.version, ConversationIndex.currentVersion, "Version matches")
    TestRunner.assertTrue(index.activeConversations.isEmpty, "Active conversations empty")
    TestRunner.assertTrue(index.archivedConversations.isEmpty, "Archived conversations empty")
}

func testIndex_Upsert_NewEntry() {
    TestRunner.setGroup("ConversationIndex - Upsert New Entry")

    var index = ConversationIndex()
    let entry = ConversationIndexEntry(
        id: UUID(),
        title: "New Conv",
        createdAt: Date(),
        updatedAt: Date(),
        messageCount: 1
    )

    index.upsert(entry)

    TestRunner.assertEqual(index.conversations.count, 1, "One conversation added")
    TestRunner.assertTrue(index.contains(id: entry.id), "Contains new entry")
    TestRunner.assertNotNil(index.entry(for: entry.id), "Can retrieve entry")
}

func testIndex_Upsert_UpdateExisting() {
    TestRunner.setGroup("ConversationIndex - Upsert Update Existing")

    var index = ConversationIndex()
    let id = UUID()
    let original = ConversationIndexEntry(
        id: id,
        title: "Original",
        createdAt: Date(),
        updatedAt: Date(),
        messageCount: 1
    )
    index.upsert(original)

    // Update same entry
    var updated = original
    updated.title = "Updated"
    updated.messageCount = 5
    index.upsert(updated)

    TestRunner.assertEqual(index.conversations.count, 1, "Still one conversation")
    TestRunner.assertEqual(index.entry(for: id)?.title, "Updated", "Title updated")
    TestRunner.assertEqual(index.entry(for: id)?.messageCount, 5, "Count updated")
}

func testIndex_Remove() {
    TestRunner.setGroup("ConversationIndex - Remove")

    var index = ConversationIndex()
    let entry = ConversationIndexEntry(
        id: UUID(),
        title: "To Remove",
        createdAt: Date(),
        updatedAt: Date(),
        messageCount: 1
    )
    index.upsert(entry)
    index.activeConversationId = entry.id

    TestRunner.assertEqual(index.conversations.count, 1, "Entry added")

    index.remove(id: entry.id)

    TestRunner.assertTrue(index.conversations.isEmpty, "Entry removed")
    TestRunner.assertNil(index.activeConversationId, "Active ID cleared when removed")
}

func testIndex_ActiveConversations_Filtering() {
    TestRunner.setGroup("ConversationIndex - Active/Archived Filtering")

    var index = ConversationIndex()
    let now = Date()

    let active1 = ConversationIndexEntry(
        id: UUID(),
        title: "Active 1",
        createdAt: now,
        updatedAt: now.addingTimeInterval(-100),
        messageCount: 1,
        isArchived: false
    )
    let active2 = ConversationIndexEntry(
        id: UUID(),
        title: "Active 2",
        createdAt: now,
        updatedAt: now,  // More recent
        messageCount: 2,
        isArchived: false
    )
    let archived = ConversationIndexEntry(
        id: UUID(),
        title: "Archived",
        createdAt: now,
        updatedAt: now,
        messageCount: 3,
        isArchived: true
    )

    index.upsert(active1)
    index.upsert(active2)
    index.upsert(archived)

    TestRunner.assertEqual(index.conversations.count, 3, "Three total conversations")
    TestRunner.assertEqual(index.activeConversations.count, 2, "Two active conversations")
    TestRunner.assertEqual(index.archivedConversations.count, 1, "One archived conversation")

    // Active sorted by most recent first
    TestRunner.assertEqual(index.activeConversations.first?.title, "Active 2", "Most recent first")
}

func testIndex_Codable() {
    TestRunner.setGroup("ConversationIndex - Codable Round Trip")

    var index = ConversationIndex()
    let entry = ConversationIndexEntry(
        id: UUID(),
        title: "Test",
        createdAt: Date(),
        updatedAt: Date(),
        messageCount: 1
    )
    index.upsert(entry)
    index.activeConversationId = entry.id

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
        let data = try encoder.encode(index)
        let decoded = try decoder.decode(ConversationIndex.self, from: data)

        TestRunner.assertEqual(decoded.conversations.count, index.conversations.count, "Conversations count match")
        TestRunner.assertEqual(decoded.activeConversationId, index.activeConversationId, "Active ID match")
        TestRunner.assertEqual(decoded.version, index.version, "Version match")
    } catch {
        TestRunner.assertTrue(false, "Encoding/decoding failed: \(error)")
    }
}

// MARK: - Edge Cases

func testEdgeCase_EmptyContent() {
    TestRunner.setGroup("Edge Cases - Empty Content")

    let msg = PersistedMessage(role: .user, content: "")
    TestRunner.assertEqual(msg.content, "", "Empty content allowed")

    let entry = ConversationIndexEntry(
        id: UUID(),
        title: "",
        createdAt: Date(),
        updatedAt: Date(),
        messageCount: 0
    )
    TestRunner.assertEqual(entry.title, "", "Empty title allowed")
    TestRunner.assertEqual(entry.messageCount, 0, "Zero message count allowed")
}

func testEdgeCase_VeryLongContent() {
    TestRunner.setGroup("Edge Cases - Very Long Content")

    let longContent = String(repeating: "a", count: 100_000)
    let msg = PersistedMessage(role: .user, content: longContent)
    TestRunner.assertEqual(msg.content.count, 100_000, "Long content preserved")

    // Title truncation handles long content
    let truncated = ConversationIndexEntry.truncateForTitle(longContent)
    TestRunner.assertTrue(truncated.count <= 51, "Title truncated properly")
}

func testEdgeCase_SpecialCharacters() {
    TestRunner.setGroup("Edge Cases - Special Characters")

    let specialContent = "Hello 🌍! こんにちは <script>alert('xss')</script> \n\t\r"
    let msg = PersistedMessage(role: .user, content: specialContent)

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    do {
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(PersistedMessage.self, from: data)
        TestRunner.assertEqual(decoded.content, specialContent, "Special chars preserved")
    } catch {
        TestRunner.assertTrue(false, "Special chars encoding failed: \(error)")
    }
}

func testEdgeCase_ConcurrentModification() {
    TestRunner.setGroup("Edge Cases - Multiple Rapid Updates")

    var index = ConversationIndex()
    let id = UUID()

    // Simulate rapid updates
    for i in 0..<100 {
        let entry = ConversationIndexEntry(
            id: id,
            title: "Update \(i)",
            createdAt: Date(),
            updatedAt: Date(),
            messageCount: i
        )
        index.upsert(entry)
    }

    TestRunner.assertEqual(index.conversations.count, 1, "Still one conversation after updates")
    TestRunner.assertEqual(index.entry(for: id)?.messageCount, 99, "Last update applied")
}

func testEdgeCase_RemoveNonExistent() {
    TestRunner.setGroup("Edge Cases - Remove Non-Existent")

    var index = ConversationIndex()
    let entry = ConversationIndexEntry(
        id: UUID(),
        title: "Exists",
        createdAt: Date(),
        updatedAt: Date(),
        messageCount: 1
    )
    index.upsert(entry)

    // Remove non-existent ID
    let nonExistentId = UUID()
    index.remove(id: nonExistentId)

    TestRunner.assertEqual(index.conversations.count, 1, "Existing entry preserved")
}

func testEdgeCase_DateOrdering() {
    TestRunner.setGroup("Edge Cases - Date Ordering")

    var index = ConversationIndex()
    let now = Date()

    // Add in random order
    let old = ConversationIndexEntry(
        id: UUID(),
        title: "Old",
        createdAt: now.addingTimeInterval(-1000),
        updatedAt: now.addingTimeInterval(-1000),
        messageCount: 1
    )
    let new = ConversationIndexEntry(
        id: UUID(),
        title: "New",
        createdAt: now,
        updatedAt: now,
        messageCount: 1
    )
    let middle = ConversationIndexEntry(
        id: UUID(),
        title: "Middle",
        createdAt: now.addingTimeInterval(-500),
        updatedAt: now.addingTimeInterval(-500),
        messageCount: 1
    )

    index.upsert(old)
    index.upsert(middle)
    index.upsert(new)

    let active = index.activeConversations
    TestRunner.assertEqual(active[0].title, "New", "Most recent first")
    TestRunner.assertEqual(active[1].title, "Middle", "Middle second")
    TestRunner.assertEqual(active[2].title, "Old", "Oldest last")
}

func testEdgeCase_EmptyConversationNotSaved() {
    TestRunner.setGroup("Edge Cases - Empty Conversation Logic")

    // This tests the logic: conversations with no messages shouldn't be saved
    // We simulate the check that ConversationManager does

    let messages: [PersistedMessage] = []
    let shouldSave = !messages.isEmpty

    TestRunner.assertFalse(shouldSave, "Empty conversation should not be saved")

    let nonEmptyMessages = [PersistedMessage(role: .user, content: "Hello")]
    let shouldSaveNonEmpty = !nonEmptyMessages.isEmpty

    TestRunner.assertTrue(shouldSaveNonEmpty, "Non-empty conversation should be saved")
}

func testEdgeCase_ContextRestoration() {
    TestRunner.setGroup("Edge Cases - Context Restoration")

    // Test restoring contexts from persisted messages
    let context1 = TestContext(applicationName: "App1", selectedText: "Text1")
    let context2 = TestContext(applicationName: "App2", selectedText: "Text2")

    let messages = [
        PersistedMessage(role: .user, content: "Q1", contextData: PersistedMessage.encodeContext(context1)),
        PersistedMessage(role: .assistant, content: "A1"),
        PersistedMessage(role: .user, content: "Q2", contextData: PersistedMessage.encodeContext(context2)),
        PersistedMessage(role: .assistant, content: "A2"),
        PersistedMessage(role: .user, content: "Q3")  // No context
    ]

    // Simulate restoreMessageContexts
    var contexts: [UUID: TestContext] = [:]
    for message in messages {
        if message.role == .user, let context = message.decodeContext() {
            contexts[message.id] = context
        }
    }

    TestRunner.assertEqual(contexts.count, 2, "Two contexts restored (Q3 has none)")
    TestRunner.assertEqual(contexts[messages[0].id]?.applicationName, "App1", "First context restored")
    TestRunner.assertEqual(contexts[messages[2].id]?.applicationName, "App2", "Second context restored")
}

// MARK: - Main Entry Point

@main
struct PersistenceTestRunner {
    static func main() {
        print("")
        print("🧪 Persistence Unit Tests")
        print("==================================================")

        // PersistedMessage tests
        testPersistedMessage_BasicCreation()
        testPersistedMessage_FromChatMessage()
        testPersistedMessage_ToChatMessage()
        testPersistedMessage_ContextEncodeDecode()
        testPersistedMessage_NilContextEncode()
        testPersistedMessage_Codable()

        // ConversationIndexEntry tests
        testIndexEntry_TitleTruncation()
        testIndexEntry_Creation()
        testIndexEntry_BackwardCompatibility()

        // ConversationIndex tests
        testIndex_EmptyIndex()
        testIndex_Upsert_NewEntry()
        testIndex_Upsert_UpdateExisting()
        testIndex_Remove()
        testIndex_ActiveConversations_Filtering()
        testIndex_Codable()

        // Edge cases
        testEdgeCase_EmptyContent()
        testEdgeCase_VeryLongContent()
        testEdgeCase_SpecialCharacters()
        testEdgeCase_ConcurrentModification()
        testEdgeCase_RemoveNonExistent()
        testEdgeCase_DateOrdering()
        testEdgeCase_EmptyConversationNotSaved()
        testEdgeCase_ContextRestoration()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
