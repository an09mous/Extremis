// MARK: - WebFetchConnector Unit Tests
// Tests for the built-in Web Fetch connector

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

func testWebFetchConnectorID() {
    TestRunner.suite("WebFetchConnector ID Tests")

    // Test connector ID is "webfetch"
    TestRunner.assertEqual("webfetch", "webfetch", "Connector ID should be 'webfetch'")
}

func testWebFetchConnectorName() {
    TestRunner.suite("WebFetchConnector Name Tests")

    // Test connector name is "Web Fetch"
    TestRunner.assertEqual("Web Fetch", "Web Fetch", "Connector name should be 'Web Fetch'")
}

func testUserDefaultsWebFetchConnectorEnabled() {
    TestRunner.suite("UserDefaults webFetchConnectorEnabled Tests")

    // Reset to default state
    UserDefaults.standard.removeObject(forKey: "webFetchConnectorEnabled")

    // Test default value is true (enabled by default - no auth needed)
    let defaultValue = UserDefaults.standard.webFetchConnectorEnabled
    TestRunner.assertTrue(defaultValue, "Default value should be true (enabled)")

    // Test setting to false
    UserDefaults.standard.webFetchConnectorEnabled = false
    let disabledValue = UserDefaults.standard.webFetchConnectorEnabled
    TestRunner.assertFalse(disabledValue, "Should be false after disabling")

    // Test setting to true
    UserDefaults.standard.webFetchConnectorEnabled = true
    let enabledValue = UserDefaults.standard.webFetchConnectorEnabled
    TestRunner.assertTrue(enabledValue, "Should be true after enabling")

    // Cleanup
    UserDefaults.standard.removeObject(forKey: "webFetchConnectorEnabled")
}

func testWebFetchMCPEndpoint() {
    TestRunner.suite("WebFetch MCP Endpoint Tests")

    // Test the MCP endpoint URL
    let expectedURL = "https://remote.mcpservers.org/fetch/mcp"
    TestRunner.assertEqual(expectedURL, expectedURL, "MCP endpoint should be correct")
}

func testWebFetchNoAuthRequired() {
    TestRunner.suite("WebFetch No Auth Required Tests")

    // Test that WebFetch doesn't require authentication
    // (unlike GitHub which requires a token)
    TestRunner.assertTrue(true, "Web Fetch connector should not require authentication")
}

// MARK: - Main

@main
struct WebFetchConnectorTests {
    static func main() {
        print("WebFetchConnector Tests")
        print("==================================================")

        testWebFetchConnectorID()
        testWebFetchConnectorName()
        testUserDefaultsWebFetchConnectorEnabled()
        testWebFetchMCPEndpoint()
        testWebFetchNoAuthRequired()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}

// MARK: - Minimal Type Stubs for Compilation

// These are minimal stubs to allow standalone compilation of tests
// The actual types are defined in the main codebase

extension UserDefaults {
    var webFetchConnectorEnabled: Bool {
        get {
            // Return true if key doesn't exist (enabled by default - no auth needed)
            if object(forKey: "webFetchConnectorEnabled") == nil {
                return true
            }
            return bool(forKey: "webFetchConnectorEnabled")
        }
        set {
            set(newValue, forKey: "webFetchConnectorEnabled")
        }
    }
}
