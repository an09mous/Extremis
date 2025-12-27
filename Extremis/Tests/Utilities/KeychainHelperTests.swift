// MARK: - KeychainHelper Unit Tests
// Standalone test runner for KeychainHelper functionality
// Uses a separate test service to avoid interfering with production keychain data

import Foundation
import Security

/// Simple test framework for running without XCTest
struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []

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
            let message = "Expected nil but got '\(value!)'"
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
        if !condition {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected false but got true"))
            print("  ✗ \(testName): Expected false but got true")
        }
    }

    static func assertNoThrow(_ block: () throws -> Void, _ testName: String) {
        do {
            try block()
            passedCount += 1
            print("  ✓ \(testName)")
        } catch {
            failedCount += 1
            failedTests.append((testName, "Unexpected error: \(error)"))
            print("  ✗ \(testName): Unexpected error: \(error)")
        }
    }

    static func printSummary() -> Bool {
        print("\n" + String(repeating: "=", count: 50))
        print("TEST SUMMARY")
        print(String(repeating: "=", count: 50))
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("\nFailed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print(String(repeating: "=", count: 50))
        return failedCount == 0
    }
}

// MARK: - Test KeychainHelper (Isolated for Testing)

/// A test version of KeychainHelper that uses a separate service name
final class TestKeychainHelper {
    private let service: String
    private let keychainAccount = "api_keys"
    private var apiKeys: [String: String] = [:]
    private var isLoaded: Bool = false

    init(service: String = "com.extremis.test") {
        self.service = service
        loadFromKeychain()
    }

    private func loadFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        isLoaded = true

        switch status {
        case errSecSuccess:
            if let data = result as? Data,
               let dict = try? JSONDecoder().decode([String: String].self, from: data) {
                apiKeys = dict
            }
        case errSecItemNotFound:
            apiKeys = [:]
        default:
            apiKeys = [:]
        }
    }

    private func saveToKeychain() throws {
        guard let data = try? JSONEncoder().encode(apiKeys) else {
            throw NSError(domain: "KeychainHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode"])
        }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        if !apiKeys.isEmpty {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: keychainAccount,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw NSError(domain: "KeychainHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Save failed: \(status)"])
            }
        }
    }

    func store(key: String, value: String) throws {
        apiKeys[key] = value
        try saveToKeychain()
    }

    func retrieve(key: String) -> String? {
        return apiKeys[key]
    }

    func delete(key: String) throws {
        apiKeys.removeValue(forKey: key)
        try saveToKeychain()
    }

    func exists(key: String) -> Bool {
        return apiKeys[key] != nil && !apiKeys[key]!.isEmpty
    }

    func clear() throws {
        apiKeys = [:]
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }

    var allKeys: [String] {
        return Array(apiKeys.keys)
    }
}

// MARK: - Test Cases

struct KeychainHelperTests {
    let helper: TestKeychainHelper

    init() {
        helper = TestKeychainHelper(service: "com.extremis.test.\(UUID().uuidString)")
    }

    func cleanup() {
        try? helper.clear()
    }

    // MARK: - Store Tests

    func testStoreAndRetrieve() {
        TestRunner.assertNoThrow({
            try helper.store(key: "test_key", value: "test_value")
        }, "Store: No error thrown")

        let retrieved = helper.retrieve(key: "test_key")
        TestRunner.assertEqual(retrieved, "test_value", "Retrieve: Value matches stored")
    }

    func testStoreMultipleKeys() {
        TestRunner.assertNoThrow({
            try helper.store(key: "key1", value: "value1")
            try helper.store(key: "key2", value: "value2")
            try helper.store(key: "key3", value: "value3")
        }, "Store: Multiple keys without error")

        TestRunner.assertEqual(helper.retrieve(key: "key1"), "value1", "Retrieve: key1 correct")
        TestRunner.assertEqual(helper.retrieve(key: "key2"), "value2", "Retrieve: key2 correct")
        TestRunner.assertEqual(helper.retrieve(key: "key3"), "value3", "Retrieve: key3 correct")
    }

    func testStoreOverwritesExisting() {
        TestRunner.assertNoThrow({
            try helper.store(key: "overwrite_key", value: "original")
            try helper.store(key: "overwrite_key", value: "updated")
        }, "Store: Overwrite without error")

        TestRunner.assertEqual(helper.retrieve(key: "overwrite_key"), "updated", "Retrieve: Value updated")
    }

    // MARK: - Retrieve Tests

    func testRetrieveNonExistent() {
        let result = helper.retrieve(key: "nonexistent_key")
        TestRunner.assertNil(result, "Retrieve: Non-existent key returns nil")
    }

    // MARK: - Delete Tests

    func testDelete() {
        TestRunner.assertNoThrow({
            try helper.store(key: "delete_key", value: "to_be_deleted")
        }, "Delete: Setup - store key")

        TestRunner.assertTrue(helper.exists(key: "delete_key"), "Delete: Key exists before delete")

        TestRunner.assertNoThrow({
            try helper.delete(key: "delete_key")
        }, "Delete: No error thrown")

        TestRunner.assertFalse(helper.exists(key: "delete_key"), "Delete: Key gone after delete")
        TestRunner.assertNil(helper.retrieve(key: "delete_key"), "Delete: Retrieve returns nil")
    }

    func testDeleteNonExistent() {
        TestRunner.assertNoThrow({
            try helper.delete(key: "never_existed")
        }, "Delete: Non-existent key doesn't throw")
    }

    func testDeletePreservesOtherKeys() {
        TestRunner.assertNoThrow({
            try helper.store(key: "keep1", value: "value1")
            try helper.store(key: "delete_me", value: "bye")
            try helper.store(key: "keep2", value: "value2")
            try helper.delete(key: "delete_me")
        }, "Delete: Setup and delete middle key")

        TestRunner.assertEqual(helper.retrieve(key: "keep1"), "value1", "Delete: keep1 preserved")
        TestRunner.assertEqual(helper.retrieve(key: "keep2"), "value2", "Delete: keep2 preserved")
        TestRunner.assertNil(helper.retrieve(key: "delete_me"), "Delete: deleted key gone")
    }

    // MARK: - Exists Tests

    func testExistsTrue() {
        try? helper.store(key: "exists_key", value: "exists_value")
        TestRunner.assertTrue(helper.exists(key: "exists_key"), "Exists: Returns true for existing key")
    }

    func testExistsFalse() {
        TestRunner.assertFalse(helper.exists(key: "not_exists"), "Exists: Returns false for non-existing key")
    }

    func testExistsEmptyValue() {
        try? helper.store(key: "empty_key", value: "")
        TestRunner.assertFalse(helper.exists(key: "empty_key"), "Exists: Returns false for empty string value")
    }

    // MARK: - Edge Cases

    func testSpecialCharactersInValue() {
        let specialValue = "sk-abc123!@#$%^&*()_+-=[]{}|;':\",./<>?"
        TestRunner.assertNoThrow({
            try helper.store(key: "special_key", value: specialValue)
        }, "Special: Store special chars without error")

        TestRunner.assertEqual(helper.retrieve(key: "special_key"), specialValue, "Special: Retrieved value matches")
    }

    func testUnicodeInValue() {
        let unicodeValue = "Hello 世界 🌍 émoji café"
        TestRunner.assertNoThrow({
            try helper.store(key: "unicode_key", value: unicodeValue)
        }, "Unicode: Store unicode without error")

        TestRunner.assertEqual(helper.retrieve(key: "unicode_key"), unicodeValue, "Unicode: Retrieved value matches")
    }

    func testLongValue() {
        let longValue = String(repeating: "a", count: 10000)
        TestRunner.assertNoThrow({
            try helper.store(key: "long_key", value: longValue)
        }, "Long: Store 10KB value without error")

        let retrieved = helper.retrieve(key: "long_key")
        TestRunner.assertEqual(retrieved?.count, 10000, "Long: Retrieved value length correct")
    }

    func testSpecialCharactersInKey() {
        TestRunner.assertNoThrow({
            try helper.store(key: "api_key_OpenAI", value: "openai_value")
            try helper.store(key: "api_key_Anthropic", value: "anthropic_value")
        }, "KeyFormat: Store provider-style keys")

        TestRunner.assertEqual(helper.retrieve(key: "api_key_OpenAI"), "openai_value", "KeyFormat: OpenAI key works")
        TestRunner.assertEqual(helper.retrieve(key: "api_key_Anthropic"), "anthropic_value", "KeyFormat: Anthropic key works")
    }

    // MARK: - Persistence Tests

    func testPersistenceAcrossInstances() {
        let service = "com.extremis.test.persistence.\(UUID().uuidString)"

        // First instance - store
        let helper1 = TestKeychainHelper(service: service)
        TestRunner.assertNoThrow({
            try helper1.store(key: "persist_key", value: "persist_value")
        }, "Persistence: Store in first instance")

        // Second instance - should load from keychain
        let helper2 = TestKeychainHelper(service: service)
        TestRunner.assertEqual(helper2.retrieve(key: "persist_key"), "persist_value", "Persistence: Second instance retrieves value")

        // Cleanup
        try? helper2.clear()
    }

    // MARK: - Run All Tests

    func runAll() {
        print("\n🧪 KeychainHelper Unit Tests")
        print(String(repeating: "=", count: 50))

        print("\n📦 Store Tests")
        print(String(repeating: "-", count: 40))
        testStoreAndRetrieve()
        cleanup()

        testStoreMultipleKeys()
        cleanup()

        testStoreOverwritesExisting()
        cleanup()

        print("\n📦 Retrieve Tests")
        print(String(repeating: "-", count: 40))
        testRetrieveNonExistent()
        cleanup()

        print("\n📦 Delete Tests")
        print(String(repeating: "-", count: 40))
        testDelete()
        cleanup()

        testDeleteNonExistent()
        cleanup()

        testDeletePreservesOtherKeys()
        cleanup()

        print("\n📦 Exists Tests")
        print(String(repeating: "-", count: 40))
        testExistsTrue()
        cleanup()

        testExistsFalse()
        cleanup()

        testExistsEmptyValue()
        cleanup()

        print("\n📦 Edge Case Tests")
        print(String(repeating: "-", count: 40))
        testSpecialCharactersInValue()
        cleanup()

        testUnicodeInValue()
        cleanup()

        testLongValue()
        cleanup()

        testSpecialCharactersInKey()
        cleanup()

        print("\n📦 Persistence Tests")
        print(String(repeating: "-", count: 40))
        testPersistenceAcrossInstances()
    }
}

// MARK: - Main Entry Point

@main
struct KeychainHelperTestRunner {
    static func main() {
        let tests = KeychainHelperTests()
        tests.runAll()

        let success = TestRunner.printSummary()
        exit(success ? 0 : 1)
    }
}

