// MARK: - Command Storage Tests
// Tests for CommandStorage persistence operations

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

// MARK: - Command Model (Inline for Standalone Test)

struct Command: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var description: String?
    var promptTemplate: String
    var icon: String?
    var isPinned: Bool
    var usageCount: Int
    var lastUsedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        promptTemplate: String,
        icon: String? = nil,
        isPinned: Bool = false,
        usageCount: Int = 0,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.promptTemplate = promptTemplate
        self.icon = icon
        self.isPinned = isPinned
        self.usageCount = usageCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayIcon: String {
        icon ?? "command"
    }

    func withRecordedUsage() -> Command {
        var copy = self
        copy.usageCount += 1
        copy.lastUsedAt = Date()
        return copy
    }

    func withUpdatedTimestamp() -> Command {
        var copy = self
        copy.updatedAt = Date()
        return copy
    }
}

// MARK: - CommandConfigFile (Inline for Standalone Test)

struct CommandConfigFile: Codable, Equatable {
    var version: Int
    var commands: [Command]
    var pinnedOrder: [UUID]

    static let currentVersion = 1
    static let maxPinnedCommands = 5

    static let empty = CommandConfigFile(
        version: currentVersion,
        commands: [],
        pinnedOrder: []
    )

    init(version: Int = currentVersion, commands: [Command] = [], pinnedOrder: [UUID] = []) {
        self.version = version
        self.commands = commands
        self.pinnedOrder = pinnedOrder
    }

    mutating func addCommand(_ command: Command) {
        commands.append(command)
        if command.isPinned && pinnedOrder.count < Self.maxPinnedCommands {
            pinnedOrder.append(command.id)
        }
    }

    mutating func updateCommand(_ command: Command) {
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        let wasUpdated = command.withUpdatedTimestamp()
        commands[index] = wasUpdated

        let wasPinned = pinnedOrder.contains(command.id)
        if command.isPinned && !wasPinned {
            if pinnedOrder.count < Self.maxPinnedCommands {
                pinnedOrder.append(command.id)
            }
        } else if !command.isPinned && wasPinned {
            pinnedOrder.removeAll { $0 == command.id }
        }
    }

    mutating func removeCommand(id: UUID) {
        commands.removeAll { $0.id == id }
        pinnedOrder.removeAll { $0 == id }
    }

    func command(id: UUID) -> Command? {
        commands.first { $0.id == id }
    }

    mutating func recordUsage(id: UUID) {
        guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[index] = commands[index].withRecordedUsage()
    }

    var pinnedCommands: [Command] {
        pinnedOrder.compactMap { id in
            commands.first { $0.id == id && $0.isPinned }
        }
    }

    var canPinMore: Bool {
        pinnedOrder.count < Self.maxPinnedCommands
    }

    /// Create config with default commands
    static func withDefaults() -> CommandConfigFile {
        var config = CommandConfigFile.empty

        let defaults = [
            Command(
                name: "Proofread",
                description: "Check grammar, spelling, and punctuation",
                promptTemplate: "Proofread the selected text for grammar, spelling, and punctuation. Please correct any errors while maintaining my original tone and style. If a sentence is particularly confusing, suggest a clearer alternative.",
                icon: "doc.text.magnifyingglass",
                isPinned: true
            ),
            Command(
                name: "Professionalize",
                description: "Make text more formal and professional",
                promptTemplate: "Rewrite the selected text to be more professional and formal. Ensure the tone is diplomatic, respectful and use more sophisticated vocabulary. Remove any slang, fillers, or overly casual phrasing while keeping the core message intact.",
                icon: "briefcase",
                isPinned: true
            ),
            Command(
                name: "Simplify",
                description: "Make text easier to understand",
                promptTemplate: "Simplify this text to make it clearer and easier to understand.",
                icon: "text.redaction",
                isPinned: true
            ),
            Command(
                name: "Explain Code",
                description: "Explain what this code does",
                promptTemplate: "Explain what this code does in simple terms.",
                icon: "questionmark.circle",
                isPinned: true
            )
        ]

        for cmd in defaults {
            config.addCommand(cmd)
        }

        return config
    }

    /// Migration from older versions
    static func migrate(from data: Data) throws -> CommandConfigFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Try to decode current version
        if let config = try? decoder.decode(CommandConfigFile.self, from: data) {
            return config
        }

        // Add migration logic for future versions here
        throw NSError(domain: "CommandConfigFile", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown format"])
    }
}

// MARK: - MockCommandStorage (In-memory implementation for testing)

class MockCommandStorage {
    private var storedData: Data?
    private(set) var saveCount = 0
    private(set) var loadCount = 0

    func save(_ config: CommandConfigFile) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        storedData = try encoder.encode(config)
        saveCount += 1
    }

    func load() throws -> CommandConfigFile {
        loadCount += 1
        guard let data = storedData else {
            // First launch - return defaults
            return CommandConfigFile.withDefaults()
        }
        return try CommandConfigFile.migrate(from: data)
    }

    func clear() {
        storedData = nil
        saveCount = 0
        loadCount = 0
    }
}

// MARK: - Storage Tests

func testStorage_FirstLaunchReturnsDefaults() {
    TestRunner.setGroup("Storage - First Launch Returns Defaults")

    let storage = MockCommandStorage()

    do {
        let config = try storage.load()

        TestRunner.assertEqual(config.version, CommandConfigFile.currentVersion, "Version is current")
        TestRunner.assertEqual(config.commands.count, 4, "Has 4 default commands")
        TestRunner.assertEqual(config.pinnedOrder.count, 4, "All 4 are pinned")

        // Check specific default commands exist
        let hasProofread = config.commands.contains { $0.name == "Proofread" }
        TestRunner.assertTrue(hasProofread, "Has 'Proofread' command")

        let hasProfessionalize = config.commands.contains { $0.name == "Professionalize" }
        TestRunner.assertTrue(hasProfessionalize, "Has 'Professionalize' command")

        let hasSimplify = config.commands.contains { $0.name == "Simplify" }
        TestRunner.assertTrue(hasSimplify, "Has 'Simplify' command")

        let hasExplainCode = config.commands.contains { $0.name == "Explain Code" }
        TestRunner.assertTrue(hasExplainCode, "Has 'Explain Code' command")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_SaveAndLoadRoundTrip() {
    TestRunner.setGroup("Storage - Save and Load Round Trip")

    let storage = MockCommandStorage()

    var config = CommandConfigFile.empty
    let command = Command(
        name: "Custom Command",
        description: "My custom command",
        promptTemplate: "Do something with {{CONTEXT}}",
        icon: "star.fill",
        isPinned: true
    )
    config.addCommand(command)

    do {
        try storage.save(config)
        TestRunner.assertEqual(storage.saveCount, 1, "Save called once")

        let loaded = try storage.load()
        TestRunner.assertEqual(storage.loadCount, 1, "Load called once")

        TestRunner.assertEqual(loaded.commands.count, 1, "Command count matches")
        TestRunner.assertEqual(loaded.commands[0].name, "Custom Command", "Command name matches")
        TestRunner.assertEqual(loaded.commands[0].description, "My custom command", "Description matches")
        TestRunner.assertEqual(loaded.commands[0].promptTemplate, "Do something with {{CONTEXT}}", "Template matches")
        TestRunner.assertEqual(loaded.commands[0].icon, "star.fill", "Icon matches")
        TestRunner.assertTrue(loaded.commands[0].isPinned, "isPinned matches")
        TestRunner.assertEqual(loaded.pinnedOrder.count, 1, "Pinned order matches")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_MultipleCommands() {
    TestRunner.setGroup("Storage - Multiple Commands")

    let storage = MockCommandStorage()

    var config = CommandConfigFile.empty
    for i in 1...10 {
        let command = Command(
            name: "Command \(i)",
            promptTemplate: "Template \(i)",
            isPinned: i <= 5  // First 5 are pinned
        )
        config.addCommand(command)
    }

    do {
        try storage.save(config)
        let loaded = try storage.load()

        TestRunner.assertEqual(loaded.commands.count, 10, "All 10 commands saved")
        TestRunner.assertEqual(loaded.pinnedOrder.count, 5, "5 pinned (max)")
        TestRunner.assertFalse(loaded.canPinMore, "Cannot pin more at max")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_UpdateCommand() {
    TestRunner.setGroup("Storage - Update Command")

    let storage = MockCommandStorage()

    var config = CommandConfigFile.empty
    var command = Command(name: "Original", promptTemplate: "Original Template")
    config.addCommand(command)

    do {
        try storage.save(config)

        // Load, modify, save
        var loaded = try storage.load()
        command.name = "Updated"
        command.promptTemplate = "Updated Template"
        loaded.updateCommand(command)
        try storage.save(loaded)

        // Verify changes persisted
        let reloaded = try storage.load()
        TestRunner.assertEqual(reloaded.commands[0].name, "Updated", "Name updated")
        TestRunner.assertEqual(reloaded.commands[0].promptTemplate, "Updated Template", "Template updated")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_RemoveCommand() {
    TestRunner.setGroup("Storage - Remove Command")

    let storage = MockCommandStorage()

    var config = CommandConfigFile.empty
    let command1 = Command(name: "Keep", promptTemplate: "Keep this", isPinned: true)
    let command2 = Command(name: "Remove", promptTemplate: "Remove this", isPinned: true)
    config.addCommand(command1)
    config.addCommand(command2)

    do {
        try storage.save(config)
        TestRunner.assertEqual(config.commands.count, 2, "Started with 2 commands")
        TestRunner.assertEqual(config.pinnedOrder.count, 2, "Started with 2 pinned")

        // Remove one command
        var loaded = try storage.load()
        loaded.removeCommand(id: command2.id)
        try storage.save(loaded)

        // Verify
        let reloaded = try storage.load()
        TestRunner.assertEqual(reloaded.commands.count, 1, "Now has 1 command")
        TestRunner.assertEqual(reloaded.commands[0].name, "Keep", "Correct command kept")
        TestRunner.assertEqual(reloaded.pinnedOrder.count, 1, "Pinned order updated")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_RecordUsage() {
    TestRunner.setGroup("Storage - Record Usage")

    let storage = MockCommandStorage()

    var config = CommandConfigFile.empty
    let command = Command(name: "Test", promptTemplate: "Test", usageCount: 0)
    config.addCommand(command)

    do {
        try storage.save(config)

        var loaded = try storage.load()
        TestRunner.assertEqual(loaded.commands[0].usageCount, 0, "Usage starts at 0")

        // Record usage multiple times
        for _ in 1...5 {
            loaded.recordUsage(id: command.id)
        }
        try storage.save(loaded)

        let reloaded = try storage.load()
        TestRunner.assertEqual(reloaded.commands[0].usageCount, 5, "Usage count is 5")
        TestRunner.assertNotNil(reloaded.commands[0].lastUsedAt, "lastUsedAt is set")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_PinnedOrderPreserved() {
    TestRunner.setGroup("Storage - Pinned Order Preserved")

    let storage = MockCommandStorage()

    var config = CommandConfigFile.empty
    let cmd1 = Command(name: "First", promptTemplate: "1", isPinned: true)
    let cmd2 = Command(name: "Second", promptTemplate: "2", isPinned: true)
    let cmd3 = Command(name: "Third", promptTemplate: "3", isPinned: true)

    config.addCommand(cmd1)
    config.addCommand(cmd2)
    config.addCommand(cmd3)

    do {
        try storage.save(config)

        let loaded = try storage.load()
        // Order should be preserved as added
        TestRunner.assertEqual(loaded.pinnedOrder[0], cmd1.id, "First command first")
        TestRunner.assertEqual(loaded.pinnedOrder[1], cmd2.id, "Second command second")
        TestRunner.assertEqual(loaded.pinnedOrder[2], cmd3.id, "Third command third")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_SpecialCharactersInTemplate() {
    TestRunner.setGroup("Storage - Special Characters In Template")

    let storage = MockCommandStorage()

    let specialTemplate = """
    Fix this code:
    ```javascript
    const x = "hello";
    console.log('world');
    ```

    Rules:
    1. Use "double quotes"
    2. Handle 'single quotes'
    3. Emoji: 🚀✨
    4. Newlines and tabs\t\there
    """

    var config = CommandConfigFile.empty
    let command = Command(name: "Special", promptTemplate: specialTemplate)
    config.addCommand(command)

    do {
        try storage.save(config)
        let loaded = try storage.load()

        TestRunner.assertEqual(loaded.commands[0].promptTemplate, specialTemplate, "Special characters preserved")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_EmptyConfig() {
    TestRunner.setGroup("Storage - Empty Config")

    let storage = MockCommandStorage()
    let config = CommandConfigFile.empty

    do {
        try storage.save(config)
        let loaded = try storage.load()

        TestRunner.assertTrue(loaded.commands.isEmpty, "Commands is empty")
        TestRunner.assertTrue(loaded.pinnedOrder.isEmpty, "Pinned order is empty")
        TestRunner.assertTrue(loaded.canPinMore, "Can pin more when empty")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_MigrationFromV1() {
    TestRunner.setGroup("Storage - Migration From V1")

    let storage = MockCommandStorage()

    // Create V1 config
    var config = CommandConfigFile(version: 1, commands: [], pinnedOrder: [])
    let command = Command(name: "V1 Command", promptTemplate: "V1 Template")
    config.addCommand(command)

    do {
        try storage.save(config)
        let loaded = try storage.load()

        // Should load successfully (V1 is current version)
        TestRunner.assertEqual(loaded.version, 1, "Version is 1")
        TestRunner.assertEqual(loaded.commands.count, 1, "Command loaded")
        TestRunner.assertEqual(loaded.commands[0].name, "V1 Command", "Command name preserved")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

// MARK: - Edge Case Tests

func testStorage_VeryLongCommandName() {
    TestRunner.setGroup("Edge Case - Very Long Command Name")

    let storage = MockCommandStorage()

    let longName = String(repeating: "A", count: 1000)
    var config = CommandConfigFile.empty
    let command = Command(name: longName, promptTemplate: "Test")
    config.addCommand(command)

    do {
        try storage.save(config)
        let loaded = try storage.load()

        TestRunner.assertEqual(loaded.commands[0].name.count, 1000, "Long name preserved")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_UnicodeInAllFields() {
    TestRunner.setGroup("Edge Case - Unicode In All Fields")

    let storage = MockCommandStorage()

    var config = CommandConfigFile.empty
    let command = Command(
        name: "日本語コマンド",
        description: "Emoji: 🎉🚀 Arabic: مرحبا Chinese: 你好",
        promptTemplate: "Handle: Ñoño, Ümläut, Ωmega, Кириллица",
        icon: "globe"
    )
    config.addCommand(command)

    do {
        try storage.save(config)
        let loaded = try storage.load()

        TestRunner.assertEqual(loaded.commands[0].name, "日本語コマンド", "Japanese preserved")
        TestRunner.assertEqual(loaded.commands[0].description, "Emoji: 🎉🚀 Arabic: مرحبا Chinese: 你好", "Mixed unicode preserved")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testStorage_MaxPinnedEnforced() {
    TestRunner.setGroup("Edge Case - Max Pinned Enforced Across Save/Load")

    let storage = MockCommandStorage()

    var config = CommandConfigFile.empty

    // Add 6 pinned commands
    for i in 1...6 {
        let command = Command(name: "Pinned \(i)", promptTemplate: "T", isPinned: true)
        config.addCommand(command)
    }

    do {
        try storage.save(config)
        let loaded = try storage.load()

        // Should only have 5 in pinned order (max)
        TestRunner.assertEqual(loaded.pinnedOrder.count, 5, "Max 5 pinned")
        TestRunner.assertEqual(loaded.commands.count, 6, "All 6 commands saved")
        TestRunner.assertFalse(loaded.canPinMore, "Cannot pin more")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

// MARK: - Main Entry Point

@main
struct CommandStorageTestRunner {
    static func main() {
        print("")
        print("🧪 Command Storage Tests")
        print("==================================================")

        // Storage Tests
        testStorage_FirstLaunchReturnsDefaults()
        testStorage_SaveAndLoadRoundTrip()
        testStorage_MultipleCommands()
        testStorage_UpdateCommand()
        testStorage_RemoveCommand()
        testStorage_RecordUsage()
        testStorage_PinnedOrderPreserved()
        testStorage_SpecialCharactersInTemplate()
        testStorage_EmptyConfig()
        testStorage_MigrationFromV1()

        // Edge Cases
        testStorage_VeryLongCommandName()
        testStorage_UnicodeInAllFields()
        testStorage_MaxPinnedEnforced()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
