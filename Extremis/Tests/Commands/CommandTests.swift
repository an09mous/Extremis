// MARK: - Command Unit Tests
// Tests for Command model and CommandConfigFile

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

    mutating func setPinnedOrder(_ order: [UUID]) {
        let validOrder = order.filter { id in
            commands.contains { $0.id == id && $0.isPinned }
        }
        pinnedOrder = Array(validOrder.prefix(Self.maxPinnedCommands))
    }

    var canPinMore: Bool {
        pinnedOrder.count < Self.maxPinnedCommands
    }

    var commandsSortedByRecent: [Command] {
        commands.sorted { a, b in
            guard let aDate = a.lastUsedAt else { return false }
            guard let bDate = b.lastUsedAt else { return true }
            return aDate > bDate
        }
    }

    var commandsSortedByUsage: [Command] {
        commands.sorted { $0.usageCount > $1.usageCount }
    }
}

// MARK: - Command Model Tests

func testCommand_Creation() {
    TestRunner.setGroup("Command - Creation")

    let command = Command(
        name: "Test Command",
        description: "A test command",
        promptTemplate: "Do something with {{CONTEXT}}",
        icon: "star",
        isPinned: false
    )

    TestRunner.assertEqual(command.name, "Test Command", "Name is set correctly")
    TestRunner.assertEqual(command.description, "A test command", "Description is set correctly")
    TestRunner.assertEqual(command.promptTemplate, "Do something with {{CONTEXT}}", "Template is set correctly")
    TestRunner.assertEqual(command.icon, "star", "Icon is set correctly")
    TestRunner.assertFalse(command.isPinned, "isPinned is false by default")
    TestRunner.assertEqual(command.usageCount, 0, "Usage count starts at 0")
    TestRunner.assertNil(command.lastUsedAt, "lastUsedAt is nil initially")
}

func testCommand_DisplayIcon() {
    TestRunner.setGroup("Command - Display Icon")

    let commandWithIcon = Command(name: "Test", promptTemplate: "Test", icon: "gear")
    TestRunner.assertEqual(commandWithIcon.displayIcon, "gear", "Uses custom icon when set")

    let commandWithoutIcon = Command(name: "Test", promptTemplate: "Test", icon: nil)
    TestRunner.assertEqual(commandWithoutIcon.displayIcon, "command", "Uses default 'command' icon as fallback")
}

func testCommand_WithRecordedUsage() {
    TestRunner.setGroup("Command - With Recorded Usage")

    let original = Command(name: "Test", promptTemplate: "Test", usageCount: 5)
    let updated = original.withRecordedUsage()

    TestRunner.assertEqual(updated.usageCount, 6, "Usage count incremented")
    TestRunner.assertNotNil(updated.lastUsedAt, "lastUsedAt is set")
    TestRunner.assertEqual(original.usageCount, 5, "Original unchanged (immutable)")
}

func testCommand_WithUpdatedTimestamp() {
    TestRunner.setGroup("Command - With Updated Timestamp")

    let originalDate = Date(timeIntervalSince1970: 0)
    let original = Command(name: "Test", promptTemplate: "Test", updatedAt: originalDate)

    // Small delay to ensure timestamp changes
    let updated = original.withUpdatedTimestamp()

    TestRunner.assertTrue(updated.updatedAt > originalDate, "Timestamp is updated")
}

func testCommand_Encoding() {
    TestRunner.setGroup("Command - JSON Encoding/Decoding")

    let command = Command(
        name: "Test",
        description: "Description",
        promptTemplate: "Template",
        icon: "star",
        isPinned: true,
        usageCount: 10
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
        let data = try encoder.encode(command)
        let decoded = try decoder.decode(Command.self, from: data)

        TestRunner.assertEqual(decoded.name, command.name, "Name survives encoding")
        TestRunner.assertEqual(decoded.description, command.description, "Description survives encoding")
        TestRunner.assertEqual(decoded.promptTemplate, command.promptTemplate, "Template survives encoding")
        TestRunner.assertEqual(decoded.icon, command.icon, "Icon survives encoding")
        TestRunner.assertEqual(decoded.isPinned, command.isPinned, "isPinned survives encoding")
        TestRunner.assertEqual(decoded.usageCount, command.usageCount, "usageCount survives encoding")
    } catch {
        TestRunner.assertTrue(false, "Encoding/decoding should not throw: \(error)")
    }
}

// MARK: - CommandConfigFile Tests

func testConfigFile_Empty() {
    TestRunner.setGroup("CommandConfigFile - Empty")

    let config = CommandConfigFile.empty

    TestRunner.assertEqual(config.version, CommandConfigFile.currentVersion, "Version is current")
    TestRunner.assertTrue(config.commands.isEmpty, "No commands")
    TestRunner.assertTrue(config.pinnedOrder.isEmpty, "No pinned order")
    TestRunner.assertTrue(config.canPinMore, "Can pin more when empty")
}

func testConfigFile_AddCommand() {
    TestRunner.setGroup("CommandConfigFile - Add Command")

    var config = CommandConfigFile.empty
    let command = Command(name: "Test", promptTemplate: "Test")

    config.addCommand(command)

    TestRunner.assertEqual(config.commands.count, 1, "Command added")
    TestRunner.assertEqual(config.commands[0].id, command.id, "Correct command added")
}

func testConfigFile_AddPinnedCommand() {
    TestRunner.setGroup("CommandConfigFile - Add Pinned Command")

    var config = CommandConfigFile.empty
    let command = Command(name: "Test", promptTemplate: "Test", isPinned: true)

    config.addCommand(command)

    TestRunner.assertEqual(config.pinnedOrder.count, 1, "Pinned order updated")
    TestRunner.assertEqual(config.pinnedOrder[0], command.id, "Correct ID in pinned order")
    TestRunner.assertEqual(config.pinnedCommands.count, 1, "Pinned commands returns correct count")
}

func testConfigFile_MaxPinnedCommands() {
    TestRunner.setGroup("CommandConfigFile - Max Pinned Commands")

    var config = CommandConfigFile.empty

    // Add 5 pinned commands (max)
    for i in 0..<5 {
        let command = Command(name: "Command \(i)", promptTemplate: "Test", isPinned: true)
        config.addCommand(command)
    }

    TestRunner.assertEqual(config.pinnedOrder.count, 5, "5 commands pinned")
    TestRunner.assertFalse(config.canPinMore, "Cannot pin more at max")

    // Try to add 6th pinned command
    let extraCommand = Command(name: "Extra", promptTemplate: "Test", isPinned: true)
    config.addCommand(extraCommand)

    TestRunner.assertEqual(config.pinnedOrder.count, 5, "Still 5 pinned (6th not added to pin order)")
    TestRunner.assertEqual(config.commands.count, 6, "But command was still added to list")
}

func testConfigFile_RemoveCommand() {
    TestRunner.setGroup("CommandConfigFile - Remove Command")

    var config = CommandConfigFile.empty
    let command = Command(name: "Test", promptTemplate: "Test", isPinned: true)
    config.addCommand(command)

    TestRunner.assertEqual(config.commands.count, 1, "Command added")
    TestRunner.assertEqual(config.pinnedOrder.count, 1, "Pinned order has command")

    config.removeCommand(id: command.id)

    TestRunner.assertTrue(config.commands.isEmpty, "Command removed")
    TestRunner.assertTrue(config.pinnedOrder.isEmpty, "Pinned order cleared")
}

func testConfigFile_UpdateCommand() {
    TestRunner.setGroup("CommandConfigFile - Update Command")

    var config = CommandConfigFile.empty
    var command = Command(name: "Original", promptTemplate: "Test")
    config.addCommand(command)

    command.name = "Updated"
    config.updateCommand(command)

    TestRunner.assertEqual(config.commands[0].name, "Updated", "Name updated")
}

func testConfigFile_UpdatePinState() {
    TestRunner.setGroup("CommandConfigFile - Update Pin State")

    var config = CommandConfigFile.empty
    var command = Command(name: "Test", promptTemplate: "Test", isPinned: false)
    config.addCommand(command)

    TestRunner.assertTrue(config.pinnedOrder.isEmpty, "Not pinned initially")

    // Pin the command
    command.isPinned = true
    config.updateCommand(command)

    TestRunner.assertEqual(config.pinnedOrder.count, 1, "Now pinned")

    // Unpin the command
    command.isPinned = false
    config.updateCommand(command)

    TestRunner.assertTrue(config.pinnedOrder.isEmpty, "Unpinned")
}

func testConfigFile_RecordUsage() {
    TestRunner.setGroup("CommandConfigFile - Record Usage")

    var config = CommandConfigFile.empty
    let command = Command(name: "Test", promptTemplate: "Test", usageCount: 0)
    config.addCommand(command)

    config.recordUsage(id: command.id)

    TestRunner.assertEqual(config.commands[0].usageCount, 1, "Usage count incremented")
    TestRunner.assertNotNil(config.commands[0].lastUsedAt, "lastUsedAt set")
}

func testConfigFile_SetPinnedOrder() {
    TestRunner.setGroup("CommandConfigFile - Set Pinned Order")

    var config = CommandConfigFile.empty
    let command1 = Command(name: "A", promptTemplate: "Test", isPinned: true)
    let command2 = Command(name: "B", promptTemplate: "Test", isPinned: true)
    let command3 = Command(name: "C", promptTemplate: "Test", isPinned: true)

    config.addCommand(command1)
    config.addCommand(command2)
    config.addCommand(command3)

    // Reverse the order
    config.setPinnedOrder([command3.id, command2.id, command1.id])

    TestRunner.assertEqual(config.pinnedOrder[0], command3.id, "First is command3")
    TestRunner.assertEqual(config.pinnedOrder[1], command2.id, "Second is command2")
    TestRunner.assertEqual(config.pinnedOrder[2], command1.id, "Third is command1")
}

func testConfigFile_PinnedOrderFiltersUnpinned() {
    TestRunner.setGroup("CommandConfigFile - Pinned Order Filters Unpinned")

    var config = CommandConfigFile.empty
    var command = Command(name: "Test", promptTemplate: "Test", isPinned: true)
    config.addCommand(command)

    TestRunner.assertEqual(config.pinnedCommands.count, 1, "Has pinned command")

    // Unpin via direct modification (simulating edge case)
    command.isPinned = false
    config.commands[0] = command

    // pinnedCommands should filter out unpinned ones
    TestRunner.assertTrue(config.pinnedCommands.isEmpty, "Pinned commands excludes unpinned")
}

func testConfigFile_SortedByRecent() {
    TestRunner.setGroup("CommandConfigFile - Sorted By Recent")

    var config = CommandConfigFile.empty
    let oldDate = Date(timeIntervalSince1970: 1000)
    let newDate = Date(timeIntervalSince1970: 2000)

    let oldCommand = Command(name: "Old", promptTemplate: "Test", lastUsedAt: oldDate)
    let newCommand = Command(name: "New", promptTemplate: "Test", lastUsedAt: newDate)
    let neverUsed = Command(name: "Never", promptTemplate: "Test", lastUsedAt: nil)

    config.addCommand(oldCommand)
    config.addCommand(neverUsed)
    config.addCommand(newCommand)

    let sorted = config.commandsSortedByRecent

    TestRunner.assertEqual(sorted[0].name, "New", "Most recent first")
    TestRunner.assertEqual(sorted[1].name, "Old", "Older second")
    TestRunner.assertEqual(sorted[2].name, "Never", "Never used last")
}

func testConfigFile_SortedByUsage() {
    TestRunner.setGroup("CommandConfigFile - Sorted By Usage")

    var config = CommandConfigFile.empty

    let lowUsage = Command(name: "Low", promptTemplate: "Test", usageCount: 1)
    let highUsage = Command(name: "High", promptTemplate: "Test", usageCount: 100)
    let midUsage = Command(name: "Mid", promptTemplate: "Test", usageCount: 50)

    config.addCommand(lowUsage)
    config.addCommand(highUsage)
    config.addCommand(midUsage)

    let sorted = config.commandsSortedByUsage

    TestRunner.assertEqual(sorted[0].name, "High", "Most used first")
    TestRunner.assertEqual(sorted[1].name, "Mid", "Mid usage second")
    TestRunner.assertEqual(sorted[2].name, "Low", "Least used last")
}

func testConfigFile_Encoding() {
    TestRunner.setGroup("CommandConfigFile - JSON Encoding/Decoding")

    var config = CommandConfigFile.empty
    let command = Command(name: "Test", promptTemplate: "Template", isPinned: true)
    config.addCommand(command)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(CommandConfigFile.self, from: data)

        TestRunner.assertEqual(decoded.version, config.version, "Version survives encoding")
        TestRunner.assertEqual(decoded.commands.count, config.commands.count, "Commands count matches")
        TestRunner.assertEqual(decoded.pinnedOrder.count, config.pinnedOrder.count, "Pinned order count matches")
    } catch {
        TestRunner.assertTrue(false, "Encoding/decoding should not throw: \(error)")
    }
}

// MARK: - Edge Cases

func testEdgeCase_EmptyCommandName() {
    TestRunner.setGroup("Edge Case - Empty Command Name")

    let command = Command(name: "", promptTemplate: "Test")

    TestRunner.assertEqual(command.name, "", "Empty name is allowed")
}

func testEdgeCase_LongPromptTemplate() {
    TestRunner.setGroup("Edge Case - Long Prompt Template")

    let longTemplate = String(repeating: "Test ", count: 10000)
    let command = Command(name: "Long", promptTemplate: longTemplate)

    TestRunner.assertEqual(command.promptTemplate.count, 50000, "Long template stored correctly")
}

func testEdgeCase_SpecialCharactersInTemplate() {
    TestRunner.setGroup("Edge Case - Special Characters In Template")

    let template = "Fix this: {{CONTEXT}}\n\nRules:\n1. \"Quote\" things\n2. Use 'apostrophes'\n3. Handle emoji "
    let command = Command(name: "Special", promptTemplate: template)

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    do {
        let data = try encoder.encode(command)
        let decoded = try decoder.decode(Command.self, from: data)
        TestRunner.assertEqual(decoded.promptTemplate, template, "Special characters survive encoding")
    } catch {
        TestRunner.assertTrue(false, "Should handle special characters")
    }
}

func testEdgeCase_RemoveNonExistentCommand() {
    TestRunner.setGroup("Edge Case - Remove Non-Existent Command")

    var config = CommandConfigFile.empty
    let nonExistentId = UUID()

    // Should not crash
    config.removeCommand(id: nonExistentId)

    TestRunner.assertTrue(config.commands.isEmpty, "Still empty after removing non-existent")
}

func testEdgeCase_UpdateNonExistentCommand() {
    TestRunner.setGroup("Edge Case - Update Non-Existent Command")

    var config = CommandConfigFile.empty
    let command = Command(name: "Ghost", promptTemplate: "Test")

    // Should not crash or add command
    config.updateCommand(command)

    TestRunner.assertTrue(config.commands.isEmpty, "Still empty after updating non-existent")
}

func testEdgeCase_RecordUsageNonExistent() {
    TestRunner.setGroup("Edge Case - Record Usage Non-Existent")

    var config = CommandConfigFile.empty
    let nonExistentId = UUID()

    // Should not crash
    config.recordUsage(id: nonExistentId)

    TestRunner.assertTrue(config.commands.isEmpty, "Still empty")
}

// MARK: - Main Entry Point

@main
struct CommandTestRunner {
    static func main() {
        print("")
        print("🧪 Command Model Tests")
        print("==================================================")

        // Command Model Tests
        testCommand_Creation()
        testCommand_DisplayIcon()
        testCommand_WithRecordedUsage()
        testCommand_WithUpdatedTimestamp()
        testCommand_Encoding()

        // CommandConfigFile Tests
        testConfigFile_Empty()
        testConfigFile_AddCommand()
        testConfigFile_AddPinnedCommand()
        testConfigFile_MaxPinnedCommands()
        testConfigFile_RemoveCommand()
        testConfigFile_UpdateCommand()
        testConfigFile_UpdatePinState()
        testConfigFile_RecordUsage()
        testConfigFile_SetPinnedOrder()
        testConfigFile_PinnedOrderFiltersUnpinned()
        testConfigFile_SortedByRecent()
        testConfigFile_SortedByUsage()
        testConfigFile_Encoding()

        // Edge Cases
        testEdgeCase_EmptyCommandName()
        testEdgeCase_LongPromptTemplate()
        testEdgeCase_SpecialCharactersInTemplate()
        testEdgeCase_RemoveNonExistentCommand()
        testEdgeCase_UpdateNonExistentCommand()
        testEdgeCase_RecordUsageNonExistent()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
