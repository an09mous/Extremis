// MARK: - Add/Edit MCP Server Sheet
// Form for configuring custom MCP servers

import SwiftUI

/// Mode for the add/edit sheet
enum AddEditMCPServerMode: Identifiable {
    case add
    case edit(CustomMCPServerConfig)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let config):
            return config.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .add:
            return "Add MCP Server"
        case .edit:
            return "Edit MCP Server"
        }
    }

    var saveButtonTitle: String {
        switch self {
        case .add:
            return "Add"
        case .edit:
            return "Save"
        }
    }
}

struct AddEditMCPServerSheet: View {
    let mode: AddEditMCPServerMode
    let onSave: (CustomMCPServerConfig) -> Void
    let onCancel: () -> Void

    // Form state
    @State private var name: String = ""
    @State private var transportType: MCPTransportType = .stdio
    @State private var enabled: Bool = true

    // STDIO config
    @State private var command: String = ""
    @State private var args: String = ""
    @State private var envVars: String = ""

    // HTTP config
    @State private var url: String = ""
    @State private var headers: String = ""

    // API Keys (stored in Keychain)
    @State private var secretEnvVars: String = ""
    @State private var secretHeaders: String = ""

    // OAuth configuration
    @State private var oauthEnabled: Bool = false
    @State private var oauthUseAutoDiscovery: Bool = false  // For HTTP transport: use MCP auto-discovery
    @State private var oauthAuthorizationEndpoint: String = ""
    @State private var oauthTokenEndpoint: String = ""
    @State private var oauthClientId: String = ""
    @State private var oauthScopes: String = ""
    @State private var oauthAccessTokenEnvVar: String = "OAUTH_ACCESS_TOKEN"

    // Validation
    @State private var validationErrors: [String] = []
    @State private var showingValidationAlert = false

    // Existing config ID for edits
    private var existingID: UUID?
    private var existingCreatedAt: Date?

    init(mode: AddEditMCPServerMode, onSave: @escaping (CustomMCPServerConfig) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel

        // Pre-populate if editing
        if case .edit(let config) = mode {
            _name = State(initialValue: config.name)
            _transportType = State(initialValue: config.type)
            _enabled = State(initialValue: config.enabled)
            existingID = config.id
            existingCreatedAt = config.createdAt

            switch config.transport {
            case .stdio(let stdioConfig):
                _command = State(initialValue: stdioConfig.command)
                _args = State(initialValue: stdioConfig.args.joined(separator: " "))
                _envVars = State(initialValue: formatKeyValue(stdioConfig.env))
                // Load OAuth config if present
                if let oauth = stdioConfig.oauth {
                    _oauthEnabled = State(initialValue: true)
                    _oauthAuthorizationEndpoint = State(initialValue: oauth.authorizationEndpoint.absoluteString)
                    _oauthTokenEndpoint = State(initialValue: oauth.tokenEndpoint.absoluteString)
                    _oauthClientId = State(initialValue: oauth.clientId)
                    _oauthScopes = State(initialValue: oauth.scopes.joined(separator: " "))
                    _oauthAccessTokenEnvVar = State(initialValue: oauth.accessTokenEnvVar ?? "OAUTH_ACCESS_TOKEN")
                }
            case .http(let httpConfig):
                _url = State(initialValue: httpConfig.url.absoluteString)
                _headers = State(initialValue: formatKeyValue(httpConfig.headers))
                // Load auto-discovery setting
                _oauthUseAutoDiscovery = State(initialValue: httpConfig.useAutoDiscovery)
                if httpConfig.useAutoDiscovery {
                    _oauthEnabled = State(initialValue: true)
                    _oauthClientId = State(initialValue: httpConfig.oauthClientId ?? "")
                }
                // Load manual OAuth config if present
                if let oauth = httpConfig.oauth {
                    _oauthEnabled = State(initialValue: true)
                    _oauthAuthorizationEndpoint = State(initialValue: oauth.authorizationEndpoint.absoluteString)
                    _oauthTokenEndpoint = State(initialValue: oauth.tokenEndpoint.absoluteString)
                    _oauthClientId = State(initialValue: oauth.clientId)
                    _oauthScopes = State(initialValue: oauth.scopes.joined(separator: " "))
                    _oauthAccessTokenEnvVar = State(initialValue: oauth.accessTokenEnvVar ?? "OAUTH_ACCESS_TOKEN")
                }
            }

            // Load secrets from Keychain
            if let secrets = try? ConnectorSecretsStorage.shared.loadSecrets(for: .custom(config.id)) {
                _secretEnvVars = State(initialValue: formatKeyValue(secrets.secretEnvVars))
                _secretHeaders = State(initialValue: formatKeyValue(secrets.secretHeaders))
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Basic Info
                    GroupBox("Basic Information") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Name")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("My MCP Server", text: $name)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Toggle("Enabled", isOn: $enabled)
                        }
                        .padding(.vertical, 8)
                    }

                    // Transport Type
                    GroupBox("Transport") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Type", selection: $transportType) {
                                Text("Local (Command)").tag(MCPTransportType.stdio)
                                Text("Remote (HTTP)").tag(MCPTransportType.http)
                            }
                            .pickerStyle(.segmented)

                            if transportType == .stdio {
                                stdioConfigView
                            } else {
                                httpConfigView
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // Secrets (API Keys)
                    GroupBox("Secrets (Stored in Keychain)") {
                        VStack(alignment: .leading, spacing: 12) {
                            if transportType == .stdio {
                                secretEnvVarsView
                            } else {
                                secretHeadersView
                            }

                            Text("Secrets are stored securely in macOS Keychain, not in the config file.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }

                    // OAuth Authentication
                    GroupBox("OAuth Authentication") {
                        VStack(alignment: .leading, spacing: 12) {
                            if transportType == .http {
                                // HTTP transport supports auto-discovery
                                httpOAuthConfigView
                            } else {
                                // STDIO transport uses manual OAuth config
                                OAuthConfigView(
                                    enabled: $oauthEnabled,
                                    authorizationEndpoint: $oauthAuthorizationEndpoint,
                                    tokenEndpoint: $oauthTokenEndpoint,
                                    clientId: $oauthClientId,
                                    scopes: $oauthScopes,
                                    accessTokenEnvVar: $oauthAccessTokenEnvVar
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button(mode.saveButtonTitle) {
                    save()
                }
                .keyboardShortcut(.return)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 720)
        .alert("Validation Error", isPresented: $showingValidationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrors.joined(separator: "\n"))
        }
    }

    // MARK: - STDIO Config View

    private var stdioConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Command field with detailed examples
            VStack(alignment: .leading, spacing: 4) {
                Text("Command")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("/usr/local/bin/npx", text: $command)
                    .textFieldStyle(.roundedBorder)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full path to the executable. Use `which <command>` to find the path:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Group {
                        Text("• /usr/local/bin/npx — for NPM packages (find with: which npx)")
                        Text("• /usr/local/bin/node — for Node.js scripts")
                        Text("• /usr/bin/python3 — for Python servers")
                        Text("• /path/to/executable — any MCP server binary")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
                }
            }

            // Arguments field with common patterns
            VStack(alignment: .leading, spacing: 4) {
                Text("Arguments")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("-y @modelcontextprotocol/server-filesystem /Users/me/docs", text: $args)
                    .textFieldStyle(.roundedBorder)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Arguments passed to the command. Common patterns:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Group {
                        Text("• npx: -y @org/package-name [args]")
                        Text("• node: /path/to/server.js --port 8080")
                        Text("• python: -m my_server --config /path/config.json")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
                }
            }

            // Environment variables
            VStack(alignment: .leading, spacing: 4) {
                Text("Environment Variables (non-secret)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $envVars)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                Text("KEY=value format, one per line. For API keys, use the Secrets section below.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Troubleshooting tips
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Viewing Logs", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.bold())
                    Text("Open Console.app and filter by \"com.extremis.app\" to see detailed MCP logs including connection status, requests/responses, and server stderr output.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - HTTP Config View

    private var httpConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Server URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://mcp.example.com", text: $url)
                    .textFieldStyle(.roundedBorder)
                Text("The HTTP/SSE endpoint URL for the MCP server")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Headers (non-secret)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $headers)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                Text("Header: value format, one per line. For auth tokens, use Secrets section.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - HTTP OAuth Config View

    private var httpOAuthConfigView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Requires OAuth Authentication", isOn: $oauthEnabled)

            if oauthEnabled {
                // Mode selector for HTTP OAuth
                VStack(alignment: .leading, spacing: 4) {
                    Text("OAuth Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Mode", selection: $oauthUseAutoDiscovery) {
                        Text("Auto-Discovery (MCP Servers)").tag(true)
                        Text("Manual Configuration").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.leading, 20)

                if oauthUseAutoDiscovery {
                    // Auto-discovery mode - only needs Client ID
                    VStack(alignment: .leading, spacing: 12) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("MCP Auto-Discovery", systemImage: "wand.and.stars")
                                    .font(.caption.bold())
                                    .foregroundColor(.blue)

                                Text("OAuth endpoints will be discovered automatically when connecting to the server. This works with MCP-compliant servers like Atlassian Rovo.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Client ID")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("your-client-id", text: $oauthClientId)
                                .textFieldStyle(.roundedBorder)
                            Text("OAuth application client ID (provided by the service)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 20)
                } else {
                    // Manual configuration mode
                    OAuthConfigView(
                        enabled: .constant(true),  // Already enabled, don't show toggle
                        authorizationEndpoint: $oauthAuthorizationEndpoint,
                        tokenEndpoint: $oauthTokenEndpoint,
                        clientId: $oauthClientId,
                        scopes: $oauthScopes,
                        accessTokenEnvVar: $oauthAccessTokenEnvVar
                    )
                }

                // OAuth info box
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("OAuth Flow", systemImage: "lock.shield")
                            .font(.caption.bold())
                        Text("After saving, click 'Connect' in the server list to complete the OAuth flow. A browser window will open for authorization.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    // MARK: - Secret Config Views

    private var secretEnvVarsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Secret Environment Variables (API Keys)")
                .font(.caption)
                .foregroundColor(.secondary)
            SecureTextEditor(text: $secretEnvVars)
                .frame(height: 60)
            Text("API_KEY=sk-xxx format, one per line. These are stored in Keychain.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var secretHeadersView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Secret Headers (Auth Tokens)")
                .font(.caption)
                .foregroundColor(.secondary)
            SecureTextEditor(text: $secretHeaders)
                .frame(height: 60)
            Text("Authorization: Bearer xxx format, one per line. Stored in Keychain.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        // Build config
        let config: CustomMCPServerConfig
        let serverID = existingID ?? UUID()

        if transportType == .stdio {
            let parsedEnv = parseKeyValue(envVars)

            // Build OAuth config if enabled
            var oauthConfig: OAuthConfig? = nil
            if oauthEnabled {
                guard let authEndpoint = URL(string: oauthAuthorizationEndpoint.trimmingCharacters(in: .whitespaces)),
                      let tokenEndpoint = URL(string: oauthTokenEndpoint.trimmingCharacters(in: .whitespaces)) else {
                    validationErrors = ["Invalid OAuth endpoint URLs"]
                    showingValidationAlert = true
                    return
                }
                let scopes = oauthScopes.split(separator: " ").map(String.init)
                oauthConfig = OAuthConfig(
                    authorizationEndpoint: authEndpoint,
                    tokenEndpoint: tokenEndpoint,
                    clientId: oauthClientId.trimmingCharacters(in: .whitespaces),
                    scopes: scopes,
                    accessTokenEnvVar: oauthAccessTokenEnvVar.trimmingCharacters(in: .whitespaces)
                )
            }

            let stdioConfig = StdioConfig(
                command: command.trimmingCharacters(in: .whitespaces),
                args: args.split(separator: " ").map(String.init),
                env: parsedEnv,
                oauth: oauthConfig
            )

            config = CustomMCPServerConfig(
                id: serverID,
                name: trimmedName,
                type: .stdio,
                enabled: enabled,
                transport: .stdio(stdioConfig),
                createdAt: existingCreatedAt ?? Date(),
                modifiedAt: Date()
            )
        } else {
            guard let parsedURL = URL(string: url.trimmingCharacters(in: .whitespaces)) else {
                validationErrors = ["Invalid URL format"]
                showingValidationAlert = true
                return
            }

            // Build OAuth config based on mode
            var oauthConfig: OAuthConfig? = nil
            var useAutoDiscovery = false
            var autoDiscoveryClientId: String? = nil

            if oauthEnabled {
                if oauthUseAutoDiscovery {
                    // Auto-discovery mode - only need client ID
                    useAutoDiscovery = true
                    autoDiscoveryClientId = oauthClientId.trimmingCharacters(in: .whitespaces)
                    if autoDiscoveryClientId?.isEmpty ?? true {
                        validationErrors = ["Client ID is required for OAuth auto-discovery"]
                        showingValidationAlert = true
                        return
                    }
                } else {
                    // Manual OAuth configuration
                    guard let authEndpoint = URL(string: oauthAuthorizationEndpoint.trimmingCharacters(in: .whitespaces)),
                          let tokenEndpoint = URL(string: oauthTokenEndpoint.trimmingCharacters(in: .whitespaces)) else {
                        validationErrors = ["Invalid OAuth endpoint URLs"]
                        showingValidationAlert = true
                        return
                    }
                    let scopes = oauthScopes.split(separator: " ").map(String.init)
                    oauthConfig = OAuthConfig(
                        authorizationEndpoint: authEndpoint,
                        tokenEndpoint: tokenEndpoint,
                        clientId: oauthClientId.trimmingCharacters(in: .whitespaces),
                        scopes: scopes,
                        accessTokenEnvVar: oauthAccessTokenEnvVar.trimmingCharacters(in: .whitespaces)
                    )
                }
            }

            let parsedHeaders = parseKeyValue(headers)
            let httpConfig = HTTPConfig(
                url: parsedURL,
                headers: parsedHeaders,
                oauth: oauthConfig,
                useAutoDiscovery: useAutoDiscovery,
                oauthClientId: autoDiscoveryClientId
            )

            config = CustomMCPServerConfig(
                id: serverID,
                name: trimmedName,
                type: .http,
                enabled: enabled,
                transport: .http(httpConfig),
                createdAt: existingCreatedAt ?? Date(),
                modifiedAt: Date()
            )
        }

        // Validate
        let errors = config.validate()
        if !errors.isEmpty {
            validationErrors = errors
            showingValidationAlert = true
            return
        }

        // Save secrets to Keychain
        let secrets = ConnectorSecrets(
            secretEnvVars: parseKeyValue(secretEnvVars),
            secretHeaders: parseKeyValue(secretHeaders),
            additionalSecrets: [:]
        )

        if !secrets.isEmpty {
            do {
                try ConnectorSecretsStorage.shared.saveSecrets(secrets, for: .custom(serverID))
            } catch {
                validationErrors = ["Failed to save secrets: \(error.localizedDescription)"]
                showingValidationAlert = true
                return
            }
        }

        onSave(config)
    }

    // MARK: - Helpers

    private func parseKeyValue(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Support both KEY=value and Key: value formats
            if let equalsIndex = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    result[key] = value
                }
            } else if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    result[key] = value
                }
            }
        }
        return result
    }

    private func formatKeyValue(_ dict: [String: String]) -> String {
        dict.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n")
    }
}

// MARK: - Secure Text Editor

/// A TextEditor that obscures its content like a SecureField
struct SecureTextEditor: View {
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isRevealed {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else {
                TextEditor(text: Binding(
                    get: { text.isEmpty ? "" : String(repeating: "•", count: min(text.count, 50)) },
                    set: { _ in }
                ))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .overlay(
                    // Invisible actual editor for input
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .opacity(0.01)
                )
            }

            Button(action: { isRevealed.toggle() }) {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(4)
        }
    }
}
