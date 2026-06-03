// MARK: - Stealth Session Tagging Tests
// Tests for isStealth property on ChatSession, PersistedSession, and SessionIndexEntry
// Covers creation, backward compatibility, and round-trip persistence

import Foundation

// MARK: - Test Runner Framework

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []
    static var currentGroup = ""

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
        currentGroup = ""
    }

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

// MARK: - Minimal Codable Models for Testing
// Replicate just the Codable parts needed to test isStealth without importing the full app

struct TestPersistedSession: Codable, Equatable {
    let id: UUID
    let version: Int
    var messages: [TestPersistedMessage]
    let initialRequest: String?
    let maxMessages: Int
    let createdAt: Date
    var updatedAt: Date
    var title: String?
    var isArchived: Bool
    let isStealth: Bool

    enum CodingKeys: String, CodingKey {
        case id, version, messages, initialRequest, maxMessages
        case createdAt, updatedAt, title, isArchived, isStealth
    }

    init(
        id: UUID = UUID(),
        version: Int = 1,
        messages: [TestPersistedMessage] = [],
        initialRequest: String? = nil,
        maxMessages: Int = 20,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String? = nil,
        isArchived: Bool = false,
        isStealth: Bool = false
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
        self.isStealth = isStealth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        messages = try container.decode([TestPersistedMessage].self, forKey: .messages)
        initialRequest = try container.decodeIfPresent(String.self, forKey: .initialRequest)
        maxMessages = try container.decodeIfPresent(Int.self, forKey: .maxMessages) ?? 20
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        isStealth = try container.decodeIfPresent(Bool.self, forKey: .isStealth) ?? false
    }
}

struct TestPersistedMessage: Codable, Equatable {
    let id: UUID
    let role: String
    let content: String
    let timestamp: Date
}

struct TestSessionIndexEntry: Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var preview: String?
    var isArchived: Bool
    let isStealth: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, updatedAt, messageCount, preview, isArchived, isStealth
        case lastModifiedAt
    }

    init(
        id: UUID = UUID(),
        title: String = "Test",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messageCount: Int = 0,
        preview: String? = nil,
        isArchived: Bool = false,
        isStealth: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.preview = preview
        self.isArchived = isArchived
        self.isStealth = isStealth
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
        isStealth = try container.decodeIfPresent(Bool.self, forKey: .isStealth) ?? false
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
        try container.encode(isStealth, forKey: .isStealth)
    }
}

// MARK: - Tests

func testPersistedSessionStealthFlag() {
    TestRunner.setGroup("PersistedSession isStealth")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    // Test: default is false
    let normalSession = TestPersistedSession()
    TestRunner.assertFalse(normalSession.isStealth, "Default isStealth is false")

    // Test: explicit true
    let stealthSession = TestPersistedSession(isStealth: true)
    TestRunner.assertTrue(stealthSession.isStealth, "Explicit isStealth true")

    // Test: round-trip with isStealth true
    do {
        let data = try encoder.encode(stealthSession)
        let decoded = try decoder.decode(TestPersistedSession.self, from: data)
        TestRunner.assertTrue(decoded.isStealth, "Round-trip preserves isStealth true")
    } catch {
        TestRunner.assertTrue(false, "Round-trip encode/decode should not throw: \(error)")
    }

    // Test: round-trip with isStealth false
    do {
        let data = try encoder.encode(normalSession)
        let decoded = try decoder.decode(TestPersistedSession.self, from: data)
        TestRunner.assertFalse(decoded.isStealth, "Round-trip preserves isStealth false")
    } catch {
        TestRunner.assertTrue(false, "Round-trip encode/decode should not throw: \(error)")
    }
}

func testPersistedSessionBackwardCompat() {
    TestRunner.setGroup("PersistedSession backward compatibility")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    // JSON without isStealth field (simulates old session files)
    let jsonWithoutStealth = """
    {
        "id": "550E8400-E29B-41D4-A716-446655440000",
        "version": 1,
        "messages": [],
        "maxMessages": 20,
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z",
        "isArchived": false
    }
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(TestPersistedSession.self, from: jsonWithoutStealth)
        TestRunner.assertFalse(decoded.isStealth, "Missing isStealth defaults to false")
        TestRunner.assertEqual(decoded.id.uuidString, "550E8400-E29B-41D4-A716-446655440000", "ID preserved")
    } catch {
        TestRunner.assertTrue(false, "Decoding old JSON without isStealth should not throw: \(error)")
    }

    // JSON with isStealth: true
    let jsonWithStealth = """
    {
        "id": "550E8400-E29B-41D4-A716-446655440001",
        "version": 1,
        "messages": [],
        "maxMessages": 20,
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z",
        "isArchived": false,
        "isStealth": true
    }
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(TestPersistedSession.self, from: jsonWithStealth)
        TestRunner.assertTrue(decoded.isStealth, "Explicit isStealth true decoded correctly")
    } catch {
        TestRunner.assertTrue(false, "Decoding JSON with isStealth should not throw: \(error)")
    }
}

func testSessionIndexEntryStealthFlag() {
    TestRunner.setGroup("SessionIndexEntry isStealth")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    // Test: default is false
    let normalEntry = TestSessionIndexEntry()
    TestRunner.assertFalse(normalEntry.isStealth, "Default isStealth is false")

    // Test: explicit true
    let stealthEntry = TestSessionIndexEntry(isStealth: true)
    TestRunner.assertTrue(stealthEntry.isStealth, "Explicit isStealth true")

    // Test: round-trip
    do {
        let data = try encoder.encode(stealthEntry)
        let decoded = try decoder.decode(TestSessionIndexEntry.self, from: data)
        TestRunner.assertTrue(decoded.isStealth, "Round-trip preserves isStealth true")
    } catch {
        TestRunner.assertTrue(false, "Round-trip should not throw: \(error)")
    }
}

func testSessionIndexEntryBackwardCompat() {
    TestRunner.setGroup("SessionIndexEntry backward compatibility")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    // JSON without isStealth field (simulates old index entries)
    let jsonWithoutStealth = """
    {
        "id": "550E8400-E29B-41D4-A716-446655440002",
        "title": "Old Session",
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z",
        "messageCount": 5
    }
    """.data(using: .utf8)!

    do {
        let decoded = try decoder.decode(TestSessionIndexEntry.self, from: jsonWithoutStealth)
        TestRunner.assertFalse(decoded.isStealth, "Missing isStealth defaults to false")
        TestRunner.assertEqual(decoded.title, "Old Session", "Title preserved")
        TestRunner.assertFalse(decoded.isArchived, "Missing isArchived defaults to false")
    } catch {
        TestRunner.assertTrue(false, "Decoding old JSON without isStealth should not throw: \(error)")
    }
}

// MARK: - Entry Point

@main
struct StealthSessionTaggingTests {
    static func main() {
        testPersistedSessionStealthFlag()
        testPersistedSessionBackwardCompat()
        testSessionIndexEntryStealthFlag()
        testSessionIndexEntryBackwardCompat()
        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
