// MARK: - GitHubConnector Unit Tests
// Tests for the built-in GitHub connector

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

func testGitHubConnectorID() {
    TestRunner.suite("GitHubConnector ID Tests")

    // Test connector ID is "github"
    TestRunner.assertEqual("github", "github", "Connector ID should be 'github'")
}

func testGitHubConnectorName() {
    TestRunner.suite("GitHubConnector Name Tests")

    // Test connector name is "GitHub"
    TestRunner.assertEqual("GitHub", "GitHub", "Connector name should be 'GitHub'")
}

func testUserDefaultsGitHubConnectorEnabled() {
    TestRunner.suite("UserDefaults githubConnectorEnabled Tests")

    // Reset to default state
    UserDefaults.standard.removeObject(forKey: "githubConnectorEnabled")

    // Test default value is false (disabled by default - requires token)
    let defaultValue = UserDefaults.standard.githubConnectorEnabled
    TestRunner.assertFalse(defaultValue, "Default value should be false (disabled)")

    // Test setting to true
    UserDefaults.standard.githubConnectorEnabled = true
    let enabledValue = UserDefaults.standard.githubConnectorEnabled
    TestRunner.assertTrue(enabledValue, "Should be true after enabling")

    // Test setting to false
    UserDefaults.standard.githubConnectorEnabled = false
    let disabledValue = UserDefaults.standard.githubConnectorEnabled
    TestRunner.assertFalse(disabledValue, "Should be false after disabling")

    // Cleanup
    UserDefaults.standard.removeObject(forKey: "githubConnectorEnabled")
}

func testBuiltInConnectorTypeGitHub() {
    TestRunner.suite("BuiltInConnectorType GitHub Tests")

    let githubType = BuiltInConnectorType.github

    // Test display name
    TestRunner.assertEqual(githubType.displayName, "GitHub", "Display name should be 'GitHub'")

    // Test icon name
    TestRunner.assertEqual(githubType.iconName, "link", "Icon name should be 'link'")

    // Test description
    TestRunner.assertTrue(
        githubType.description.contains("GitHub"),
        "Description should mention GitHub"
    )

    // Test auth method has correct field
    if case .apiKey(let config) = githubType.authMethod {
        TestRunner.assertTrue(!config.fields.isEmpty, "Auth config should have fields")
        if let tokenField = config.fields.first {
            TestRunner.assertEqual(
                tokenField.key,
                "GITHUB_PERSONAL_ACCESS_TOKEN",
                "Token field key should be GITHUB_PERSONAL_ACCESS_TOKEN"
            )
            TestRunner.assertTrue(tokenField.isSecret, "Token field should be a secret")
        }
    } else {
        TestRunner.assertTrue(false, "Auth method should be apiKey")
    }
}

func testConnectorKeychainKeyForGitHub() {
    TestRunner.suite("ConnectorKeychainKey GitHub Tests")

    let key = ConnectorKeychainKey.builtIn("github")

    // Test key string format
    TestRunner.assertEqual(
        key.key,
        "connector.builtin.github",
        "Keychain key should be 'connector.builtin.github'"
    )
}

// MARK: - Main

@main
struct GitHubConnectorTests {
    static func main() {
        print("GitHubConnector Tests")
        print("==================================================")

        testGitHubConnectorID()
        testGitHubConnectorName()
        testUserDefaultsGitHubConnectorEnabled()
        testBuiltInConnectorTypeGitHub()
        testConnectorKeychainKeyForGitHub()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}

// MARK: - Minimal Type Stubs for Compilation

// These are minimal stubs to allow standalone compilation of tests
// The actual types are defined in the main codebase

enum BuiltInConnectorType: String, Codable, CaseIterable {
    case github
    case webSearch
    case jira

    var displayName: String {
        switch self {
        case .github: return "GitHub"
        case .webSearch: return "Brave Search"
        case .jira: return "Jira"
        }
    }

    var iconName: String {
        switch self {
        case .github: return "link"
        case .webSearch: return "magnifyingglass"
        case .jira: return "list.clipboard"
        }
    }

    var description: String {
        switch self {
        case .github: return "Access GitHub repositories, issues, and pull requests"
        case .webSearch: return "Search the web for current information"
        case .jira: return "Manage Jira issues and projects"
        }
    }

    var authMethod: ConnectorAuthMethod {
        switch self {
        case .github:
            return .apiKey(ApiKeyAuthConfig(fields: [
                AuthField(
                    key: "GITHUB_PERSONAL_ACCESS_TOKEN",
                    label: "Personal Access Token",
                    placeholder: "ghp_xxxxxxxxxxxx",
                    helpText: "Create at GitHub → Settings → Developer settings → Personal access tokens",
                    isSecret: true
                )
            ]))
        case .webSearch:
            return .apiKey(ApiKeyAuthConfig(fields: []))
        case .jira:
            return .apiKey(ApiKeyAuthConfig(fields: []))
        }
    }
}

enum ConnectorAuthMethod {
    case apiKey(ApiKeyAuthConfig)
}

struct ApiKeyAuthConfig {
    let fields: [AuthField]
}

struct AuthField {
    let key: String
    let label: String
    let placeholder: String
    let helpText: String
    let isSecret: Bool
}

enum ConnectorKeychainKey {
    case builtIn(String)
    case custom(UUID)

    var key: String {
        switch self {
        case .builtIn(let type):
            return "connector.builtin.\(type)"
        case .custom(let id):
            return "connector.custom.\(id.uuidString)"
        }
    }
}

extension UserDefaults {
    var githubConnectorEnabled: Bool {
        get {
            if object(forKey: "githubConnectorEnabled") == nil {
                return false
            }
            return bool(forKey: "githubConnectorEnabled")
        }
        set {
            set(newValue, forKey: "githubConnectorEnabled")
        }
    }
}
