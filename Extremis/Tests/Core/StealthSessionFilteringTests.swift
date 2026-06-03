// MARK: - Stealth Session Filtering Tests
// Tests for session visibility filtering based on stealth mode state

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

// MARK: - Lightweight Session Entry for Testing

struct FilterTestEntry: Equatable {
    let id: UUID
    let title: String
    let isStealth: Bool
    let isArchived: Bool
    let updatedAt: Date

    init(title: String, isStealth: Bool = false, isArchived: Bool = false, updatedAt: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.isStealth = isStealth
        self.isArchived = isArchived
        self.updatedAt = updatedAt
    }
}

// MARK: - Filtering Logic (mirrors the actual implementation)

/// Filter sessions for visibility based on stealth mode state
/// This is the pure function extracted from the sidebar view for testability
func visibleSessions(sessions: [FilterTestEntry], isStealthActive: Bool) -> [FilterTestEntry] {
    let active = sessions.filter { !$0.isArchived }
    if isStealthActive {
        return active  // Show all (stealth + normal)
    } else {
        return active.filter { !$0.isStealth }  // Hide stealth sessions
    }
}

// MARK: - Tests

func testFilterStealthActiveShowsAll() {
    TestRunner.setGroup("Stealth active — shows all sessions")

    let sessions = [
        FilterTestEntry(title: "Normal 1"),
        FilterTestEntry(title: "Stealth 1", isStealth: true),
        FilterTestEntry(title: "Normal 2"),
        FilterTestEntry(title: "Stealth 2", isStealth: true),
    ]

    let result = visibleSessions(sessions: sessions, isStealthActive: true)
    TestRunner.assertEqual(result.count, 4, "Stealth active: all 4 sessions visible")
    TestRunner.assertTrue(result.contains { $0.title == "Stealth 1" }, "Stealth 1 visible")
    TestRunner.assertTrue(result.contains { $0.title == "Stealth 2" }, "Stealth 2 visible")
    TestRunner.assertTrue(result.contains { $0.title == "Normal 1" }, "Normal 1 visible")
    TestRunner.assertTrue(result.contains { $0.title == "Normal 2" }, "Normal 2 visible")
}

func testFilterStealthInactiveHidesStealth() {
    TestRunner.setGroup("Stealth inactive — hides stealth sessions")

    let sessions = [
        FilterTestEntry(title: "Normal 1"),
        FilterTestEntry(title: "Stealth 1", isStealth: true),
        FilterTestEntry(title: "Normal 2"),
        FilterTestEntry(title: "Stealth 2", isStealth: true),
    ]

    let result = visibleSessions(sessions: sessions, isStealthActive: false)
    TestRunner.assertEqual(result.count, 2, "Stealth inactive: only 2 normal sessions visible")
    TestRunner.assertTrue(result.contains { $0.title == "Normal 1" }, "Normal 1 visible")
    TestRunner.assertTrue(result.contains { $0.title == "Normal 2" }, "Normal 2 visible")
    TestRunner.assertFalse(result.contains { $0.title == "Stealth 1" }, "Stealth 1 hidden")
    TestRunner.assertFalse(result.contains { $0.title == "Stealth 2" }, "Stealth 2 hidden")
}

func testFilterNoStealthSessions() {
    TestRunner.setGroup("No stealth sessions — same in both modes")

    let sessions = [
        FilterTestEntry(title: "Normal 1"),
        FilterTestEntry(title: "Normal 2"),
        FilterTestEntry(title: "Normal 3"),
    ]

    let stealthOn = visibleSessions(sessions: sessions, isStealthActive: true)
    let stealthOff = visibleSessions(sessions: sessions, isStealthActive: false)
    TestRunner.assertEqual(stealthOn.count, 3, "Stealth on: all 3 normal sessions")
    TestRunner.assertEqual(stealthOff.count, 3, "Stealth off: all 3 normal sessions")
}

func testFilterAllStealthSessions() {
    TestRunner.setGroup("All stealth sessions — empty in normal mode")

    let sessions = [
        FilterTestEntry(title: "Stealth 1", isStealth: true),
        FilterTestEntry(title: "Stealth 2", isStealth: true),
    ]

    let stealthOn = visibleSessions(sessions: sessions, isStealthActive: true)
    let stealthOff = visibleSessions(sessions: sessions, isStealthActive: false)
    TestRunner.assertEqual(stealthOn.count, 2, "Stealth on: both stealth sessions visible")
    TestRunner.assertEqual(stealthOff.count, 0, "Stealth off: empty list")
}

func testFilterExcludesArchived() {
    TestRunner.setGroup("Archived sessions excluded in both modes")

    let sessions = [
        FilterTestEntry(title: "Normal Active"),
        FilterTestEntry(title: "Stealth Active", isStealth: true),
        FilterTestEntry(title: "Normal Archived", isArchived: true),
        FilterTestEntry(title: "Stealth Archived", isStealth: true, isArchived: true),
    ]

    let stealthOn = visibleSessions(sessions: sessions, isStealthActive: true)
    let stealthOff = visibleSessions(sessions: sessions, isStealthActive: false)
    TestRunner.assertEqual(stealthOn.count, 2, "Stealth on: 2 active sessions (archived excluded)")
    TestRunner.assertEqual(stealthOff.count, 1, "Stealth off: 1 normal active session")
    TestRunner.assertTrue(stealthOff.first?.title == "Normal Active", "Only normal active visible")
}

func testFilterEmptyList() {
    TestRunner.setGroup("Empty session list")

    let sessions: [FilterTestEntry] = []
    let stealthOn = visibleSessions(sessions: sessions, isStealthActive: true)
    let stealthOff = visibleSessions(sessions: sessions, isStealthActive: false)
    TestRunner.assertEqual(stealthOn.count, 0, "Stealth on: empty")
    TestRunner.assertEqual(stealthOff.count, 0, "Stealth off: empty")
}

// MARK: - Entry Point

@main
struct StealthSessionFilteringTests {
    static func main() {
        testFilterStealthActiveShowsAll()
        testFilterStealthInactiveHidesStealth()
        testFilterNoStealthSessions()
        testFilterAllStealthSessions()
        testFilterExcludesArchived()
        testFilterEmptyList()
        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
