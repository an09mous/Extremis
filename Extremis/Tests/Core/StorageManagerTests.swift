// MARK: - Storage Manager Unit Tests
// Tests for file-based persistence with actual disk operations
// Uses a temporary directory to avoid polluting real storage

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
            let message = "Expected nil but got value"
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

// MARK: - Inline Types

enum ChatRole: String, Codable, Equatable {
    case system, user, assistant
}

struct PersistedMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    let contextData: Data?

    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date(), contextData: Data? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextData = contextData
    }
}

struct ConversationSummary: Codable, Equatable {
    let content: String
    let coversMessageCount: Int
    let createdAt: Date
    var isValid: Bool { !content.isEmpty && coversMessageCount > 0 }
}

struct PersistedConversation: Codable, Identifiable, Equatable {
    let id: UUID
    let version: Int
    var messages: [PersistedMessage]
    let initialRequest: String?
    let maxMessages: Int
    let createdAt: Date
    var updatedAt: Date
    var title: String?
    var isArchived: Bool
    var summary: ConversationSummary?

    static let currentVersion = 1

    init(
        id: UUID = UUID(),
        version: Int = Self.currentVersion,
        messages: [PersistedMessage] = [],
        initialRequest: String? = nil,
        maxMessages: Int = 20,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String? = nil,
        isArchived: Bool = false,
        summary: ConversationSummary? = nil
    ) {
        self.id = id
        self.version = version
        self.messages = messages
        self.initialRequest = initialRequest
        self.maxMessages = maxMessages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.isArchived = isArchived
        self.summary = summary
    }
}

struct ConversationIndexEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var preview: String?
    var isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, messageCount, preview, isArchived, lastModifiedAt
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

    init(id: UUID, title: String, createdAt: Date, updatedAt: Date, messageCount: Int, preview: String? = nil, isArchived: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.preview = preview
        self.isArchived = isArchived
    }

    init(from conversation: PersistedConversation) {
        self.id = conversation.id
        self.title = conversation.title ?? conversation.messages.first?.content.prefix(50).description ?? "New Conversation"
        self.createdAt = conversation.createdAt
        self.updatedAt = conversation.updatedAt
        self.messageCount = conversation.messages.count
        self.preview = conversation.messages.first(where: { $0.role == .user })?.content.prefix(100).description
        self.isArchived = conversation.isArchived
    }
}

struct ConversationIndex: Codable, Equatable {
    let version: Int
    var conversations: [ConversationIndexEntry]
    var activeConversationId: UUID?
    var lastUpdated: Date

    static let currentVersion = 1

    init(version: Int = Self.currentVersion, conversations: [ConversationIndexEntry] = [], activeConversationId: UUID? = nil, lastUpdated: Date = Date()) {
        self.version = version
        self.conversations = conversations
        self.activeConversationId = activeConversationId
        self.lastUpdated = lastUpdated
    }

    var activeConversations: [ConversationIndexEntry] {
        conversations.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }
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
        if activeConversationId == id { activeConversationId = nil }
        lastUpdated = Date()
    }
}

enum StorageError: Error {
    case directoryCreationFailed, fileWriteFailed, fileReadFailed, conversationNotFound
}

// MARK: - Test Storage Manager (uses temp directory)

class TestStorageManager {
    private let testDir: URL
    private let conversationsDir: URL
    private let indexURL: URL
    private var cachedIndex: ConversationIndex?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtremisTests")
            .appendingPathComponent(UUID().uuidString)
        conversationsDir = testDir.appendingPathComponent("conversations")
        indexURL = conversationsDir.appendingPathComponent("index.json")

        try FileManager.default.createDirectory(at: conversationsDir, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: testDir)
    }

    func conversationFileURL(id: UUID) -> URL {
        conversationsDir.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Index Operations

    func loadIndex() throws -> ConversationIndex {
        if let cached = cachedIndex { return cached }

        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            let empty = ConversationIndex()
            cachedIndex = empty
            return empty
        }

        let data = try Data(contentsOf: indexURL)
        let index = try decoder.decode(ConversationIndex.self, from: data)
        cachedIndex = index
        return index
    }

    func saveIndex(_ index: ConversationIndex) throws {
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
        cachedIndex = index
    }

    func invalidateIndexCache() {
        cachedIndex = nil
    }

    // MARK: - Conversation Operations

    func saveConversation(_ conversation: PersistedConversation) throws {
        let fileURL = conversationFileURL(id: conversation.id)
        let data = try encoder.encode(conversation)
        try data.write(to: fileURL, options: .atomic)

        var index = try loadIndex()
        let entry = ConversationIndexEntry(from: conversation)
        index.upsert(entry)
        try saveIndex(index)
    }

    func loadConversation(id: UUID) throws -> PersistedConversation? {
        let fileURL = conversationFileURL(id: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(PersistedConversation.self, from: data)
    }

    func deleteConversation(id: UUID) throws {
        let fileURL = conversationFileURL(id: id)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        var index = try loadIndex()
        index.remove(id: id)
        try saveIndex(index)
    }

    func conversationExists(id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: conversationFileURL(id: id).path)
    }

    func listConversations() throws -> [ConversationIndexEntry] {
        try loadIndex().activeConversations
    }

    func setActiveConversation(id: UUID?) throws {
        var index = try loadIndex()
        index.activeConversationId = id
        index.lastUpdated = Date()
        try saveIndex(index)
    }

    func getActiveConversationId() throws -> UUID? {
        try loadIndex().activeConversationId
    }
}

// MARK: - Test Cases

var testStorage: TestStorageManager!

func setupTestStorage() {
    do {
        testStorage = try TestStorageManager()
    } catch {
        print("Failed to setup test storage: \(error)")
        exit(1)
    }
}

func teardownTestStorage() {
    testStorage?.cleanup()
    testStorage = nil
}

func testStorage_SaveAndLoadConversation() {
    TestRunner.setGroup("StorageManager - Save and Load Conversation")
    setupTestStorage()

    let conv = PersistedConversation(
        id: UUID(),
        messages: [
            PersistedMessage(role: .user, content: "Hello"),
            PersistedMessage(role: .assistant, content: "Hi there!")
        ],
        title: "Test Conversation"
    )

    do {
        try testStorage.saveConversation(conv)
        TestRunner.assertTrue(testStorage.conversationExists(id: conv.id), "Conversation file exists")

        let loaded = try testStorage.loadConversation(id: conv.id)
        TestRunner.assertNotNil(loaded, "Conversation loaded")
        TestRunner.assertEqual(loaded?.id, conv.id, "ID matches")
        TestRunner.assertEqual(loaded?.messages.count, 2, "Message count matches")
        TestRunner.assertEqual(loaded?.messages[0].content, "Hello", "First message content")
        TestRunner.assertEqual(loaded?.title, "Test Conversation", "Title matches")
    } catch {
        TestRunner.assertTrue(false, "Save/load failed: \(error)")
    }

    teardownTestStorage()
}

func testStorage_LoadNonExistent() {
    TestRunner.setGroup("StorageManager - Load Non-Existent")
    setupTestStorage()

    do {
        let loaded = try testStorage.loadConversation(id: UUID())
        TestRunner.assertNil(loaded, "Returns nil for non-existent conversation")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }

    teardownTestStorage()
}

func testStorage_DeleteConversation() {
    TestRunner.setGroup("StorageManager - Delete Conversation")
    setupTestStorage()

    let conv = PersistedConversation(
        id: UUID(),
        messages: [PersistedMessage(role: .user, content: "To delete")]
    )

    do {
        try testStorage.saveConversation(conv)
        TestRunner.assertTrue(testStorage.conversationExists(id: conv.id), "Exists before delete")

        try testStorage.deleteConversation(id: conv.id)
        TestRunner.assertFalse(testStorage.conversationExists(id: conv.id), "Deleted from disk")

        let index = try testStorage.loadIndex()
        let entry = index.conversations.first { $0.id == conv.id }
        TestRunner.assertNil(entry, "Removed from index")
    } catch {
        TestRunner.assertTrue(false, "Delete failed: \(error)")
    }

    teardownTestStorage()
}

func testStorage_IndexUpdatesOnSave() {
    TestRunner.setGroup("StorageManager - Index Updates on Save")
    setupTestStorage()

    do {
        let conv1 = PersistedConversation(id: UUID(), messages: [PersistedMessage(role: .user, content: "First")])
        let conv2 = PersistedConversation(id: UUID(), messages: [PersistedMessage(role: .user, content: "Second")])

        try testStorage.saveConversation(conv1)
        try testStorage.saveConversation(conv2)

        let list = try testStorage.listConversations()
        TestRunner.assertEqual(list.count, 2, "Two conversations in index")
    } catch {
        TestRunner.assertTrue(false, "Index update failed: \(error)")
    }

    teardownTestStorage()
}

func testStorage_ActiveConversation() {
    TestRunner.setGroup("StorageManager - Active Conversation")
    setupTestStorage()

    let convId = UUID()
    let conv = PersistedConversation(id: convId, messages: [PersistedMessage(role: .user, content: "Active")])

    do {
        try testStorage.saveConversation(conv)
        try testStorage.setActiveConversation(id: convId)

        let activeId = try testStorage.getActiveConversationId()
        TestRunner.assertEqual(activeId, convId, "Active ID set correctly")

        // Clear active
        try testStorage.setActiveConversation(id: nil)
        let clearedId = try testStorage.getActiveConversationId()
        TestRunner.assertNil(clearedId, "Active ID cleared")
    } catch {
        TestRunner.assertTrue(false, "Active conversation failed: \(error)")
    }

    teardownTestStorage()
}

func testStorage_IndexCache() {
    TestRunner.setGroup("StorageManager - Index Cache")
    setupTestStorage()

    do {
        let conv = PersistedConversation(id: UUID(), messages: [PersistedMessage(role: .user, content: "Cache test")])
        try testStorage.saveConversation(conv)

        // First load - from disk
        let index1 = try testStorage.loadIndex()
        TestRunner.assertEqual(index1.conversations.count, 1, "One conversation")

        // Second load - should be from cache (same result)
        let index2 = try testStorage.loadIndex()
        TestRunner.assertEqual(index2.conversations.count, 1, "Still one (cached)")

        // Invalidate cache
        testStorage.invalidateIndexCache()

        // Third load - from disk again
        let index3 = try testStorage.loadIndex()
        TestRunner.assertEqual(index3.conversations.count, 1, "Still one (reloaded)")
    } catch {
        TestRunner.assertTrue(false, "Cache test failed: \(error)")
    }

    teardownTestStorage()
}

func testStorage_UpdateExistingConversation() {
    TestRunner.setGroup("StorageManager - Update Existing Conversation")
    setupTestStorage()

    let convId = UUID()

    do {
        // Create initial
        var conv = PersistedConversation(
            id: convId,
            messages: [PersistedMessage(role: .user, content: "Initial")],
            title: "Original Title"
        )
        try testStorage.saveConversation(conv)

        // Update
        conv.messages.append(PersistedMessage(role: .assistant, content: "Response"))
        conv.title = "Updated Title"
        conv.updatedAt = Date()
        try testStorage.saveConversation(conv)

        // Verify
        let loaded = try testStorage.loadConversation(id: convId)
        TestRunner.assertEqual(loaded?.messages.count, 2, "Messages updated")
        TestRunner.assertEqual(loaded?.title, "Updated Title", "Title updated")

        // Index should still have one entry
        let list = try testStorage.listConversations()
        TestRunner.assertEqual(list.count, 1, "Still one conversation in index")
    } catch {
        TestRunner.assertTrue(false, "Update failed: \(error)")
    }

    teardownTestStorage()
}

func testStorage_AtomicWrites() {
    TestRunner.setGroup("StorageManager - Atomic Writes")
    setupTestStorage()

    // Test that even large conversations are written atomically
    let convId = UUID()
    var messages: [PersistedMessage] = []
    for i in 0..<1000 {
        messages.append(PersistedMessage(role: i % 2 == 0 ? .user : .assistant, content: "Message \(i) with some content"))
    }

    let conv = PersistedConversation(id: convId, messages: messages)

    do {
        try testStorage.saveConversation(conv)
        let loaded = try testStorage.loadConversation(id: convId)
        TestRunner.assertEqual(loaded?.messages.count, 1000, "All 1000 messages saved and loaded")
    } catch {
        TestRunner.assertTrue(false, "Large write failed: \(error)")
    }

    teardownTestStorage()
}

func testStorage_ActiveConversationClearedOnDelete() {
    TestRunner.setGroup("StorageManager - Active Cleared on Delete")
    setupTestStorage()

    let convId = UUID()
    let conv = PersistedConversation(id: convId, messages: [PersistedMessage(role: .user, content: "Active then deleted")])

    do {
        try testStorage.saveConversation(conv)
        try testStorage.setActiveConversation(id: convId)

        TestRunner.assertEqual(try testStorage.getActiveConversationId(), convId, "Active set")

        try testStorage.deleteConversation(id: convId)

        TestRunner.assertNil(try testStorage.getActiveConversationId(), "Active cleared after delete")
    } catch {
        TestRunner.assertTrue(false, "Test failed: \(error)")
    }

    teardownTestStorage()
}

func testStorage_MultipleConversationsSorting() {
    TestRunner.setGroup("StorageManager - Multiple Conversations Sorting")
    setupTestStorage()

    do {
        let now = Date()

        // Create conversations with different timestamps
        let old = PersistedConversation(
            id: UUID(),
            messages: [PersistedMessage(role: .user, content: "Old")],
            createdAt: now.addingTimeInterval(-1000),
            updatedAt: now.addingTimeInterval(-1000)
        )
        let new = PersistedConversation(
            id: UUID(),
            messages: [PersistedMessage(role: .user, content: "New")],
            createdAt: now,
            updatedAt: now
        )
        let middle = PersistedConversation(
            id: UUID(),
            messages: [PersistedMessage(role: .user, content: "Middle")],
            createdAt: now.addingTimeInterval(-500),
            updatedAt: now.addingTimeInterval(-500)
        )

        // Save in random order
        try testStorage.saveConversation(middle)
        try testStorage.saveConversation(old)
        try testStorage.saveConversation(new)

        // List should be sorted by updatedAt descending
        let list = try testStorage.listConversations()
        TestRunner.assertEqual(list.count, 3, "Three conversations")
        TestRunner.assertEqual(list[0].preview, "New", "Most recent first")
        TestRunner.assertEqual(list[1].preview, "Middle", "Middle second")
        TestRunner.assertEqual(list[2].preview, "Old", "Oldest last")
    } catch {
        TestRunner.assertTrue(false, "Sorting test failed: \(error)")
    }

    teardownTestStorage()
}

func testStorage_EmptyConversation() {
    TestRunner.setGroup("StorageManager - Empty Conversation Handling")
    setupTestStorage()

    // Empty conversations CAN be saved at storage level
    // The ConversationManager prevents this, but storage layer allows it
    let conv = PersistedConversation(id: UUID(), messages: [])

    do {
        try testStorage.saveConversation(conv)
        let loaded = try testStorage.loadConversation(id: conv.id)
        TestRunner.assertNotNil(loaded, "Empty conversation can be saved")
        TestRunner.assertEqual(loaded?.messages.count, 0, "Zero messages")

        let list = try testStorage.listConversations()
        TestRunner.assertEqual(list[0].messageCount, 0, "Index shows zero messages")
    } catch {
        TestRunner.assertTrue(false, "Empty conversation test failed: \(error)")
    }

    teardownTestStorage()
}

func testStorage_CorruptedFile() {
    TestRunner.setGroup("StorageManager - Corrupted File Handling")
    setupTestStorage()

    let convId = UUID()
    let fileURL = testStorage.conversationFileURL(id: convId)

    do {
        // Write corrupted JSON
        let corruptedData = "{ invalid json }".data(using: .utf8)!
        try corruptedData.write(to: fileURL, options: .atomic)

        // Try to load
        do {
            _ = try testStorage.loadConversation(id: convId)
            TestRunner.assertTrue(false, "Should have thrown for corrupted file")
        } catch {
            TestRunner.assertTrue(true, "Throws for corrupted file")
        }
    } catch {
        TestRunner.assertTrue(false, "Setup failed: \(error)")
    }

    teardownTestStorage()
}

// MARK: - Main Entry Point

@main
struct StorageManagerTestRunner {
    static func main() {
        print("")
        print("🧪 Storage Manager Unit Tests")
        print("==================================================")

        testStorage_SaveAndLoadConversation()
        testStorage_LoadNonExistent()
        testStorage_DeleteConversation()
        testStorage_IndexUpdatesOnSave()
        testStorage_ActiveConversation()
        testStorage_IndexCache()
        testStorage_UpdateExistingConversation()
        testStorage_AtomicWrites()
        testStorage_ActiveConversationClearedOnDelete()
        testStorage_MultipleConversationsSorting()
        testStorage_EmptyConversation()
        testStorage_CorruptedFile()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
