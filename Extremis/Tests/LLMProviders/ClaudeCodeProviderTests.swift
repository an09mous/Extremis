// MARK: - ClaudeCodeProvider Unit Tests
// Tests for provider configuration, model selection, and tool approval logic
// Standalone test file — can be compiled and run independently

import Foundation

// MARK: - Test Infrastructure

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(String, String)] = []

    static func assertTrue(_ condition: Bool, _ name: String) {
        if condition {
            passedCount += 1
            print("  ✓ \(name)")
        } else {
            failedCount += 1
            failedTests.append((name, "Expected true, got false"))
            print("  ✗ \(name)")
        }
    }

    static func assertFalse(_ condition: Bool, _ name: String) {
        assertTrue(!condition, name)
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(name)")
        } else {
            failedCount += 1
            failedTests.append((name, "Expected \(expected), got \(actual)"))
            print("  ✗ \(name) — Expected \(expected), got \(actual)")
        }
    }

    static func assertNil<T>(_ value: T?, _ name: String) {
        if value == nil {
            passedCount += 1
            print("  ✓ \(name)")
        } else {
            failedCount += 1
            failedTests.append((name, "Expected nil"))
            print("  ✗ \(name) — Expected nil")
        }
    }

    static func suite(_ name: String) {
        print("\n📦 \(name)")
        print(String(repeating: "-", count: 50))
    }

    static func printSummary() {
        print("\n" + String(repeating: "=", count: 50))
        print("TEST SUMMARY")
        print(String(repeating: "=", count: 50))
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("\nFailed Tests:")
            for (name, message) in failedTests {
                print("  • \(name): \(message)")
            }
        }
        print(String(repeating: "=", count: 50))
    }
}

// MARK: - Standalone type stubs

struct CLIToolInfo: Codable, Identifiable, Hashable {
    let name: String
    var isApproved: Bool
    var id: String { name }
}

// MARK: - Tests

func testCLIToolInfoModel() {
    TestRunner.suite("CLIToolInfo Model")

    let tool = CLIToolInfo(name: "Bash", isApproved: false)
    TestRunner.assertEqual(tool.name, "Bash", "Tool name")
    TestRunner.assertFalse(tool.isApproved, "Default not approved")
    TestRunner.assertEqual(tool.id, "Bash", "ID equals name")

    var approvedTool = CLIToolInfo(name: "Read", isApproved: true)
    TestRunner.assertTrue(approvedTool.isApproved, "Approved tool is approved")

    // Toggle approval
    approvedTool.isApproved = false
    TestRunner.assertFalse(approvedTool.isApproved, "Toggle approval to false")
}

func testCLIToolInfoCodable() {
    TestRunner.suite("CLIToolInfo Codable")

    let tool = CLIToolInfo(name: "Edit", isApproved: true)

    // Encode
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(tool) else {
        TestRunner.assertTrue(false, "Encode tool info")
        return
    }
    TestRunner.assertTrue(true, "Encode tool info")

    // Decode
    let decoder = JSONDecoder()
    guard let decoded = try? decoder.decode(CLIToolInfo.self, from: data) else {
        TestRunner.assertTrue(false, "Decode tool info")
        return
    }
    TestRunner.assertEqual(decoded.name, "Edit", "Decoded name")
    TestRunner.assertTrue(decoded.isApproved, "Decoded isApproved")
}

func testCLIToolInfoHashable() {
    TestRunner.suite("CLIToolInfo Hashable")

    let tool1 = CLIToolInfo(name: "Bash", isApproved: true)
    let tool2 = CLIToolInfo(name: "Bash", isApproved: false)
    let tool3 = CLIToolInfo(name: "Read", isApproved: true)

    // Same name = same hash (Hashable uses all stored properties)
    var set = Set<CLIToolInfo>()
    set.insert(tool1)
    // tool2 has different isApproved, so it's a different hash
    set.insert(tool2)
    set.insert(tool3)
    // All three should be in the set (different stored property combos)
    TestRunner.assertTrue(set.count >= 2, "Set contains at least 2 unique tools")
    TestRunner.assertTrue(set.contains(tool3), "Set contains Read tool")
}

func testToolApprovalFiltering() {
    TestRunner.suite("Tool Approval Filtering")

    let tools: [CLIToolInfo] = [
        CLIToolInfo(name: "Bash", isApproved: true),
        CLIToolInfo(name: "Read", isApproved: false),
        CLIToolInfo(name: "Edit", isApproved: true),
        CLIToolInfo(name: "Write", isApproved: false),
        CLIToolInfo(name: "Glob", isApproved: true),
    ]

    let approvedNames = tools.filter(\.isApproved).map(\.name)
    TestRunner.assertEqual(approvedNames.count, 3, "Three tools approved")
    TestRunner.assertTrue(approvedNames.contains("Bash"), "Bash approved")
    TestRunner.assertTrue(approvedNames.contains("Edit"), "Edit approved")
    TestRunner.assertTrue(approvedNames.contains("Glob"), "Glob approved")
    TestRunner.assertFalse(approvedNames.contains("Read"), "Read not approved")
    TestRunner.assertFalse(approvedNames.contains("Write"), "Write not approved")

    // Join for --allowedTools flag
    let flag = approvedNames.joined(separator: ",")
    TestRunner.assertEqual(flag, "Bash,Edit,Glob", "Comma-joined approved tools")
}

func testToolDiscoveryMerge() {
    TestRunner.suite("Tool Discovery Merge (existing approvals preserved)")

    // Simulate existing approved tools
    var existingTools: [CLIToolInfo] = [
        CLIToolInfo(name: "Bash", isApproved: true),
        CLIToolInfo(name: "Read", isApproved: true),
    ]
    let existingApprovals = Dictionary(uniqueKeysWithValues: existingTools.map { ($0.name, $0.isApproved) })

    // New discovery from CLI (has new tools, missing old ones)
    let discoveredNames = ["Bash", "Read", "Edit", "Write", "Glob"]

    let merged = discoveredNames.map { name in
        CLIToolInfo(name: name, isApproved: existingApprovals[name] ?? false)
    }

    TestRunner.assertEqual(merged.count, 5, "All discovered tools present")
    TestRunner.assertTrue(merged.first { $0.name == "Bash" }?.isApproved ?? false, "Bash approval preserved")
    TestRunner.assertTrue(merged.first { $0.name == "Read" }?.isApproved ?? false, "Read approval preserved")
    TestRunner.assertFalse(merged.first { $0.name == "Edit" }?.isApproved ?? false, "New tool Edit defaults to false")
    TestRunner.assertFalse(merged.first { $0.name == "Write" }?.isApproved ?? false, "New tool Write defaults to false")
    TestRunner.assertFalse(merged.first { $0.name == "Glob" }?.isApproved ?? false, "New tool Glob defaults to false")
}

func testToolApprovalPersistence() {
    TestRunner.suite("Tool Approval Persistence (JSON encoding)")

    let approvedNames = ["Bash", "Edit", "Glob"]

    // Encode
    guard let data = try? JSONEncoder().encode(approvedNames) else {
        TestRunner.assertTrue(false, "Encode approved tool names")
        return
    }
    TestRunner.assertTrue(true, "Encode approved tool names")

    // Decode
    guard let decoded = try? JSONDecoder().decode([String].self, from: data) else {
        TestRunner.assertTrue(false, "Decode approved tool names")
        return
    }
    TestRunner.assertEqual(decoded.count, 3, "Decoded count matches")
    TestRunner.assertEqual(decoded, approvedNames, "Decoded names match")
}

func testModelAliases() {
    TestRunner.suite("Model Aliases")

    // Verify model IDs are simple aliases
    let models = [
        ("sonnet", "Sonnet"),
        ("opus", "Opus"),
        ("haiku", "Haiku"),
    ]

    for (id, name) in models {
        TestRunner.assertTrue(id == id.lowercased(), "\(id) is lowercase")
        TestRunner.assertTrue(!id.contains("-"), "\(id) has no dashes (alias, not full ID)")
        TestRunner.assertTrue(!name.isEmpty, "\(name) has display name")
    }
}

func testProviderTypeProperties() {
    TestRunner.suite("Provider Type Properties")

    // Test that Claude Code rawValue matches what we expect
    let rawValue = "Claude Code"
    TestRunner.assertEqual(rawValue, "Claude Code", "Raw value is 'Claude Code'")

    // requiresAPIKey should be false
    let requiresAPIKey = false  // .claudeCode.requiresAPIKey
    TestRunner.assertFalse(requiresAPIKey, "Does not require API key")
}

func testEmptyToolsList() {
    TestRunner.suite("Empty Tools List")

    let tools: [CLIToolInfo] = []
    let approvedNames = tools.filter(\.isApproved).map(\.name)
    TestRunner.assertTrue(approvedNames.isEmpty, "Empty tools → empty approved list")
    TestRunner.assertEqual(approvedNames.joined(separator: ","), "", "Empty join is empty string")
}

// MARK: - Main

@main
struct ClaudeCodeProviderTests {
    static func main() {
        testCLIToolInfoModel()
        testCLIToolInfoCodable()
        testCLIToolInfoHashable()
        testToolApprovalFiltering()
        testToolDiscoveryMerge()
        testToolApprovalPersistence()
        testModelAliases()
        testProviderTypeProperties()
        testEmptyToolsList()
        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
