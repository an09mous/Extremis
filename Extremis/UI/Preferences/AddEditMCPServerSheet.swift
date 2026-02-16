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
            case .http(let httpConfig):
                _url = State(initialValue: httpConfig.url.absoluteString)
                _headers = State(initialValue: formatKeyValue(httpConfig.headers))
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
        .frame(width: 480, height: 620)
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
                        RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
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
                        RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                Text("Header: value format, one per line. For auth tokens, use Secrets section.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
            let stdioConfig = StdioConfig(
                command: command.trimmingCharacters(in: .whitespaces),
                args: args.split(separator: " ").map(String.init),
                env: parsedEnv
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

            let parsedHeaders = parseKeyValue(headers)
            let httpConfig = HTTPConfig(
                url: parsedURL,
                headers: parsedHeaders
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
                        RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
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
                    RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
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
