// MARK: - OAuth Models
// OAuth 2.1 configuration and token models for MCP server authentication

import Foundation

// MARK: - OAuth Configuration

/// OAuth 2.1 configuration for an MCP server
/// Used to define how to authenticate with OAuth-protected services
struct OAuthConfig: Codable, Equatable {
    /// Authorization endpoint URL (where user is redirected to login)
    let authorizationEndpoint: URL

    /// Token endpoint URL (where auth code is exchanged for tokens)
    let tokenEndpoint: URL

    /// OAuth client ID
    let clientId: String

    /// Required scopes for this service
    let scopes: [String]

    /// Optional custom redirect URI (defaults to localhost callback)
    let redirectUri: String?

    /// Optional client secret (for confidential clients - stored separately in Keychain)
    /// Most MCP clients are public clients and don't need this
    let requiresClientSecret: Bool

    /// Environment variable name to inject access token into (for STDIO transport)
    /// Defaults to "OAUTH_ACCESS_TOKEN"
    let accessTokenEnvVar: String?

    /// Resource URI for RFC 8707 Resource Indicators (optional)
    /// This is the canonical URI of the MCP server, used in authorization requests
    /// to bind tokens to their intended audience
    let resourceUri: URL?

    /// Whether this config was auto-discovered from the MCP server
    /// If true, endpoints may be refreshed via discovery if auth fails
    let autoDiscovered: Bool

    // MARK: - Initialization

    init(
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        clientId: String,
        scopes: [String],
        redirectUri: String? = nil,
        requiresClientSecret: Bool = false,
        accessTokenEnvVar: String? = nil,
        resourceUri: URL? = nil,
        autoDiscovered: Bool = false
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.clientId = clientId
        self.scopes = scopes
        self.redirectUri = redirectUri
        self.requiresClientSecret = requiresClientSecret
        self.accessTokenEnvVar = accessTokenEnvVar
        self.resourceUri = resourceUri
        self.autoDiscovered = autoDiscovered
    }

    // MARK: - Computed Properties

    /// Scopes as a space-separated string (OAuth format)
    var scopeString: String {
        scopes.joined(separator: " ")
    }

    /// Environment variable name for access token injection
    var tokenEnvVarName: String {
        accessTokenEnvVar ?? "OAUTH_ACCESS_TOKEN"
    }

    // MARK: - Validation

    /// Validate the OAuth configuration
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

// MARK: - OAuth Tokens

/// OAuth tokens received from the authorization server
struct OAuthTokens: Codable, Equatable {
    /// Access token for API calls
    let accessToken: String

    /// Refresh token for obtaining new access tokens
    let refreshToken: String?

    /// Token expiration date (nil if unknown)
    let expiresAt: Date?

    /// Token type (usually "Bearer")
    let tokenType: String

    /// Granted scopes (may differ from requested)
    let scope: String?

    /// When these tokens were obtained
    let obtainedAt: Date

    // MARK: - Initialization

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

    /// Create from token response
    init(from response: OAuthTokenResponse, obtainedAt: Date = Date()) {
        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken
        self.tokenType = response.tokenType ?? "Bearer"
        self.scope = response.scope
        self.obtainedAt = obtainedAt

        // Calculate expiration date from expires_in
        if let expiresIn = response.expiresIn {
            self.expiresAt = obtainedAt.addingTimeInterval(TimeInterval(expiresIn))
        } else {
            self.expiresAt = nil
        }
    }

    // MARK: - Token Status

    /// Whether the access token has expired
    var isExpired: Bool {
        guard let expiresAt = expiresAt else {
            // If we don't know expiration, assume valid but check age
            // Tokens older than 1 hour without expiration are considered stale
            return Date().timeIntervalSince(obtainedAt) > 3600
        }
        // Consider expired 60 seconds before actual expiration for safety
        return Date() >= expiresAt.addingTimeInterval(-60)
    }

    /// Whether we can attempt to refresh the token
    var canRefresh: Bool {
        refreshToken != nil
    }

    /// Time until expiration (nil if unknown or already expired)
    var timeUntilExpiration: TimeInterval? {
        guard let expiresAt = expiresAt else { return nil }
        let remaining = expiresAt.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    /// Authorization header value
    var authorizationHeader: String {
        "\(tokenType) \(accessToken)"
    }
}

// MARK: - OAuth Token Response

/// Response from the OAuth token endpoint
struct OAuthTokenResponse: Codable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

// MARK: - OAuth Error Response

/// Error response from OAuth endpoints
struct OAuthErrorResponse: Codable, Error {
    let error: String
    let errorDescription: String?
    let errorUri: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case errorUri = "error_uri"
    }

    var localizedDescription: String {
        if let description = errorDescription {
            return "\(error): \(description)"
        }
        return error
    }
}

// MARK: - OAuth State

/// State for an in-progress OAuth flow
struct OAuthFlowState: Equatable {
    /// Unique state parameter for CSRF protection
    let state: String

    /// PKCE code verifier (kept secret, used in token exchange)
    let codeVerifier: String

    /// PKCE code challenge (sent to auth server)
    let codeChallenge: String

    /// Redirect URI being used for this flow
    let redirectUri: String

    /// Port of local callback server (if using localhost)
    let callbackPort: Int?

    /// When this flow was initiated
    let initiatedAt: Date

    /// Server ID this flow is for
    let serverID: UUID

    // MARK: - Initialization

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

    /// Whether this flow has timed out (5 minutes)
    var isExpired: Bool {
        Date().timeIntervalSince(initiatedAt) > 300
    }
}

// MARK: - OAuth Connection Status

/// Connection status for an OAuth-enabled server
enum OAuthConnectionStatus: Equatable {
    /// Not connected - needs OAuth flow
    case disconnected

    /// OAuth flow in progress
    case connecting

    /// Connected with valid tokens
    case connected

    /// Tokens expired, can be refreshed
    case expired

    /// Error during OAuth flow or token refresh
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

// MARK: - OAuth Errors

/// Errors that can occur during OAuth operations
enum OAuthError: LocalizedError {
    case configurationInvalid(String)
    case callbackServerFailed(String)
    case authorizationFailed(String)
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case stateMismatch
    case flowExpired
    case noTokensAvailable
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .configurationInvalid(let reason):
            return "Invalid OAuth configuration: \(reason)"
        case .callbackServerFailed(let reason):
            return "Failed to start callback server: \(reason)"
        case .authorizationFailed(let reason):
            return "Authorization failed: \(reason)"
        case .tokenExchangeFailed(let reason):
            return "Token exchange failed: \(reason)"
        case .tokenRefreshFailed(let reason):
            return "Token refresh failed: \(reason)"
        case .stateMismatch:
            return "OAuth state mismatch - possible CSRF attack"
        case .flowExpired:
            return "OAuth flow timed out"
        case .noTokensAvailable:
            return "No OAuth tokens available"
        case .userCancelled:
            return "OAuth flow was cancelled"
        }
    }
}
