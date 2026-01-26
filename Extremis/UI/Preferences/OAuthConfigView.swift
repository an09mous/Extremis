// MARK: - OAuth Configuration View
// UI component for configuring OAuth settings for MCP servers

import SwiftUI

/// OAuth configuration mode
enum OAuthConfigMode: String, CaseIterable {
    case manual = "manual"
    case autoDiscovery = "auto"

    var displayName: String {
        switch self {
        case .manual: return "Manual Configuration"
        case .autoDiscovery: return "Auto-Discovery (MCP Servers)"
        }
    }

    var description: String {
        switch self {
        case .manual: return "Enter OAuth endpoints manually"
        case .autoDiscovery: return "Server provides OAuth endpoints automatically"
        }
    }
}

/// View for configuring OAuth settings
struct OAuthConfigView: View {
    @Binding var enabled: Bool
    @Binding var authorizationEndpoint: String
    @Binding var tokenEndpoint: String
    @Binding var clientId: String
    @Binding var scopes: String
    @Binding var accessTokenEnvVar: String

    /// Whether to use auto-discovery mode
    @State private var configMode: OAuthConfigMode = .manual

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Requires OAuth Authentication", isOn: $enabled)

            if enabled {
                oauthFieldsView
            }
        }
    }

    private var oauthFieldsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Configuration mode picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Configuration Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Mode", selection: $configMode) {
                    ForEach(OAuthConfigMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(configMode.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if configMode == .autoDiscovery {
                autoDiscoveryInfoView
            } else {
                manualConfigView
            }

            // Client ID (always required)
            VStack(alignment: .leading, spacing: 4) {
                Text("Client ID")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("your-client-id", text: $clientId)
                    .textFieldStyle(.roundedBorder)
                Text("OAuth application client ID (provided by the service)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Access Token Env Var (for STDIO)
            VStack(alignment: .leading, spacing: 4) {
                Text("Access Token Environment Variable")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("OAUTH_ACCESS_TOKEN", text: $accessTokenEnvVar)
                    .textFieldStyle(.roundedBorder)
                Text("Name of env var to inject access token into (for local servers)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Info box
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Label("OAuth Flow", systemImage: "lock.shield")
                        .font(.caption.bold())
                    Text("After saving, click 'Connect' in the server list to complete the OAuth flow. A browser window will open for authorization.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.leading, 20)
    }

    private var autoDiscoveryInfoView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("MCP Auto-Discovery", systemImage: "wand.and.stars")
                    .font(.caption.bold())
                    .foregroundColor(.blue)

                Text("This server implements the MCP Authorization Specification. OAuth endpoints will be discovered automatically when you connect.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("Supported servers include: Atlassian Rovo MCP Server, and other MCP-compliant OAuth servers.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var manualConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Authorization Endpoint
            VStack(alignment: .leading, spacing: 4) {
                Text("Authorization Endpoint")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://auth.example.com/authorize", text: $authorizationEndpoint)
                    .textFieldStyle(.roundedBorder)
                Text("URL where users are redirected to login")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Token Endpoint
            VStack(alignment: .leading, spacing: 4) {
                Text("Token Endpoint")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://auth.example.com/token", text: $tokenEndpoint)
                    .textFieldStyle(.roundedBorder)
                Text("URL where auth code is exchanged for tokens")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Scopes
            VStack(alignment: .leading, spacing: 4) {
                Text("Scopes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("read:jira-work write:jira-work offline_access", text: $scopes)
                    .textFieldStyle(.roundedBorder)
                Text("Space-separated list of OAuth scopes")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// View for OAuth connection status and actions
struct OAuthConnectionStatusView: View {
    let serverID: UUID
    let connector: CustomMCPConnector
    @ObservedObject var oauthManager: OAuthManager

    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            statusIcon

            // Status text
            Text(statusText)
                .font(.caption)
                .foregroundColor(statusColor)

            Spacer()

            // Action button
            if connector.requiresOAuth {
                actionButton
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: some View {
        Group {
            switch oauthManager.getStatus(serverID: serverID) {
            case .disconnected:
                Image(systemName: "lock")
                    .foregroundColor(.secondary)
            case .connecting:
                ProgressView()
                    .scaleEffect(0.7)
            case .connected:
                Image(systemName: "lock.open.fill")
                    .foregroundColor(.green)
            case .expired:
                Image(systemName: "exclamationmark.lock")
                    .foregroundColor(.orange)
            case .error:
                Image(systemName: "lock.slash")
                    .foregroundColor(.red)
            }
        }
    }

    private var statusText: String {
        oauthManager.getStatus(serverID: serverID).displayName
    }

    private var statusColor: Color {
        switch oauthManager.getStatus(serverID: serverID) {
        case .disconnected: return .secondary
        case .connecting: return .blue
        case .connected: return .green
        case .expired: return .orange
        case .error: return .red
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch oauthManager.getStatus(serverID: serverID) {
        case .disconnected, .expired, .error:
            Button("Connect") {
                Task { await connect() }
            }
            .disabled(isConnecting)

        case .connecting:
            Button("Cancel") {
                oauthManager.cancelFlow(serverID: serverID)
            }

        case .connected:
            Button("Disconnect") {
                connector.disconnectOAuth()
            }
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil

        do {
            _ = try await connector.startOAuthFlow()
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }
}
