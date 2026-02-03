// MARK: - Connectors Tab
// MCP server and connector configuration

import SwiftUI
import Combine

struct ConnectorsTab: View {
    @StateObject private var viewModel = ConnectorsTabViewModel()
    @State private var showingAddSheet = false
    @State private var editingServer: CustomMCPServerConfig?
    @State private var showingDeleteConfirmation = false
    @State private var serverToDelete: CustomMCPServerConfig?
    @State private var showingSudoModeConfirmation = false
    @State private var showingGitHubAuth = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Custom MCP Servers Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Custom MCP Servers")
                                .font(.headline)

                            Spacer()

                            Button(action: { showingAddSheet = true }) {
                                Image(systemName: "plus")
                            }
                            .help("Add Custom MCP Server")
                        }

                        if viewModel.customServers.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(viewModel.customServers) { server in
                                CustomServerRow(
                                    server: server,
                                    connectionState: viewModel.connectionState(for: server),
                                    tools: viewModel.tools(for: server),
                                    onToggleEnabled: { viewModel.toggleEnabled(server) },
                                    onEdit: { editingServer = server },
                                    onDelete: {
                                        serverToDelete = server
                                        showingDeleteConfirmation = true
                                    },
                                    onConnect: { viewModel.connect(server) },
                                    onDisconnect: { viewModel.disconnect(server) }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    // Built-in Connectors Section
                    Divider()
                        .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Built-in Connectors")
                            .font(.headline)

                        // Shell Connector
                        BuiltInConnectorRow(
                            name: "System Commands",
                            description: "Execute macOS shell commands with user approval",
                            icon: "terminal",
                            isEnabled: viewModel.isShellConnectorEnabled,
                            connectionState: viewModel.shellConnectionState,
                            tools: viewModel.shellTools,
                            onToggleEnabled: { viewModel.toggleShellConnector() },
                            onConnect: { viewModel.connectShellConnector() },
                            onDisconnect: { viewModel.disconnectShellConnector() }
                        )

                        // GitHub Connector
                        BuiltInConnectorRow(
                            name: "GitHub",
                            description: "Access repositories, issues, and pull requests via Copilot MCP",
                            icon: "link",
                            isEnabled: viewModel.isGitHubConnectorEnabled,
                            connectionState: viewModel.githubConnectionState,
                            tools: viewModel.githubTools,
                            onToggleEnabled: { viewModel.toggleGitHubConnector() },
                            onConnect: { viewModel.connectGitHubConnector() },
                            onDisconnect: { viewModel.disconnectGitHubConnector() },
                            onConfigure: { showingGitHubAuth = true }
                        )
                    }
                    .padding(.vertical, 8)

                    // Security Settings Section
                    Divider()
                        .padding(.vertical, 8)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Security Settings")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle("", isOn: Binding(
                                    get: { viewModel.isSudoModeEnabled },
                                    set: { newValue in
                                        if newValue {
                                            showingSudoModeConfirmation = true
                                        } else {
                                            viewModel.disableSudoMode()
                                        }
                                    }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()

                                Image(systemName: "exclamationmark.shield.fill")
                                    .foregroundColor(viewModel.isSudoModeEnabled ? .red : .secondary)

                                Text("Sudo Mode")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                if viewModel.isSudoModeEnabled {
                                    Text("ACTIVE")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red)
                                        .cornerRadius(4)
                                }

                                Spacer()
                            }

                            Text("When enabled, ALL tool calls execute immediately without approval.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if viewModel.isSudoModeEnabled {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("Security bypassed. Tools run without review.")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.isSudoModeEnabled ? Color.red.opacity(0.08) : Color.primary.opacity(0.03))
                        )
                    }
                    .padding(.vertical, 8)
                }
            }

            // Status Message
            if let message = viewModel.statusMessage {
                HStack {
                    Image(systemName: viewModel.isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundColor(viewModel.isError ? .orange : .green)
                    Text(message)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            viewModel.loadServers()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEditMCPServerSheet(
                mode: .add,
                onSave: { config in
                    viewModel.addServer(config)
                    showingAddSheet = false
                },
                onCancel: { showingAddSheet = false }
            )
        }
        .sheet(item: $editingServer) { server in
            AddEditMCPServerSheet(
                mode: .edit(server),
                onSave: { config in
                    viewModel.updateServer(config)
                    editingServer = nil
                },
                onCancel: { editingServer = nil }
            )
        }
        .confirmationDialog(
            "Delete Server",
            isPresented: $showingDeleteConfirmation,
            presenting: serverToDelete
        ) { server in
            Button("Delete", role: .destructive) {
                viewModel.deleteServer(server)
                serverToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                serverToDelete = nil
            }
        } message: { server in
            Text("Are you sure you want to delete '\(server.name)'? This action cannot be undone.")
        }
        .confirmationDialog(
            "Enable Sudo Mode?",
            isPresented: $showingSudoModeConfirmation
        ) {
            Button("Enable Sudo Mode", role: .destructive) {
                viewModel.enableSudoMode()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All tools will execute without approval. This bypasses security checks.")
        }
        .sheet(isPresented: $showingGitHubAuth) {
            GitHubAuthSheet(
                existingToken: viewModel.existingGitHubToken,
                onSave: { token in
                    viewModel.saveGitHubToken(token)
                    showingGitHubAuth = false
                },
                onCancel: { showingGitHubAuth = false }
            )
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No Custom MCP Servers")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Add a custom MCP server to extend Extremis with additional tools and capabilities.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Add Server") {
                showingAddSheet = true
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Built-in Connector Row

struct BuiltInConnectorRow: View {
    let name: String
    let description: String
    let icon: String
    let isEnabled: Bool
    let connectionState: ConnectorState
    let tools: [ConnectorTool]
    let onToggleEnabled: () -> Void
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    var onConfigure: (() -> Void)? = nil

    @State private var showingTools = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { _ in onToggleEnabled() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                Image(systemName: icon)
                    .foregroundColor(.secondary)

                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                // Connection status indicator
                connectionStatusView

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    if let onConfigure = onConfigure {
                        Button(action: onConfigure) {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.borderless)
                        .help("Configure")
                    }

                    if isEnabled {
                        if connectionState.isConnected {
                            Button("Disconnect") {
                                onDisconnect()
                            }
                            .font(.caption)
                        } else if case .connecting = connectionState {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Button("Connect") {
                                onConnect()
                            }
                            .font(.caption)
                        }
                    }
                }
            }

            // Description
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            // Tools count
            if connectionState.isConnected && !tools.isEmpty {
                Button(action: { showingTools.toggle() }) {
                    Label("\(tools.count) tool\(tools.count == 1 ? "" : "s") available", systemImage: showingTools ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Collapsible tools list
            if showingTools && connectionState.isConnected && !tools.isEmpty {
                toolsListView
            }

            // Error message if any
            if case .error(let message) = connectionState {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .foregroundColor(.red)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            if !isEnabled {
                Text("Disabled")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text(connectionState.displayText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusColor: Color {
        if !isEnabled {
            return .gray
        }
        switch connectionState {
        case .disconnected:
            return .gray
        case .connecting:
            return .yellow
        case .connected:
            return .green
        case .error:
            return .red
        }
    }

    @ViewBuilder
    private var toolsListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tools, id: \.id) { tool in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wrench")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.originalName)
                            .font(.caption)
                            .fontWeight(.medium)

                        if let description = tool.description {
                            Text(description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(.leading, 24)
        .padding(.vertical, 4)
    }
}

// MARK: - Custom Server Row

struct CustomServerRow: View {
    let server: CustomMCPServerConfig
    let connectionState: ConnectorState
    let tools: [ConnectorTool]
    let onToggleEnabled: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    @State private var showingTools = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Toggle("", isOn: Binding(
                    get: { server.enabled },
                    set: { _ in onToggleEnabled() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                Text(server.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                // Connection status indicator
                connectionStatusView

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    if server.enabled {
                        if connectionState.isConnected {
                            Button("Disconnect") {
                                onDisconnect()
                            }
                            .font(.caption)
                        } else if case .connecting = connectionState {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Button("Connect") {
                                onConnect()
                            }
                            .font(.caption)
                        }
                    }

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit Server")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete Server")
                }
            }

            // Server info
            HStack(spacing: 16) {
                Label(server.type.displayName, systemImage: server.type == .stdio ? "terminal" : "network")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if connectionState.isConnected && !tools.isEmpty {
                    Button(action: { showingTools.toggle() }) {
                        Label("\(tools.count) tools", systemImage: showingTools ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Transport details
            transportDetailsView
                .font(.caption2)
                .foregroundColor(.secondary)

            // Collapsible tools list
            if showingTools && connectionState.isConnected && !tools.isEmpty {
                toolsListView
            }

            // Error message if any
            if case .error(let message) = connectionState {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .foregroundColor(.red)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
    }

    @ViewBuilder
    private var toolsListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tools, id: \.id) { tool in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wrench")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.originalName)
                            .font(.caption)
                            .fontWeight(.medium)

                        if let description = tool.description {
                            Text(description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(.leading, 24)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            if !server.enabled {
                Text("Disabled")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text(connectionState.displayText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusColor: Color {
        if !server.enabled {
            return .gray
        }
        switch connectionState {
        case .disconnected:
            return .gray
        case .connecting:
            return .yellow
        case .connected:
            return .green
        case .error:
            return .red
        }
    }

    @ViewBuilder
    private var transportDetailsView: some View {
        switch server.transport {
        case .stdio(let config):
            Text("Command: \(config.command) \(config.args.joined(separator: " "))")
                .lineLimit(1)
                .truncationMode(.middle)
        case .http(let config):
            Text("URL: \(config.url.absoluteString)")
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - View Model

@MainActor
final class ConnectorsTabViewModel: ObservableObject {
    @Published private(set) var customServers: [CustomMCPServerConfig] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var isError = false

    private let configStorage = ConnectorConfigStorage.shared
    private let registry = ConnectorRegistry.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to registry changes to update UI when connection states change
        registry.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Shell Connector Properties

    var isShellConnectorEnabled: Bool {
        UserDefaults.standard.shellConnectorEnabled
    }

    var shellConnectionState: ConnectorState {
        registry.connectionStates["shell"] ?? .disconnected
    }

    var shellTools: [ConnectorTool] {
        registry.connector(id: "shell")?.tools ?? []
    }

    // MARK: - Sudo Mode

    var isSudoModeEnabled: Bool {
        UserDefaults.standard.sudoModeEnabled
    }

    func enableSudoMode() {
        UserDefaults.standard.sudoModeEnabled = true
        statusMessage = "Sudo Mode enabled"
        isError = false
        objectWillChange.send()
    }

    func disableSudoMode() {
        UserDefaults.standard.sudoModeEnabled = false
        statusMessage = "Sudo Mode disabled"
        isError = false
        objectWillChange.send()
    }

    // MARK: - Shell Connector Actions

    func toggleShellConnector() {
        let newValue = !isShellConnectorEnabled
        UserDefaults.standard.shellConnectorEnabled = newValue

        Task {
            if newValue {
                // Enable and connect
                try? await registry.connect(connectorID: "shell")
            } else {
                // Disable and disconnect
                await registry.disconnect(connectorID: "shell")
            }
            objectWillChange.send()
        }

        statusMessage = "System Commands \(newValue ? "enabled" : "disabled")"
        isError = false
    }

    func connectShellConnector() {
        Task {
            do {
                try await registry.connect(connectorID: "shell")
                objectWillChange.send()
            } catch {
                statusMessage = "Connection failed: \(error.localizedDescription)"
                isError = true
            }
        }
    }

    func disconnectShellConnector() {
        Task {
            await registry.disconnect(connectorID: "shell")
            objectWillChange.send()
        }
    }

    // MARK: - GitHub Connector Properties

    var isGitHubConnectorEnabled: Bool {
        UserDefaults.standard.githubConnectorEnabled
    }

    var githubConnectionState: ConnectorState {
        registry.connectionStates["github"] ?? .disconnected
    }

    var githubTools: [ConnectorTool] {
        registry.connector(id: "github")?.tools ?? []
    }

    var hasGitHubToken: Bool {
        ConnectorSecretsStorage.shared.hasSecrets(forBuiltIn: .github)
    }

    var existingGitHubToken: String? {
        guard let secrets = try? ConnectorSecretsStorage.shared.loadSecrets(forBuiltIn: .github) else {
            return nil
        }
        return secrets.additionalSecrets["GITHUB_PERSONAL_ACCESS_TOKEN"]
    }

    // MARK: - GitHub Connector Actions

    func toggleGitHubConnector() {
        let newValue = !isGitHubConnectorEnabled
        UserDefaults.standard.githubConnectorEnabled = newValue

        Task {
            if newValue {
                do {
                    try await registry.connect(connectorID: "github")
                } catch ConnectorError.authenticationRequired {
                    statusMessage = "GitHub token required - click Configure"
                    isError = true
                } catch {
                    // Connection failed, but toggle state is saved
                }
            } else {
                await registry.disconnect(connectorID: "github")
            }
            objectWillChange.send()
        }

        if !newValue {
            statusMessage = "GitHub disabled"
            isError = false
        }
    }

    func connectGitHubConnector() {
        Task {
            do {
                try await registry.connect(connectorID: "github")
                objectWillChange.send()
            } catch ConnectorError.authenticationRequired {
                statusMessage = "GitHub token required - click Configure"
                isError = true
            } catch {
                statusMessage = "Connection failed: \(error.localizedDescription)"
                isError = true
            }
        }
    }

    func disconnectGitHubConnector() {
        Task {
            await registry.disconnect(connectorID: "github")
            objectWillChange.send()
        }
    }

    func saveGitHubToken(_ token: String) {
        let secrets = ConnectorSecrets(
            secretEnvVars: [:],
            secretHeaders: [:],
            additionalSecrets: ["GITHUB_PERSONAL_ACCESS_TOKEN": token]
        )
        do {
            try ConnectorSecretsStorage.shared.saveSecrets(secrets, forBuiltIn: .github)
            statusMessage = "GitHub token saved"
            isError = false

            // If connector is enabled, try to connect with new token
            if isGitHubConnectorEnabled {
                connectGitHubConnector()
            }
        } catch {
            statusMessage = "Failed to save token: \(error.localizedDescription)"
            isError = true
        }
    }

    // MARK: - Custom Server Methods

    func loadServers() {
        do {
            customServers = try configStorage.allCustomServers()

            // Ensure registry has connectors for all servers
            Task {
                await registry.loadCustomServers()
                objectWillChange.send()
            }
        } catch {
            statusMessage = "Failed to load servers: \(error.localizedDescription)"
            isError = true
        }
    }

    func addServer(_ config: CustomMCPServerConfig) {
        do {
            try configStorage.addCustomServer(config)
            customServers.append(config)

            // Add to registry and optionally auto-connect
            Task {
                await registry.addCustomServer(config, autoConnect: config.enabled)
                objectWillChange.send()
            }

            statusMessage = "Server '\(config.name)' added"
            isError = false
        } catch {
            statusMessage = "Failed to add server: \(error.localizedDescription)"
            isError = true
        }
    }

    func updateServer(_ config: CustomMCPServerConfig) {
        do {
            try configStorage.updateCustomServer(config)

            if let index = customServers.firstIndex(where: { $0.id == config.id }) {
                customServers[index] = config
            }

            // Update in registry
            Task {
                await registry.updateCustomServer(config)
                objectWillChange.send()
            }

            statusMessage = "Server '\(config.name)' updated"
            isError = false
        } catch {
            statusMessage = "Failed to update server: \(error.localizedDescription)"
            isError = true
        }
    }

    func deleteServer(_ server: CustomMCPServerConfig) {
        do {
            // Remove from registry
            Task {
                await registry.removeCustomServer(id: server.id)
            }

            // Delete secrets
            try? ConnectorSecretsStorage.shared.deleteSecrets(for: .custom(server.id))

            // Remove from storage
            try configStorage.removeCustomServer(id: server.id)
            customServers.removeAll { $0.id == server.id }

            statusMessage = "Server '\(server.name)' deleted"
            isError = false
        } catch {
            statusMessage = "Failed to delete server: \(error.localizedDescription)"
            isError = true
        }
    }

    func toggleEnabled(_ server: CustomMCPServerConfig) {
        var updated = server
        updated.enabled = !server.enabled

        do {
            try configStorage.setEnabled(updated.enabled, forCustomServer: server.id)

            if let index = customServers.firstIndex(where: { $0.id == server.id }) {
                customServers[index].enabled = updated.enabled
            }

            // Update in registry and connect/disconnect
            Task {
                await registry.updateCustomServer(updated)
                if updated.enabled {
                    try? await registry.connect(connectorID: server.id.uuidString)
                } else {
                    await registry.disconnect(connectorID: server.id.uuidString)
                }
                objectWillChange.send()
            }

            statusMessage = "\(server.name) \(updated.enabled ? "enabled" : "disabled")"
            isError = false
        } catch {
            statusMessage = "Failed to update server: \(error.localizedDescription)"
            isError = true
        }
    }

    func connect(_ server: CustomMCPServerConfig) {
        Task {
            do {
                try await registry.connect(connectorID: server.id.uuidString)
                objectWillChange.send()
            } catch {
                statusMessage = "Connection failed: \(error.localizedDescription)"
                isError = true
            }
        }
    }

    func disconnect(_ server: CustomMCPServerConfig) {
        Task {
            await registry.disconnect(connectorID: server.id.uuidString)
            objectWillChange.send()
        }
    }

    func connectionState(for server: CustomMCPServerConfig) -> ConnectorState {
        registry.connectionStates[server.id.uuidString] ?? .disconnected
    }

    func toolCount(for server: CustomMCPServerConfig) -> Int {
        if let connector = registry.connector(id: server.id.uuidString) {
            return connector.tools.count
        }
        return 0
    }

    func tools(for server: CustomMCPServerConfig) -> [ConnectorTool] {
        if let connector = registry.connector(id: server.id.uuidString) {
            return connector.tools
        }
        return []
    }
}

// Note: MCPTransportType.displayName is defined in MCPTransportConfig.swift
