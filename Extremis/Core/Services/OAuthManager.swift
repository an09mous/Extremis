// MARK: - OAuth Manager
// Central service for OAuth 2.1 flows with PKCE

import Foundation
import CryptoKit
import AppKit

/// Manages OAuth 2.1 authentication flows for MCP servers
@MainActor
final class OAuthManager: ObservableObject {

    // MARK: - Singleton

    static let shared = OAuthManager()

    // MARK: - Published State

    /// Current OAuth flows in progress (by server ID)
    @Published private(set) var activeFlows: [UUID: OAuthFlowState] = [:]

    /// Connection status for each OAuth-enabled server
    @Published private(set) var connectionStatus: [UUID: OAuthConnectionStatus] = [:]

    // MARK: - Dependencies

    private let secretsStorage: ConnectorSecretsStorage

    // MARK: - Initialization

    init(secretsStorage: ConnectorSecretsStorage = .shared) {
        self.secretsStorage = secretsStorage
    }

    // MARK: - Public Interface

    /// Start OAuth authorization flow for a server
    /// - Parameters:
    ///   - serverID: The server's UUID
    ///   - config: OAuth configuration
    /// - Returns: The obtained OAuth tokens
    func authorize(serverID: UUID, config: OAuthConfig) async throws -> OAuthTokens {
        // Validate configuration
        let errors = config.validate()
        guard errors.isEmpty else {
            throw OAuthError.configurationInvalid(errors.joined(separator: ", "))
        }

        // Update status
        connectionStatus[serverID] = .connecting

        do {
            // Generate PKCE parameters
            let codeVerifier = generateCodeVerifier()
            let codeChallenge = generateCodeChallenge(from: codeVerifier)
            let state = generateState()

            // Start callback server
            let callbackServer = OAuthCallbackServer()

            // Start server in background and get port
            let serverTask = Task {
                try await callbackServer.waitForCallback()
            }

            // Wait a moment for server to start
            try await Task.sleep(nanoseconds: 200_000_000)  // 200ms

            let port = await callbackServer.listeningPort
            guard port > 0 else {
                throw OAuthError.callbackServerFailed("Failed to start callback server")
            }

            let redirectUri = config.redirectUri ?? "http://127.0.0.1:\(port)/callback"

            // Store flow state
            let flowState = OAuthFlowState(
                state: state,
                codeVerifier: codeVerifier,
                codeChallenge: codeChallenge,
                redirectUri: redirectUri,
                callbackPort: port,
                serverID: serverID
            )
            activeFlows[serverID] = flowState

            // Build authorization URL
            let authURL = buildAuthorizationURL(
                config: config,
                state: state,
                codeChallenge: codeChallenge,
                redirectUri: redirectUri
            )

            // Open browser for authorization
            NSWorkspace.shared.open(authURL)
            print("🔐 OAuth: Opened browser for authorization")

            // Wait for callback
            let callbackResult = try await serverTask.value

            // Verify state matches
            guard callbackResult.state == state else {
                activeFlows.removeValue(forKey: serverID)
                connectionStatus[serverID] = .error("State mismatch")
                throw OAuthError.stateMismatch
            }

            // Exchange code for tokens
            let tokens = try await exchangeCodeForTokens(
                config: config,
                code: callbackResult.code,
                codeVerifier: codeVerifier,
                redirectUri: redirectUri
            )

            // Store tokens in Keychain
            try saveTokens(tokens, forServer: serverID)

            // Update status
            activeFlows.removeValue(forKey: serverID)
            connectionStatus[serverID] = .connected

            print("🔐 OAuth: Successfully obtained tokens for server \(serverID)")
            return tokens

        } catch is CancellationError {
            activeFlows.removeValue(forKey: serverID)
            connectionStatus[serverID] = .disconnected
            throw OAuthError.userCancelled

        } catch {
            activeFlows.removeValue(forKey: serverID)
            connectionStatus[serverID] = .error(error.localizedDescription)
            throw error
        }
    }

    /// Refresh tokens for a server
    /// - Parameters:
    ///   - serverID: The server's UUID
    ///   - config: OAuth configuration
    /// - Returns: The refreshed tokens
    func refreshTokens(serverID: UUID, config: OAuthConfig) async throws -> OAuthTokens {
        guard let existingTokens = loadTokens(forServer: serverID) else {
            throw OAuthError.noTokensAvailable
        }

        guard let refreshToken = existingTokens.refreshToken else {
            throw OAuthError.tokenRefreshFailed("No refresh token available")
        }

        connectionStatus[serverID] = .connecting

        do {
            let tokens = try await performTokenRefresh(
                config: config,
                refreshToken: refreshToken
            )

            // Store refreshed tokens
            try saveTokens(tokens, forServer: serverID)
            connectionStatus[serverID] = .connected

            print("🔐 OAuth: Successfully refreshed tokens for server \(serverID)")
            return tokens

        } catch {
            connectionStatus[serverID] = .error(error.localizedDescription)
            throw error
        }
    }

    /// Get valid tokens for a server, refreshing if needed
    /// - Parameters:
    ///   - serverID: The server's UUID
    ///   - config: OAuth configuration (needed for refresh)
    /// - Returns: Valid OAuth tokens, or nil if unavailable
    func getValidTokens(serverID: UUID, config: OAuthConfig) async -> OAuthTokens? {
        guard let tokens = loadTokens(forServer: serverID) else {
            connectionStatus[serverID] = .disconnected
            return nil
        }

        // If tokens are valid, return them
        if !tokens.isExpired {
            connectionStatus[serverID] = .connected
            return tokens
        }

        // Try to refresh
        if tokens.canRefresh {
            connectionStatus[serverID] = .expired
            do {
                return try await refreshTokens(serverID: serverID, config: config)
            } catch {
                print("🔐 OAuth: Token refresh failed: \(error.localizedDescription)")
                // Fall through to return nil
            }
        }

        connectionStatus[serverID] = .expired
        return nil
    }

    /// Check if a server has valid tokens
    func hasValidTokens(serverID: UUID) -> Bool {
        guard let tokens = loadTokens(forServer: serverID) else {
            return false
        }
        return !tokens.isExpired
    }

    /// Disconnect (revoke tokens) for a server
    func disconnect(serverID: UUID) {
        deleteTokens(forServer: serverID)
        activeFlows.removeValue(forKey: serverID)
        connectionStatus[serverID] = .disconnected
        print("🔐 OAuth: Disconnected server \(serverID)")
    }

    /// Cancel an in-progress OAuth flow
    func cancelFlow(serverID: UUID) {
        activeFlows.removeValue(forKey: serverID)
        connectionStatus[serverID] = .disconnected
    }

    /// Get connection status for a server
    func getStatus(serverID: UUID) -> OAuthConnectionStatus {
        connectionStatus[serverID] ?? .disconnected
    }

    // MARK: - PKCE Generation

    /// Generate a cryptographically random code verifier (43-128 characters)
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// Generate code challenge from code verifier using S256 method
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    /// Generate a random state parameter for CSRF protection
    private func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    // MARK: - URL Building

    /// Build the authorization URL with all required parameters
    private func buildAuthorizationURL(
        config: OAuthConfig,
        state: String,
        codeChallenge: String,
        redirectUri: String
    ) -> URL {
        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: true)!

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: config.scopeString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        // Add resource parameter per RFC 8707 if available
        // This binds the token to the intended MCP server
        if let resourceUri = config.resourceUri {
            queryItems.append(URLQueryItem(name: "resource", value: resourceUri.absoluteString))
        }

        // Add existing query items from the endpoint URL
        if let existingItems = components.queryItems {
            queryItems.append(contentsOf: existingItems)
        }

        components.queryItems = queryItems
        return components.url!
    }

    // MARK: - Token Exchange

    /// Exchange authorization code for tokens
    private func exchangeCodeForTokens(
        config: OAuthConfig,
        code: String,
        codeVerifier: String,
        redirectUri: String
    ) async throws -> OAuthTokens {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var bodyParams: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
            "client_id": config.clientId,
            "code_verifier": codeVerifier
        ]

        // Add resource parameter per RFC 8707 if available
        if let resourceUri = config.resourceUri {
            bodyParams["resource"] = resourceUri.absoluteString
        }

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            // Try to parse error response
            if let errorResponse = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                throw OAuthError.tokenExchangeFailed(errorResponse.localizedDescription)
            }
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode)")
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        return OAuthTokens(from: tokenResponse)
    }

    /// Refresh tokens using refresh token
    private func performTokenRefresh(
        config: OAuthConfig,
        refreshToken: String
    ) async throws -> OAuthTokens {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let bodyParams: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId
        ]

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenRefreshFailed("Invalid response")
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
                throw OAuthError.tokenRefreshFailed(errorResponse.localizedDescription)
            }
            throw OAuthError.tokenRefreshFailed("HTTP \(httpResponse.statusCode)")
        }

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        return OAuthTokens(from: tokenResponse)
    }

    // MARK: - Token Storage

    /// Save tokens to Keychain via ConnectorSecretsStorage
    private func saveTokens(_ tokens: OAuthTokens, forServer serverID: UUID) throws {
        let existingSecrets = (try? secretsStorage.loadSecrets(forCustomServer: serverID)) ?? .empty
        let updatedSecrets = ConnectorSecrets(
            secretEnvVars: existingSecrets.secretEnvVars,
            secretHeaders: existingSecrets.secretHeaders,
            additionalSecrets: existingSecrets.additionalSecrets,
            oauthTokens: tokens
        )
        try secretsStorage.saveSecrets(updatedSecrets, forCustomServer: serverID)
    }

    /// Load tokens from Keychain
    private func loadTokens(forServer serverID: UUID) -> OAuthTokens? {
        (try? secretsStorage.loadSecrets(forCustomServer: serverID))?.oauthTokens
    }

    /// Delete tokens from Keychain
    private func deleteTokens(forServer serverID: UUID) {
        guard let existingSecrets = try? secretsStorage.loadSecrets(forCustomServer: serverID) else { return }
        let updatedSecrets = ConnectorSecrets(
            secretEnvVars: existingSecrets.secretEnvVars,
            secretHeaders: existingSecrets.secretHeaders,
            additionalSecrets: existingSecrets.additionalSecrets,
            oauthTokens: nil
        )
        try? secretsStorage.saveSecrets(updatedSecrets, forCustomServer: serverID)
    }

    // MARK: - Discovered OAuth Config Storage

    /// In-memory cache of auto-discovered OAuth configs (indexed by server ID)
    /// These are cached for the session but not persisted since they can be re-discovered
    private var discoveredConfigs: [UUID: OAuthConfig] = [:]

    /// Store a discovered OAuth config for a server
    func storeDiscoveredConfig(serverID: UUID, config: OAuthConfig) {
        discoveredConfigs[serverID] = config
        print("🔐 OAuth: Stored discovered config for server \(serverID)")
    }

    /// Get a previously discovered OAuth config for a server
    func getDiscoveredConfig(serverID: UUID) -> OAuthConfig? {
        discoveredConfigs[serverID]
    }

    /// Clear the discovered config for a server (e.g., when disconnecting)
    func clearDiscoveredConfig(serverID: UUID) {
        discoveredConfigs.removeValue(forKey: serverID)
    }

    /// Get the effective OAuth config for a server
    /// Returns either the discovered config or the manually configured one
    func getEffectiveOAuthConfig(serverID: UUID, httpConfig: HTTPConfig) -> OAuthConfig? {
        // Prefer manually configured OAuth
        if let manualConfig = httpConfig.oauth {
            return manualConfig
        }

        // Fall back to discovered config
        return discoveredConfigs[serverID]
    }
}

// MARK: - Data Extension for Base64URL

extension Data {
    /// Base64URL encoding (URL-safe, no padding)
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
