// MARK: - OAuth Discovery
// Auto-discovery of OAuth endpoints per MCP Authorization Specification
// Implements RFC 9728 (Protected Resource Metadata) and RFC 8414 (Authorization Server Metadata)

import Foundation

// MARK: - Discovery Types

/// Protected Resource Metadata (RFC 9728)
/// Returned by MCP servers to indicate their authorization requirements
struct ProtectedResourceMetadata: Codable {
    /// The resource identifier (canonical URI of the MCP server)
    let resource: URL?

    /// List of authorization server URLs that can issue tokens for this resource
    let authorizationServers: [URL]

    /// Scopes supported by this resource
    let scopesSupported: [String]?

    /// Bearer token authentication methods supported
    let bearerMethodsSupported: [String]?

    private enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case scopesSupported = "scopes_supported"
        case bearerMethodsSupported = "bearer_methods_supported"
    }
}

/// Authorization Server Metadata (RFC 8414)
/// Returned by authorization servers to describe their endpoints and capabilities
struct AuthorizationServerMetadata: Codable {
    /// The authorization server's issuer identifier
    let issuer: URL

    /// URL of the authorization endpoint
    let authorizationEndpoint: URL

    /// URL of the token endpoint
    let tokenEndpoint: URL

    /// URL of the userinfo endpoint (optional)
    let userinfoEndpoint: URL?

    /// URL of the JWKS endpoint (optional)
    let jwksUri: URL?

    /// URL of the registration endpoint for dynamic client registration (optional)
    let registrationEndpoint: URL?

    /// Scopes supported by this authorization server
    let scopesSupported: [String]?

    /// Response types supported
    let responseTypesSupported: [String]?

    /// Grant types supported
    let grantTypesSupported: [String]?

    /// Code challenge methods supported (for PKCE)
    let codeChallengeMethodsSupported: [String]?

    /// Whether Client ID Metadata Documents are supported
    let clientIdMetadataDocumentSupported: Bool?

    private enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case userinfoEndpoint = "userinfo_endpoint"
        case jwksUri = "jwks_uri"
        case registrationEndpoint = "registration_endpoint"
        case scopesSupported = "scopes_supported"
        case responseTypesSupported = "response_types_supported"
        case grantTypesSupported = "grant_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case clientIdMetadataDocumentSupported = "client_id_metadata_document_supported"
    }
}

/// Discovered OAuth configuration from auto-discovery
struct DiscoveredOAuthConfig {
    /// The authorization server metadata
    let authServerMetadata: AuthorizationServerMetadata

    /// The protected resource metadata (optional)
    let resourceMetadata: ProtectedResourceMetadata?

    /// Scopes to request (from WWW-Authenticate or resource metadata)
    let recommendedScopes: [String]

    /// The resource URI to include in authorization requests (RFC 8707)
    let resourceUri: URL

    /// Convert to OAuthConfig for use with OAuthManager
    func toOAuthConfig(clientId: String, accessTokenEnvVar: String? = nil) -> OAuthConfig {
        OAuthConfig(
            authorizationEndpoint: authServerMetadata.authorizationEndpoint,
            tokenEndpoint: authServerMetadata.tokenEndpoint,
            clientId: clientId,
            scopes: recommendedScopes,
            accessTokenEnvVar: accessTokenEnvVar
        )
    }
}

// MARK: - OAuth Discovery Service

/// Service for auto-discovering OAuth endpoints from MCP servers
/// Implements the MCP Authorization Specification discovery flow
actor OAuthDiscoveryService {

    // MARK: - Singleton

    static let shared = OAuthDiscoveryService()

    // MARK: - Properties

    private let urlSession: URLSession

    // MARK: - Initialization

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - Discovery Methods

    /// Discover OAuth configuration for an MCP server
    /// This implements the full MCP authorization discovery flow:
    /// 1. Make unauthenticated request to get 401 with WWW-Authenticate
    /// 2. Extract resource_metadata URL from WWW-Authenticate header
    /// 3. Fetch Protected Resource Metadata to get authorization server(s)
    /// 4. Fetch Authorization Server Metadata to get endpoints
    func discoverOAuthConfig(for serverURL: URL) async throws -> DiscoveredOAuthConfig {
        // Step 1: Make unauthenticated request to trigger 401
        let (wwwAuthenticateHeader, scopeFromHeader) = try await triggerAuthChallenge(serverURL: serverURL)

        // Step 2: Get Protected Resource Metadata
        let resourceMetadata = try await fetchResourceMetadata(
            serverURL: serverURL,
            wwwAuthenticateHeader: wwwAuthenticateHeader
        )

        // Step 3: Get first authorization server
        guard let authServerURL = resourceMetadata.authorizationServers.first else {
            throw OAuthDiscoveryError.noAuthorizationServer
        }

        // Step 4: Fetch Authorization Server Metadata
        let authServerMetadata = try await fetchAuthServerMetadata(issuer: authServerURL)

        // Validate PKCE support
        if let methods = authServerMetadata.codeChallengeMethodsSupported {
            guard methods.contains("S256") else {
                throw OAuthDiscoveryError.pkceNotSupported
            }
        } else {
            // If not specified, we must refuse per MCP spec
            throw OAuthDiscoveryError.pkceNotSupported
        }

        // Determine scopes to request (priority: WWW-Authenticate > scopes_supported)
        let scopes: [String]
        if let scopeFromHeader = scopeFromHeader, !scopeFromHeader.isEmpty {
            scopes = scopeFromHeader.split(separator: " ").map(String.init)
        } else if let supportedScopes = resourceMetadata.scopesSupported, !supportedScopes.isEmpty {
            scopes = supportedScopes
        } else if let supportedScopes = authServerMetadata.scopesSupported, !supportedScopes.isEmpty {
            scopes = supportedScopes
        } else {
            scopes = []
        }

        return DiscoveredOAuthConfig(
            authServerMetadata: authServerMetadata,
            resourceMetadata: resourceMetadata,
            recommendedScopes: scopes,
            resourceUri: serverURL
        )
    }

    /// Check if an MCP server supports OAuth auto-discovery
    func supportsAutoDiscovery(serverURL: URL) async -> Bool {
        do {
            _ = try await discoverOAuthConfig(for: serverURL)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private Methods

    /// Make an unauthenticated request to trigger a 401 response
    /// Returns the WWW-Authenticate header value and extracted scope
    private func triggerAuthChallenge(serverURL: URL) async throws -> (wwwAuthenticate: String?, scope: String?) {
        var request = URLRequest(url: serverURL)
        request.httpMethod = "GET"

        let (_, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthDiscoveryError.invalidResponse
        }

        // We expect a 401 Unauthorized
        guard httpResponse.statusCode == 401 else {
            // If we get 200, the server might not require auth
            if httpResponse.statusCode == 200 {
                throw OAuthDiscoveryError.authNotRequired
            }
            throw OAuthDiscoveryError.unexpectedStatusCode(httpResponse.statusCode)
        }

        // Extract WWW-Authenticate header
        let wwwAuth = httpResponse.value(forHTTPHeaderField: "WWW-Authenticate")

        // Parse scope from WWW-Authenticate if present
        let scope = parseWWWAuthenticateParam(wwwAuth, param: "scope")

        return (wwwAuth, scope)
    }

    /// Fetch Protected Resource Metadata (RFC 9728)
    private func fetchResourceMetadata(
        serverURL: URL,
        wwwAuthenticateHeader: String?
    ) async throws -> ProtectedResourceMetadata {
        // Try to get resource_metadata URL from WWW-Authenticate header first
        if let wwwAuth = wwwAuthenticateHeader,
           let metadataURLString = parseWWWAuthenticateParam(wwwAuth, param: "resource_metadata"),
           let metadataURL = URL(string: metadataURLString) {
            return try await fetchMetadata(from: metadataURL)
        }

        // Fallback to well-known URI probing
        // Try path-specific first, then root
        let wellKnownURLs = buildWellKnownURLs(for: serverURL)

        for url in wellKnownURLs {
            do {
                return try await fetchMetadata(from: url)
            } catch {
                continue
            }
        }

        throw OAuthDiscoveryError.resourceMetadataNotFound
    }

    /// Build well-known URLs for Protected Resource Metadata
    private func buildWellKnownURLs(for serverURL: URL) -> [URL] {
        var urls: [URL] = []

        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: true) else {
            return urls
        }

        let originalPath = components.path

        // Try with path: /.well-known/oauth-protected-resource/path
        if !originalPath.isEmpty && originalPath != "/" {
            let pathWithoutLeadingSlash = originalPath.hasPrefix("/") ? String(originalPath.dropFirst()) : originalPath
            components.path = "/.well-known/oauth-protected-resource/\(pathWithoutLeadingSlash)"
            if let url = components.url {
                urls.append(url)
            }
        }

        // Try root: /.well-known/oauth-protected-resource
        components.path = "/.well-known/oauth-protected-resource"
        if let url = components.url {
            urls.append(url)
        }

        return urls
    }

    /// Fetch metadata from a URL and decode as ProtectedResourceMetadata
    private func fetchMetadata(from url: URL) async throws -> ProtectedResourceMetadata {
        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthDiscoveryError.metadataFetchFailed
        }

        return try JSONDecoder().decode(ProtectedResourceMetadata.self, from: data)
    }

    /// Fetch Authorization Server Metadata (RFC 8414)
    private func fetchAuthServerMetadata(issuer: URL) async throws -> AuthorizationServerMetadata {
        // Try multiple well-known endpoints per MCP spec
        let wellKnownURLs = buildAuthServerWellKnownURLs(for: issuer)

        for url in wellKnownURLs {
            do {
                let request = URLRequest(url: url)
                let (data, response) = try await urlSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }

                return try JSONDecoder().decode(AuthorizationServerMetadata.self, from: data)
            } catch {
                continue
            }
        }

        throw OAuthDiscoveryError.authServerMetadataNotFound
    }

    /// Build well-known URLs for Authorization Server Metadata
    private func buildAuthServerWellKnownURLs(for issuer: URL) -> [URL] {
        var urls: [URL] = []

        guard var components = URLComponents(url: issuer, resolvingAgainstBaseURL: true) else {
            return urls
        }

        let originalPath = components.path

        if !originalPath.isEmpty && originalPath != "/" {
            // With path: try insertion methods
            let pathWithoutLeadingSlash = originalPath.hasPrefix("/") ? String(originalPath.dropFirst()) : originalPath

            // OAuth 2.0 with path insertion
            components.path = "/.well-known/oauth-authorization-server/\(pathWithoutLeadingSlash)"
            if let url = components.url {
                urls.append(url)
            }

            // OpenID Connect with path insertion
            components.path = "/.well-known/openid-configuration/\(pathWithoutLeadingSlash)"
            if let url = components.url {
                urls.append(url)
            }

            // OpenID Connect path appending
            components.path = "\(originalPath)/.well-known/openid-configuration"
            if let url = components.url {
                urls.append(url)
            }
        } else {
            // Without path: standard well-known locations
            // OAuth 2.0
            components.path = "/.well-known/oauth-authorization-server"
            if let url = components.url {
                urls.append(url)
            }

            // OpenID Connect
            components.path = "/.well-known/openid-configuration"
            if let url = components.url {
                urls.append(url)
            }
        }

        return urls
    }

    /// Parse a parameter from WWW-Authenticate header
    /// Format: Bearer realm="...", resource_metadata="...", scope="..."
    private func parseWWWAuthenticateParam(_ header: String?, param: String) -> String? {
        guard let header = header else { return nil }

        // Simple regex-free parsing
        // Look for param="value" or param=value
        let pattern = "\(param)="
        guard let range = header.range(of: pattern, options: .caseInsensitive) else {
            return nil
        }

        let afterParam = header[range.upperBound...]

        // Check if value is quoted
        if afterParam.hasPrefix("\"") {
            // Find closing quote
            let valueStart = afterParam.index(after: afterParam.startIndex)
            if let endQuote = afterParam[valueStart...].firstIndex(of: "\"") {
                return String(afterParam[valueStart..<endQuote])
            }
        } else {
            // Unquoted value - take until comma or whitespace
            let endIndex = afterParam.firstIndex(where: { $0 == "," || $0 == " " }) ?? afterParam.endIndex
            return String(afterParam[..<endIndex])
        }

        return nil
    }
}

// MARK: - Discovery Errors

enum OAuthDiscoveryError: LocalizedError {
    case invalidResponse
    case authNotRequired
    case unexpectedStatusCode(Int)
    case resourceMetadataNotFound
    case metadataFetchFailed
    case noAuthorizationServer
    case authServerMetadataNotFound
    case pkceNotSupported
    case discoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .authNotRequired:
            return "Server does not require authentication"
        case .unexpectedStatusCode(let code):
            return "Unexpected status code: \(code)"
        case .resourceMetadataNotFound:
            return "Could not find Protected Resource Metadata"
        case .metadataFetchFailed:
            return "Failed to fetch metadata from server"
        case .noAuthorizationServer:
            return "No authorization server specified in metadata"
        case .authServerMetadataNotFound:
            return "Could not find Authorization Server Metadata"
        case .pkceNotSupported:
            return "Authorization server does not support PKCE (required by MCP)"
        case .discoveryFailed(let reason):
            return "OAuth discovery failed: \(reason)"
        }
    }
}
