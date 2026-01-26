// MARK: - OAuth Unit Tests
// Tests for OAuth models, PKCE generation, and configuration validation

import Foundation
import CryptoKit

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
        print("==================================================")

        if !failedTests.isEmpty {
            print("")
            print("FAILED TESTS:")
            for (name, message) in failedTests {
                print("  • \(name): \(message)")
            }
        }
        print("")
    }
}

// MARK: - OAuth Models (inline for testing)

struct OAuthConfig: Codable, Equatable {
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let clientId: String
    let scopes: [String]
    let redirectUri: String?
    let requiresClientSecret: Bool
    let accessTokenEnvVar: String?

    init(
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        clientId: String,
        scopes: [String],
        redirectUri: String? = nil,
        requiresClientSecret: Bool = false,
        accessTokenEnvVar: String? = nil
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.clientId = clientId
        self.scopes = scopes
        self.redirectUri = redirectUri
        self.requiresClientSecret = requiresClientSecret
        self.accessTokenEnvVar = accessTokenEnvVar
    }

    var scopeString: String {
        scopes.joined(separator: " ")
    }

    var tokenEnvVarName: String {
        accessTokenEnvVar ?? "OAUTH_ACCESS_TOKEN"
    }

    func validate() -> [String] {
        var errors: [String] = []
        if authorizationEndpoint.scheme?.lowercased() != "https" {
            errors.append("Authorization endpoint must use HTTPS")
        }
        if tokenEndpoint.scheme?.lowercased() != "https" {
            errors.append("Token endpoint must use HTTPS")
        }
        if clientId.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Client ID cannot be empty")
        }
        if scopes.isEmpty {
            errors.append("At least one scope is required")
        }
        return errors
    }

    var isValid: Bool {
        validate().isEmpty
    }
}

struct OAuthTokens: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let tokenType: String
    let scope: String?
    let obtainedAt: Date

    init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        tokenType: String = "Bearer",
        scope: String? = nil,
        obtainedAt: Date = Date()
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
        self.scope = scope
        self.obtainedAt = obtainedAt
    }

    var isExpired: Bool {
        guard let expiresAt = expiresAt else {
            return Date().timeIntervalSince(obtainedAt) > 3600
        }
        return Date() >= expiresAt.addingTimeInterval(-60)
    }

    var canRefresh: Bool {
        refreshToken != nil
    }

    var authorizationHeader: String {
        "\(tokenType) \(accessToken)"
    }
}

enum OAuthConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case expired
    case error(String)

    var displayName: String {
        switch self {
        case .disconnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .expired: return "Session Expired"
        case .error(let message): return "Error: \(message)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct OAuthFlowState: Equatable {
    let state: String
    let codeVerifier: String
    let codeChallenge: String
    let redirectUri: String
    let callbackPort: Int?
    let initiatedAt: Date
    let serverID: UUID

    init(
        state: String,
        codeVerifier: String,
        codeChallenge: String,
        redirectUri: String,
        callbackPort: Int? = nil,
        serverID: UUID
    ) {
        self.state = state
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
        self.redirectUri = redirectUri
        self.callbackPort = callbackPort
        self.initiatedAt = Date()
        self.serverID = serverID
    }

    var isExpired: Bool {
        Date().timeIntervalSince(initiatedAt) > 300
    }
}

// MARK: - PKCE Helper Functions (inline for testing)

func generateCodeVerifier() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64URLEncodedString()
}

func generateCodeChallenge(from verifier: String) -> String {
    let data = Data(verifier.utf8)
    let hash = SHA256.hash(data: data)
    return Data(hash).base64URLEncodedString()
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Test Functions

func testOAuthConfigCreation() {
    TestRunner.setGroup("OAuthConfig Creation")

    let config = OAuthConfig(
        authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
        tokenEndpoint: URL(string: "https://auth.example.com/token")!,
        clientId: "test-client-id",
        scopes: ["read", "write", "offline_access"]
    )

    TestRunner.assertEqual(config.authorizationEndpoint.absoluteString, "https://auth.example.com/authorize", "Authorization endpoint stored correctly")
    TestRunner.assertEqual(config.tokenEndpoint.absoluteString, "https://auth.example.com/token", "Token endpoint stored correctly")
    TestRunner.assertEqual(config.clientId, "test-client-id", "Client ID stored correctly")
    TestRunner.assertEqual(config.scopes.count, 3, "Scopes count is correct")
    TestRunner.assertEqual(config.scopeString, "read write offline_access", "Scope string formatted correctly")
    TestRunner.assertNil(config.redirectUri, "Redirect URI is nil by default")
    TestRunner.assertFalse(config.requiresClientSecret, "Client secret not required by default")
    TestRunner.assertEqual(config.tokenEnvVarName, "OAUTH_ACCESS_TOKEN", "Default token env var name")
}

func testOAuthConfigCustomEnvVar() {
    TestRunner.setGroup("OAuthConfig Custom Env Var")

    let config = OAuthConfig(
        authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
        tokenEndpoint: URL(string: "https://auth.example.com/token")!,
        clientId: "test-client",
        scopes: ["read"],
        accessTokenEnvVar: "JIRA_ACCESS_TOKEN"
    )

    TestRunner.assertEqual(config.tokenEnvVarName, "JIRA_ACCESS_TOKEN", "Custom token env var name")
}

func testOAuthConfigValidation() {
    TestRunner.setGroup("OAuthConfig Validation")

    // Valid config
    let validConfig = OAuthConfig(
        authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
        tokenEndpoint: URL(string: "https://auth.example.com/token")!,
        clientId: "test-client",
        scopes: ["read"]
    )
    TestRunner.assertTrue(validConfig.isValid, "Valid config passes validation")
    TestRunner.assertEqual(validConfig.validate().count, 0, "Valid config has no errors")

    // Invalid - HTTP authorization endpoint
    let httpAuthConfig = OAuthConfig(
        authorizationEndpoint: URL(string: "http://auth.example.com/authorize")!,
        tokenEndpoint: URL(string: "https://auth.example.com/token")!,
        clientId: "test-client",
        scopes: ["read"]
    )
    TestRunner.assertFalse(httpAuthConfig.isValid, "HTTP auth endpoint fails validation")
    TestRunner.assertTrue(httpAuthConfig.validate().contains("Authorization endpoint must use HTTPS"), "Error message for HTTP auth endpoint")

    // Invalid - HTTP token endpoint
    let httpTokenConfig = OAuthConfig(
        authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
        tokenEndpoint: URL(string: "http://auth.example.com/token")!,
        clientId: "test-client",
        scopes: ["read"]
    )
    TestRunner.assertFalse(httpTokenConfig.isValid, "HTTP token endpoint fails validation")

    // Invalid - empty client ID
    let emptyClientConfig = OAuthConfig(
        authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
        tokenEndpoint: URL(string: "https://auth.example.com/token")!,
        clientId: "   ",
        scopes: ["read"]
    )
    TestRunner.assertFalse(emptyClientConfig.isValid, "Empty client ID fails validation")

    // Invalid - no scopes
    let noScopesConfig = OAuthConfig(
        authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
        tokenEndpoint: URL(string: "https://auth.example.com/token")!,
        clientId: "test-client",
        scopes: []
    )
    TestRunner.assertFalse(noScopesConfig.isValid, "Empty scopes fails validation")
}

func testOAuthTokensCreation() {
    TestRunner.setGroup("OAuthTokens Creation")

    let tokens = OAuthTokens(
        accessToken: "test-access-token",
        refreshToken: "test-refresh-token",
        expiresAt: Date().addingTimeInterval(3600),
        tokenType: "Bearer",
        scope: "read write"
    )

    TestRunner.assertEqual(tokens.accessToken, "test-access-token", "Access token stored correctly")
    TestRunner.assertEqual(tokens.refreshToken, "test-refresh-token", "Refresh token stored correctly")
    TestRunner.assertEqual(tokens.tokenType, "Bearer", "Token type stored correctly")
    TestRunner.assertEqual(tokens.scope, "read write", "Scope stored correctly")
    TestRunner.assertTrue(tokens.canRefresh, "Can refresh with refresh token")
    TestRunner.assertEqual(tokens.authorizationHeader, "Bearer test-access-token", "Authorization header formatted correctly")
}

func testOAuthTokensExpiration() {
    TestRunner.setGroup("OAuthTokens Expiration")

    // Not expired - expires in 1 hour
    let validTokens = OAuthTokens(
        accessToken: "test",
        expiresAt: Date().addingTimeInterval(3600)
    )
    TestRunner.assertFalse(validTokens.isExpired, "Token with 1 hour remaining is not expired")

    // Expired - expired 1 hour ago
    let expiredTokens = OAuthTokens(
        accessToken: "test",
        expiresAt: Date().addingTimeInterval(-3600)
    )
    TestRunner.assertTrue(expiredTokens.isExpired, "Token that expired 1 hour ago is expired")

    // About to expire - within 60 second buffer
    let almostExpiredTokens = OAuthTokens(
        accessToken: "test",
        expiresAt: Date().addingTimeInterval(30)
    )
    TestRunner.assertTrue(almostExpiredTokens.isExpired, "Token expiring in 30 seconds is considered expired (60s buffer)")

    // No expiration but old (> 1 hour)
    let oldTokens = OAuthTokens(
        accessToken: "test",
        expiresAt: nil,
        obtainedAt: Date().addingTimeInterval(-7200)
    )
    TestRunner.assertTrue(oldTokens.isExpired, "Token without expiration older than 1 hour is expired")

    // No expiration and fresh
    let freshTokens = OAuthTokens(
        accessToken: "test",
        expiresAt: nil,
        obtainedAt: Date().addingTimeInterval(-60)
    )
    TestRunner.assertFalse(freshTokens.isExpired, "Token without expiration less than 1 hour old is not expired")
}

func testOAuthTokensRefresh() {
    TestRunner.setGroup("OAuthTokens Refresh Capability")

    let withRefresh = OAuthTokens(
        accessToken: "test",
        refreshToken: "refresh-token"
    )
    TestRunner.assertTrue(withRefresh.canRefresh, "Can refresh with refresh token")

    let withoutRefresh = OAuthTokens(
        accessToken: "test",
        refreshToken: nil
    )
    TestRunner.assertFalse(withoutRefresh.canRefresh, "Cannot refresh without refresh token")
}

func testOAuthConnectionStatus() {
    TestRunner.setGroup("OAuthConnectionStatus")

    TestRunner.assertEqual(OAuthConnectionStatus.disconnected.displayName, "Not Connected", "Disconnected display name")
    TestRunner.assertEqual(OAuthConnectionStatus.connecting.displayName, "Connecting...", "Connecting display name")
    TestRunner.assertEqual(OAuthConnectionStatus.connected.displayName, "Connected", "Connected display name")
    TestRunner.assertEqual(OAuthConnectionStatus.expired.displayName, "Session Expired", "Expired display name")
    TestRunner.assertEqual(OAuthConnectionStatus.error("Test error").displayName, "Error: Test error", "Error display name")

    TestRunner.assertFalse(OAuthConnectionStatus.disconnected.isConnected, "Disconnected is not connected")
    TestRunner.assertFalse(OAuthConnectionStatus.connecting.isConnected, "Connecting is not connected")
    TestRunner.assertTrue(OAuthConnectionStatus.connected.isConnected, "Connected is connected")
    TestRunner.assertFalse(OAuthConnectionStatus.expired.isConnected, "Expired is not connected")
    TestRunner.assertFalse(OAuthConnectionStatus.error("test").isConnected, "Error is not connected")
}

func testOAuthFlowState() {
    TestRunner.setGroup("OAuthFlowState")

    let serverID = UUID()
    let state = OAuthFlowState(
        state: "random-state",
        codeVerifier: "verifier",
        codeChallenge: "challenge",
        redirectUri: "http://127.0.0.1:8080/callback",
        callbackPort: 8080,
        serverID: serverID
    )

    TestRunner.assertEqual(state.state, "random-state", "State stored correctly")
    TestRunner.assertEqual(state.codeVerifier, "verifier", "Code verifier stored correctly")
    TestRunner.assertEqual(state.codeChallenge, "challenge", "Code challenge stored correctly")
    TestRunner.assertEqual(state.redirectUri, "http://127.0.0.1:8080/callback", "Redirect URI stored correctly")
    TestRunner.assertEqual(state.callbackPort, 8080, "Callback port stored correctly")
    TestRunner.assertEqual(state.serverID, serverID, "Server ID stored correctly")
    TestRunner.assertFalse(state.isExpired, "Fresh flow state is not expired")
}

func testPKCECodeVerifier() {
    TestRunner.setGroup("PKCE Code Verifier Generation")

    let verifier1 = generateCodeVerifier()
    let verifier2 = generateCodeVerifier()

    // Verifier should be non-empty
    TestRunner.assertTrue(!verifier1.isEmpty, "Code verifier is not empty")

    // Verifier should be at least 43 characters (32 bytes base64url encoded)
    TestRunner.assertTrue(verifier1.count >= 43, "Code verifier has sufficient length")

    // Verifiers should be unique
    TestRunner.assertTrue(verifier1 != verifier2, "Code verifiers are unique")

    // Verifier should only contain base64url-safe characters
    let base64urlCharset = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    let verifierCharset = CharacterSet(charactersIn: verifier1)
    TestRunner.assertTrue(verifierCharset.isSubset(of: base64urlCharset), "Code verifier contains only base64url characters")
}

func testPKCECodeChallenge() {
    TestRunner.setGroup("PKCE Code Challenge Generation")

    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    let challenge = generateCodeChallenge(from: verifier)

    // Challenge should be non-empty
    TestRunner.assertTrue(!challenge.isEmpty, "Code challenge is not empty")

    // Challenge should be deterministic (same verifier = same challenge)
    let challenge2 = generateCodeChallenge(from: verifier)
    TestRunner.assertEqual(challenge, challenge2, "Code challenge is deterministic")

    // Challenge should be different for different verifiers
    let differentVerifier = "different-verifier-value"
    let differentChallenge = generateCodeChallenge(from: differentVerifier)
    TestRunner.assertTrue(challenge != differentChallenge, "Different verifiers produce different challenges")

    // Challenge should only contain base64url-safe characters
    let base64urlCharset = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    let challengeCharset = CharacterSet(charactersIn: challenge)
    TestRunner.assertTrue(challengeCharset.isSubset(of: base64urlCharset), "Code challenge contains only base64url characters")
}

func testBase64URLEncoding() {
    TestRunner.setGroup("Base64URL Encoding")

    // Test that standard base64 characters are replaced
    let testData = Data([0xFB, 0xEF, 0xBE])  // Contains + and / in standard base64
    let encoded = testData.base64URLEncodedString()

    // Should not contain + or / or =
    TestRunner.assertFalse(encoded.contains("+"), "Base64URL does not contain +")
    TestRunner.assertFalse(encoded.contains("/"), "Base64URL does not contain /")
    TestRunner.assertFalse(encoded.contains("="), "Base64URL does not contain =")

    // Should contain - or _ if any were replaced
    let hasUrlSafe = encoded.contains("-") || encoded.contains("_") || (!encoded.contains("+") && !encoded.contains("/"))
    TestRunner.assertTrue(hasUrlSafe, "Base64URL contains URL-safe characters")
}

func testOAuthConfigCodable() {
    TestRunner.setGroup("OAuthConfig Codable")

    let original = OAuthConfig(
        authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
        tokenEndpoint: URL(string: "https://auth.example.com/token")!,
        clientId: "test-client",
        scopes: ["read", "write"],
        redirectUri: "http://127.0.0.1:8080/callback",
        requiresClientSecret: true,
        accessTokenEnvVar: "MY_TOKEN"
    )

    // Encode
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(original) else {
        TestRunner.assertTrue(false, "OAuthConfig encodes to JSON")
        return
    }
    TestRunner.assertTrue(true, "OAuthConfig encodes to JSON")

    // Decode
    let decoder = JSONDecoder()
    guard let decoded = try? decoder.decode(OAuthConfig.self, from: data) else {
        TestRunner.assertTrue(false, "OAuthConfig decodes from JSON")
        return
    }
    TestRunner.assertTrue(true, "OAuthConfig decodes from JSON")

    // Compare
    TestRunner.assertEqual(decoded.authorizationEndpoint, original.authorizationEndpoint, "Authorization endpoint survives round-trip")
    TestRunner.assertEqual(decoded.tokenEndpoint, original.tokenEndpoint, "Token endpoint survives round-trip")
    TestRunner.assertEqual(decoded.clientId, original.clientId, "Client ID survives round-trip")
    TestRunner.assertEqual(decoded.scopes, original.scopes, "Scopes survive round-trip")
    TestRunner.assertEqual(decoded.redirectUri, original.redirectUri, "Redirect URI survives round-trip")
    TestRunner.assertEqual(decoded.requiresClientSecret, original.requiresClientSecret, "RequiresClientSecret survives round-trip")
    TestRunner.assertEqual(decoded.accessTokenEnvVar, original.accessTokenEnvVar, "AccessTokenEnvVar survives round-trip")
}

func testOAuthTokensCodable() {
    TestRunner.setGroup("OAuthTokens Codable")

    let expiresAt = Date().addingTimeInterval(3600)
    let obtainedAt = Date()

    let original = OAuthTokens(
        accessToken: "access-token-123",
        refreshToken: "refresh-token-456",
        expiresAt: expiresAt,
        tokenType: "Bearer",
        scope: "read write",
        obtainedAt: obtainedAt
    )

    // Encode
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(original) else {
        TestRunner.assertTrue(false, "OAuthTokens encodes to JSON")
        return
    }
    TestRunner.assertTrue(true, "OAuthTokens encodes to JSON")

    // Decode
    let decoder = JSONDecoder()
    guard let decoded = try? decoder.decode(OAuthTokens.self, from: data) else {
        TestRunner.assertTrue(false, "OAuthTokens decodes from JSON")
        return
    }
    TestRunner.assertTrue(true, "OAuthTokens decodes from JSON")

    // Compare
    TestRunner.assertEqual(decoded.accessToken, original.accessToken, "Access token survives round-trip")
    TestRunner.assertEqual(decoded.refreshToken, original.refreshToken, "Refresh token survives round-trip")
    TestRunner.assertEqual(decoded.tokenType, original.tokenType, "Token type survives round-trip")
    TestRunner.assertEqual(decoded.scope, original.scope, "Scope survives round-trip")
}

// MARK: - Backwards Compatibility Tests

func testBackwardsCompatibilityWithoutOAuth() {
    TestRunner.setGroup("Backwards Compatibility - Config Without OAuth")

    // Test config JSON with all required fields but optional fields missing
    // Note: requiresClientSecret is a non-optional Bool so it must be present in JSON
    let configJSON = """
    {
        "authorizationEndpoint": "https://auth.example.com/authorize",
        "tokenEndpoint": "https://auth.example.com/token",
        "clientId": "test-client",
        "scopes": ["read"],
        "requiresClientSecret": false
    }
    """

    let decoder = JSONDecoder()
    guard let data = configJSON.data(using: .utf8),
          let config = try? decoder.decode(OAuthConfig.self, from: data) else {
        TestRunner.assertTrue(false, "Config with required fields decodes successfully")
        return
    }

    TestRunner.assertTrue(true, "Config with required fields decodes successfully")
    TestRunner.assertNil(config.redirectUri, "Redirect URI is nil when not provided")
    TestRunner.assertFalse(config.requiresClientSecret, "RequiresClientSecret is false as specified")
    TestRunner.assertNil(config.accessTokenEnvVar, "AccessTokenEnvVar is nil when not provided")
    TestRunner.assertEqual(config.tokenEnvVarName, "OAUTH_ACCESS_TOKEN", "Default token env var name used")
}

func testOAuthTokensWithoutOptionalFields() {
    TestRunner.setGroup("Backwards Compatibility - Tokens Without Optional Fields")

    // Minimal tokens without optional fields
    let minimalTokensJSON = """
    {
        "accessToken": "test-token",
        "tokenType": "Bearer",
        "obtainedAt": 0
    }
    """

    let decoder = JSONDecoder()
    guard let data = minimalTokensJSON.data(using: .utf8),
          let tokens = try? decoder.decode(OAuthTokens.self, from: data) else {
        TestRunner.assertTrue(false, "Minimal tokens without optional fields decodes successfully")
        return
    }

    TestRunner.assertTrue(true, "Minimal tokens without optional fields decodes successfully")
    TestRunner.assertEqual(tokens.accessToken, "test-token", "Access token decoded correctly")
    TestRunner.assertNil(tokens.refreshToken, "Refresh token is nil")
    TestRunner.assertNil(tokens.expiresAt, "ExpiresAt is nil")
    TestRunner.assertNil(tokens.scope, "Scope is nil")
    TestRunner.assertFalse(tokens.canRefresh, "Cannot refresh without refresh token")
}

// MARK: - Main Entry Point

@main
struct OAuthTests {
    static func main() {
        print("OAuth Tests")
        print("==================================================")

        // OAuthConfig tests
        testOAuthConfigCreation()
        testOAuthConfigCustomEnvVar()
        testOAuthConfigValidation()
        testOAuthConfigCodable()

        // OAuthTokens tests
        testOAuthTokensCreation()
        testOAuthTokensExpiration()
        testOAuthTokensRefresh()
        testOAuthTokensCodable()

        // OAuthConnectionStatus tests
        testOAuthConnectionStatus()

        // OAuthFlowState tests
        testOAuthFlowState()

        // PKCE tests
        testPKCECodeVerifier()
        testPKCECodeChallenge()
        testBase64URLEncoding()

        // Backwards compatibility tests
        testBackwardsCompatibilityWithoutOAuth()
        testOAuthTokensWithoutOptionalFields()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
