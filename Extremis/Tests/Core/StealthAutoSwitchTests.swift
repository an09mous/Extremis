// MARK: - Stealth Auto-Switch Tests
// Tests for automatic session switching when stealth mode is deactivated

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

// MARK: - Lightweight Entry for Testing

struct SwitchTestEntry {
    let id: UUID
    let title: String
    let isStealth: Bool
    let isArchived: Bool
    let updatedAt: Date

    init(title: String, isStealth: Bool = false, isArchived: Bool = false, minutesAgo: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isStealth = isStealth
        self.isArchived = isArchived
        self.updatedAt = Date().addingTimeInterval(TimeInterval(-minutesAgo * 60))
    }
}

// MARK: - Auto-Switch Logic (mirrors the actual implementation)

/// Determine which session to switch to when stealth is deactivated
/// Returns the ID of the session to switch to, or nil if no switch is needed
func determineSessionAfterStealthDisable(
    currentSessionIsStealth: Bool,
    sessions: [SwitchTestEntry]
) -> UUID? {
    // If current session is not stealth, no switch needed
    guard currentSessionIsStealth else { return nil }

    // Find the most recent non-stealth, non-archived session
    let normalSessions = sessions
        .filter { !$0.isStealth && !$0.isArchived }
        .sorted { $0.updatedAt > $1.updatedAt }

    return normalSessions.first?.id
}

// MARK: - Tests

func testStealthDisableWithStealthSession() {
    TestRunner.setGroup("Stealth disable — active stealth session switches to most recent normal")

    let normal1 = SwitchTestEntry(title: "Normal Old", minutesAgo: 10)
    let normal2 = SwitchTestEntry(title: "Normal Recent", minutesAgo: 1)
    let stealth1 = SwitchTestEntry(title: "Stealth", isStealth: true, minutesAgo: 5)

    let sessions = [normal1, normal2, stealth1]
    let switchTo = determineSessionAfterStealthDisable(
        currentSessionIsStealth: true,
        sessions: sessions
    )

    TestRunner.assertNotNil(switchTo, "Should switch to a session")
    TestRunner.assertEqual(switchTo, normal2.id, "Switches to most recent normal session")
}

func testStealthDisableWithNormalSession() {
    TestRunner.setGroup("Stealth disable — active normal session stays (no switch)")

    let normal1 = SwitchTestEntry(title: "Normal")
    let stealth1 = SwitchTestEntry(title: "Stealth", isStealth: true)

    let sessions = [normal1, stealth1]
    let switchTo = determineSessionAfterStealthDisable(
        currentSessionIsStealth: false,
        sessions: sessions
    )

    TestRunner.assertNil(switchTo, "No switch needed — current is normal")
}

func testStealthDisableNoNormalSessions() {
    TestRunner.setGroup("Stealth disable — no normal sessions available (clear)")

    let stealth1 = SwitchTestEntry(title: "Stealth 1", isStealth: true)
    let stealth2 = SwitchTestEntry(title: "Stealth 2", isStealth: true)

    let sessions = [stealth1, stealth2]
    let switchTo = determineSessionAfterStealthDisable(
        currentSessionIsStealth: true,
        sessions: sessions
    )

    TestRunner.assertNil(switchTo, "No normal sessions — returns nil (clear active)")
}

func testStealthDisableIgnoresArchived() {
    TestRunner.setGroup("Stealth disable — ignores archived normal sessions")

    let archived = SwitchTestEntry(title: "Normal Archived", isArchived: true, minutesAgo: 1)
    let stealth1 = SwitchTestEntry(title: "Stealth", isStealth: true)

    let sessions = [archived, stealth1]
    let switchTo = determineSessionAfterStealthDisable(
        currentSessionIsStealth: true,
        sessions: sessions
    )

    TestRunner.assertNil(switchTo, "Archived normal session not eligible — returns nil")
}

func testStealthEnableNoSwitch() {
    TestRunner.setGroup("Stealth enable — no session change")

    // Stealth enable should never trigger a switch
    // The current session stays as-is (FR-007)
    let normal1 = SwitchTestEntry(title: "Normal")
    let sessions = [normal1]

    // We test this by verifying the function returns nil when currentSession is NOT stealth
    // (because on enable, the current session is always a normal one)
    let switchTo = determineSessionAfterStealthDisable(
        currentSessionIsStealth: false,
        sessions: sessions
    )

    TestRunner.assertNil(switchTo, "Stealth enable: no switch (current stays)")
}

func testStealthDisableEmptySessionList() {
    TestRunner.setGroup("Stealth disable — empty session list")

    let switchTo = determineSessionAfterStealthDisable(
        currentSessionIsStealth: true,
        sessions: []
    )

    TestRunner.assertNil(switchTo, "Empty list — returns nil (clear active)")
}

// MARK: - Entry Point

@main
struct StealthAutoSwitchTests {
    static func main() {
        testStealthDisableWithStealthSession()
        testStealthDisableWithNormalSession()
        testStealthDisableNoNormalSessions()
        testStealthDisableIgnoresArchived()
        testStealthEnableNoSwitch()
        testStealthDisableEmptySessionList()
        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
