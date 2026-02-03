// MARK: - Sudo Mode Tests
// Unit tests for sudo mode feature that bypasses tool approval

import Foundation

// MARK: - Test Runner

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0

    static func suite(_ name: String) {
        print("\n\u{1F4CB} \(name)")
        print(String(repeating: "-", count: 50))
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            passedCount += 1
            print("  \u{2705} \(message)")
        } else {
            failedCount += 1
            print("  \u{274C} \(message)")
            print("     Expected: \(expected)")
            print("     Actual: \(actual)")
        }
    }

    static func assertTrue(_ condition: Bool, _ message: String) {
        if condition {
            passedCount += 1
            print("  \u{2705} \(message)")
        } else {
            failedCount += 1
            print("  \u{274C} \(message)")
        }
    }

    static func assertFalse(_ condition: Bool, _ message: String) {
        assertTrue(!condition, message)
    }

    static func printSummary() {
        print("\n" + String(repeating: "=", count: 50))
        print("TEST RESULTS")
        print(String(repeating: "=", count: 50))
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print(String(repeating: "=", count: 50))
    }
}

// MARK: - UserDefaults Extension (mirrors production code)

extension UserDefaults {
    var sudoModeEnabled: Bool {
        get { bool(forKey: "sudoModeEnabled") }
        set { set(newValue, forKey: "sudoModeEnabled") }
    }
}

// MARK: - Mock Types

enum ApprovalAction: String {
    case approved
    case denied
    case dismissed
    case sessionApproved
}

struct MockToolCall {
    let id: String
    let toolName: String
    let connectorID: String

    init(id: String = UUID().uuidString, toolName: String, connectorID: String) {
        self.id = id
        self.toolName = toolName
        self.connectorID = connectorID
    }
}

struct ApprovalDecision {
    let requestId: String
    let toolName: String
    let connectorId: String
    let action: ApprovalAction
    let reason: String?

    init(toolCall: MockToolCall, action: ApprovalAction, reason: String? = nil) {
        self.requestId = toolCall.id
        self.toolName = toolCall.toolName
        self.connectorId = toolCall.connectorID
        self.action = action
        self.reason = reason
    }
}

struct ApprovalResult {
    let approvedIds: Set<String>
    let decisions: [ApprovalDecision]
    let allowAllOnce: Bool

    static let empty = ApprovalResult(approvedIds: [], decisions: [], allowAllOnce: false)
}

// MARK: - Mock Approval Manager (simulates production behavior)

final class MockToolApprovalManager {

    /// Request approval for tool calls - mirrors production logic
    func requestApproval(for toolCalls: [MockToolCall]) -> ApprovalResult {
        // Empty list -> empty result
        guard !toolCalls.isEmpty else {
            return .empty
        }

        // SUDO MODE: Bypass all approval when enabled
        if UserDefaults.standard.sudoModeEnabled {
            let decisions = toolCalls.map { toolCall in
                ApprovalDecision(
                    toolCall: toolCall,
                    action: .sessionApproved,
                    reason: "Sudo mode enabled"
                )
            }
            return ApprovalResult(
                approvedIds: Set(toolCalls.map(\.id)),
                decisions: decisions,
                allowAllOnce: true
            )
        }

        // Normal flow: Would need user approval (return empty for test)
        return ApprovalResult(
            approvedIds: [],
            decisions: [],
            allowAllOnce: false
        )
    }
}

// MARK: - Sudo Mode Default State Tests

func testSudoModeDefaultState() {
    TestRunner.suite("Sudo Mode Default State Tests")

    // Clean up any existing value
    UserDefaults.standard.removeObject(forKey: "sudoModeEnabled")

    // Test default is false (secure by default)
    TestRunner.assertFalse(
        UserDefaults.standard.sudoModeEnabled,
        "Sudo mode defaults to false"
    )

    // Test explicitly setting to false
    UserDefaults.standard.sudoModeEnabled = false
    TestRunner.assertFalse(
        UserDefaults.standard.sudoModeEnabled,
        "Sudo mode is false after explicit set"
    )
}

// MARK: - Sudo Mode Enable/Disable Tests

func testSudoModeToggle() {
    TestRunner.suite("Sudo Mode Toggle Tests")

    // Clean state
    UserDefaults.standard.removeObject(forKey: "sudoModeEnabled")

    // Enable sudo mode
    UserDefaults.standard.sudoModeEnabled = true
    TestRunner.assertTrue(
        UserDefaults.standard.sudoModeEnabled,
        "Sudo mode can be enabled"
    )

    // Disable sudo mode
    UserDefaults.standard.sudoModeEnabled = false
    TestRunner.assertFalse(
        UserDefaults.standard.sudoModeEnabled,
        "Sudo mode can be disabled"
    )

    // Enable again
    UserDefaults.standard.sudoModeEnabled = true
    TestRunner.assertTrue(
        UserDefaults.standard.sudoModeEnabled,
        "Sudo mode can be re-enabled"
    )

    // Clean up
    UserDefaults.standard.removeObject(forKey: "sudoModeEnabled")
}

// MARK: - Sudo Mode Approval Bypass Tests

func testSudoModeBypassesApproval() {
    TestRunner.suite("Sudo Mode Approval Bypass Tests")

    let manager = MockToolApprovalManager()

    // Clean state - sudo mode off
    UserDefaults.standard.sudoModeEnabled = false

    // Create test tool calls
    let toolCall1 = MockToolCall(toolName: "shell_execute", connectorID: "shell")
    let toolCall2 = MockToolCall(toolName: "github_search", connectorID: "github-mcp")
    let toolCall3 = MockToolCall(toolName: "slack_post", connectorID: "slack-mcp")
    let toolCalls = [toolCall1, toolCall2, toolCall3]

    // Test: With sudo mode OFF, no tools are auto-approved
    let resultOff = manager.requestApproval(for: toolCalls)
    TestRunner.assertTrue(
        resultOff.approvedIds.isEmpty,
        "With sudo mode OFF, no tools are auto-approved"
    )
    TestRunner.assertFalse(
        resultOff.allowAllOnce,
        "allowAllOnce is false when sudo mode is OFF"
    )

    // Enable sudo mode
    UserDefaults.standard.sudoModeEnabled = true

    // Test: With sudo mode ON, all tools are auto-approved
    let resultOn = manager.requestApproval(for: toolCalls)
    TestRunner.assertEqual(
        resultOn.approvedIds.count, 3,
        "With sudo mode ON, all 3 tools are approved"
    )
    TestRunner.assertTrue(
        resultOn.approvedIds.contains(toolCall1.id),
        "Shell tool is approved"
    )
    TestRunner.assertTrue(
        resultOn.approvedIds.contains(toolCall2.id),
        "GitHub tool is approved"
    )
    TestRunner.assertTrue(
        resultOn.approvedIds.contains(toolCall3.id),
        "Slack tool is approved"
    )
    TestRunner.assertTrue(
        resultOn.allowAllOnce,
        "allowAllOnce is true when sudo mode is ON"
    )

    // Verify all decisions have correct action and reason
    for decision in resultOn.decisions {
        TestRunner.assertEqual(
            decision.action, .sessionApproved,
            "Decision action is sessionApproved for \(decision.toolName)"
        )
        TestRunner.assertEqual(
            decision.reason, "Sudo mode enabled",
            "Decision reason is 'Sudo mode enabled' for \(decision.toolName)"
        )
    }

    // Clean up
    UserDefaults.standard.removeObject(forKey: "sudoModeEnabled")
}

// MARK: - Sudo Mode Empty Tool List Tests

func testSudoModeEmptyToolList() {
    TestRunner.suite("Sudo Mode Empty Tool List Tests")

    let manager = MockToolApprovalManager()

    // Enable sudo mode
    UserDefaults.standard.sudoModeEnabled = true

    // Test: Empty tool list returns empty result even with sudo mode
    let result = manager.requestApproval(for: [])
    TestRunner.assertTrue(
        result.approvedIds.isEmpty,
        "Empty tool list returns empty approved IDs"
    )
    TestRunner.assertTrue(
        result.decisions.isEmpty,
        "Empty tool list returns empty decisions"
    )
    TestRunner.assertFalse(
        result.allowAllOnce,
        "Empty tool list returns allowAllOnce=false"
    )

    // Clean up
    UserDefaults.standard.removeObject(forKey: "sudoModeEnabled")
}

// MARK: - Sudo Mode Persistence Tests

func testSudoModePersistence() {
    TestRunner.suite("Sudo Mode Persistence Tests")

    // Clean state
    UserDefaults.standard.removeObject(forKey: "sudoModeEnabled")

    // Enable sudo mode
    UserDefaults.standard.sudoModeEnabled = true

    // Synchronize to ensure persistence
    UserDefaults.standard.synchronize()

    // Read back
    TestRunner.assertTrue(
        UserDefaults.standard.sudoModeEnabled,
        "Sudo mode persists after synchronize"
    )

    // Disable and verify
    UserDefaults.standard.sudoModeEnabled = false
    UserDefaults.standard.synchronize()

    TestRunner.assertFalse(
        UserDefaults.standard.sudoModeEnabled,
        "Disabled sudo mode persists after synchronize"
    )

    // Clean up
    UserDefaults.standard.removeObject(forKey: "sudoModeEnabled")
}

// MARK: - Sudo Mode Single Tool Tests

func testSudoModeSingleTool() {
    TestRunner.suite("Sudo Mode Single Tool Tests")

    let manager = MockToolApprovalManager()

    // Enable sudo mode
    UserDefaults.standard.sudoModeEnabled = true

    // Test with single tool
    let toolCall = MockToolCall(toolName: "dangerous_shell_rm", connectorID: "shell")
    let result = manager.requestApproval(for: [toolCall])

    TestRunner.assertEqual(
        result.approvedIds.count, 1,
        "Single tool is approved"
    )
    TestRunner.assertTrue(
        result.approvedIds.contains(toolCall.id),
        "Correct tool ID is in approved set"
    )
    TestRunner.assertEqual(
        result.decisions.count, 1,
        "Single decision is created"
    )
    TestRunner.assertEqual(
        result.decisions.first?.toolName, "dangerous_shell_rm",
        "Decision has correct tool name"
    )

    // Clean up
    UserDefaults.standard.removeObject(forKey: "sudoModeEnabled")
}

// MARK: - Main Entry Point

@main
struct SudoModeTests {
    static func main() {
        print("\u{1F9EA} Sudo Mode Tests")
        print(String(repeating: "=", count: 50))

        testSudoModeDefaultState()
        testSudoModeToggle()
        testSudoModeBypassesApproval()
        testSudoModeEmptyToolList()
        testSudoModePersistence()
        testSudoModeSingleTool()

        TestRunner.printSummary()

        // Clean up after all tests
        UserDefaults.standard.removeObject(forKey: "sudoModeEnabled")

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
