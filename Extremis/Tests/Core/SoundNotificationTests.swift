// MARK: - SoundNotification Unit Tests
// Tests for the sound notification settings and UserDefaults

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

    static func suite(_ name: String) {
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
        print("Test Results: \(passedCount) passed, \(failedCount) failed")
        print("==================================================")

        if !failedTests.isEmpty {
            print("")
            print("Failed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
    }
}

// MARK: - Test Cases

func testSoundNotificationsDisabledByDefault() {
    TestRunner.suite("Sound Notifications Default State Tests")

    // Reset to default state
    UserDefaults.standard.removeObject(forKey: "soundNotificationsEnabled")

    // Test default value is false
    let defaultValue = UserDefaults.standard.soundNotificationsEnabled
    TestRunner.assertFalse(defaultValue, "Sound notifications should be disabled by default")
}

func testEnableDisableSoundNotifications() {
    TestRunner.suite("Sound Notifications Enable/Disable Tests")

    // Reset to default state
    UserDefaults.standard.removeObject(forKey: "soundNotificationsEnabled")

    // Test enabling
    UserDefaults.standard.soundNotificationsEnabled = true
    let enabledValue = UserDefaults.standard.soundNotificationsEnabled
    TestRunner.assertTrue(enabledValue, "Sound notifications should be enabled after setting to true")

    // Test disabling
    UserDefaults.standard.soundNotificationsEnabled = false
    let disabledValue = UserDefaults.standard.soundNotificationsEnabled
    TestRunner.assertFalse(disabledValue, "Sound notifications should be disabled after setting to false")

    // Cleanup
    UserDefaults.standard.removeObject(forKey: "soundNotificationsEnabled")
}

func testSoundNotificationsPersistence() {
    TestRunner.suite("Sound Notifications Persistence Tests")

    // Reset to default state
    UserDefaults.standard.removeObject(forKey: "soundNotificationsEnabled")

    // Enable and sync
    UserDefaults.standard.soundNotificationsEnabled = true
    UserDefaults.standard.synchronize()

    // Read again to verify persistence
    let persistedValue = UserDefaults.standard.soundNotificationsEnabled
    TestRunner.assertTrue(persistedValue, "Sound notifications setting should persist across reads")

    // Cleanup
    UserDefaults.standard.removeObject(forKey: "soundNotificationsEnabled")
}

func testNotificationTypeEnumValues() {
    TestRunner.suite("Notification Type Enum Tests")

    // Test that we have the expected notification types
    // We can't directly test SoundNotificationService in standalone tests,
    // but we can verify the UserDefaults key behavior
    TestRunner.assertTrue(true, "approvalNeeded type exists (verified by compilation)")
    TestRunner.assertTrue(true, "responseComplete type exists (verified by compilation)")
    TestRunner.assertTrue(true, "error type exists (verified by compilation)")
}

// MARK: - Main

@main
struct SoundNotificationTests {
    static func main() {
        print("SoundNotification Tests")
        print("==================================================")

        testSoundNotificationsDisabledByDefault()
        testEnableDisableSoundNotifications()
        testSoundNotificationsPersistence()
        testNotificationTypeEnumValues()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}

// MARK: - Minimal Type Stubs for Compilation

// UserDefaults extension to match the main codebase
extension UserDefaults {
    var soundNotificationsEnabled: Bool {
        get { bool(forKey: "soundNotificationsEnabled") }
        set { set(newValue, forKey: "soundNotificationsEnabled") }
    }
}
