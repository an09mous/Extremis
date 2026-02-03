// MARK: - Connector Registry
// Singleton managing connector lifecycle and access

import Foundation

/// Central registry managing all connector instances
@MainActor
final class ConnectorRegistry: ObservableObject {

    // MARK: - Singleton

    static let shared = ConnectorRegistry()

    // MARK: - Published State

    /// All registered connectors (both custom and built-in)
    @Published private(set) var connectors: [String: any Connector] = [:]

    /// Current connection states by connector ID
    @Published private(set) var connectionStates: [String: ConnectorState] = [:]

    /// All available tools from all connected connectors
    @Published private(set) var availableTools: [ConnectorTool] = []

    // MARK: - Dependencies

    private let configStorage: ConnectorConfigStorage
    private let secretsStorage: ConnectorSecretsStorage

    // MARK: - Retry State

    private var retryAttempts: [String: Int] = [:]
    private var retryTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Initialization

    init(
        configStorage: ConnectorConfigStorage = .shared,
        secretsStorage: ConnectorSecretsStorage = .shared
    ) {
        self.configStorage = configStorage
        self.secretsStorage = secretsStorage
    }

    // MARK: - Registration

    /// Register a connector
    func register(_ connector: any Connector) {
        connectors[connector.id] = connector
        connectionStates[connector.id] = connector.state

        // Observe state changes
        observeStateChanges(for: connector)
    }

    /// Unregister a connector
    func unregister(connectorID: String) async {
        // Cancel any pending retry
        retryTasks[connectorID]?.cancel()
        retryTasks.removeValue(forKey: connectorID)
        retryAttempts.removeValue(forKey: connectorID)

        // Disconnect if connected
        if let connector = connectors[connectorID] {
            await connector.disconnect()
        }

        connectors.removeValue(forKey: connectorID)
        connectionStates.removeValue(forKey: connectorID)
        refreshAvailableTools()
    }

    // MARK: - Connection Management

    /// Connect to a specific connector
    func connect(connectorID: String) async throws {
        guard let connector = connectors[connectorID] else {
            throw ConnectorError.notConnected
        }

        retryAttempts[connectorID] = 0

        // Set connecting state immediately to clear any stale error state
        connectionStates[connectorID] = .connecting

        do {
            try await connector.connect()
            connectionStates[connectorID] = .connected
            refreshAvailableTools()
            print("[ConnectorRegistry] Connected to \(connector.name)")
        } catch {
            connectionStates[connectorID] = .error(error.localizedDescription)
            throw error
        }
    }

    /// Disconnect from a specific connector
    func disconnect(connectorID: String) async {
        // Cancel any pending retry
        retryTasks[connectorID]?.cancel()
        retryTasks.removeValue(forKey: connectorID)

        guard let connector = connectors[connectorID] else { return }

        // Set disconnected state BEFORE calling disconnect to prevent
        // transient error states from cancelled pending requests
        connectionStates[connectorID] = .disconnected

        await connector.disconnect()
        refreshAvailableTools()
        print("[ConnectorRegistry] Disconnected from \(connector.name)")
    }

    /// Connect to all enabled connectors
    func connectAllEnabled() async {
        // Register built-in connectors first
        registerBuiltInConnectors()

        // Load configs and create connectors
        await loadCustomServers()

        // Connect to all enabled connectors sequentially on MainActor
        // (This is safe since we're already on MainActor)
        for (id, connector) in connectors where connector.isEnabled {
            do {
                try await connect(connectorID: id)
            } catch {
                print("[ConnectorRegistry] Failed to connect \(connector.name): \(error.localizedDescription)")
                // Start retry logic
                scheduleRetry(for: id)
            }
        }
    }

    /// Disconnect all connectors
    func disconnectAll() async {
        // Cancel all retries
        for (_, task) in retryTasks {
            task.cancel()
        }
        retryTasks.removeAll()
        retryAttempts.removeAll()

        // Disconnect all sequentially on MainActor
        // (This is safe since we're already on MainActor)
        for id in connectors.keys {
            await disconnect(connectorID: id)
        }
    }

    // MARK: - Built-In Connectors

    /// Register built-in connectors (Shell, etc.)
    private func registerBuiltInConnectors() {
        // Register ShellConnector if not already registered
        if connectors["shell"] == nil {
            let shellConnector = ShellConnector()
            register(shellConnector)
            print("[ConnectorRegistry] Registered built-in ShellConnector")
        }
    }

    // MARK: - Custom Server Management

    /// Load custom servers from config storage
    func loadCustomServers() async {
        do {
            let servers = try configStorage.allCustomServers()

            for server in servers {
                // Skip if already registered
                if connectors[server.id.uuidString] != nil {
                    continue
                }

                let connector = CustomMCPConnector(config: server, secretsStorage: secretsStorage)
                register(connector)
            }
        } catch {
            print("[ConnectorRegistry] Failed to load custom servers: \(error.localizedDescription)")
        }
    }

    /// Add a new custom server and optionally connect
    func addCustomServer(_ config: CustomMCPServerConfig, autoConnect: Bool = true) async {
        let connector = CustomMCPConnector(config: config, secretsStorage: secretsStorage)
        register(connector)

        if autoConnect && config.enabled {
            do {
                try await connect(connectorID: config.id.uuidString)
            } catch {
                print("[ConnectorRegistry] Auto-connect failed for \(config.name): \(error.localizedDescription)")
            }
        }
    }

    /// Update a custom server configuration
    func updateCustomServer(_ config: CustomMCPServerConfig) async {
        guard let connector = connectors[config.id.uuidString] as? CustomMCPConnector else {
            return
        }

        // If connector is being disabled, cancel any pending retries
        if !config.enabled {
            retryTasks[config.id.uuidString]?.cancel()
            retryTasks.removeValue(forKey: config.id.uuidString)
            retryAttempts.removeValue(forKey: config.id.uuidString)
        }

        await connector.updateConfig(config)
        connectionStates[config.id.uuidString] = connector.state
        refreshAvailableTools()
    }

    /// Remove a custom server
    func removeCustomServer(id: UUID) async {
        await unregister(connectorID: id.uuidString)
    }

    // MARK: - Tool Access

    /// Get a connector by ID
    func connector(id: String) -> (any Connector)? {
        connectors[id]
    }

    /// Get connector for a specific tool
    func connector(forTool toolName: String) -> (any Connector)? {
        for connector in connectors.values {
            if connector.tools.contains(where: { $0.name == toolName || $0.originalName == toolName }) {
                return connector
            }
        }
        return nil
    }

    /// Execute a tool call
    func executeTool(_ call: ToolCall) async throws -> ToolResult {
        guard let connector = connectors[call.connectorID] else {
            throw ConnectorError.notConnected
        }

        return try await connector.executeTool(call)
    }

    // MARK: - Private Methods

    /// Refresh the aggregated list of available tools
    private func refreshAvailableTools() {
        var tools: [ConnectorTool] = []

        for connector in connectors.values {
            if connector.state.isConnected {
                tools.append(contentsOf: connector.tools)
            }
        }

        availableTools = tools
    }

    /// Schedule a retry for failed connection
    private func scheduleRetry(for connectorID: String) {
        guard let connector = connectors[connectorID] else { return }

        // Don't retry if connector is disabled
        guard connector.isEnabled else {
            print("[ConnectorRegistry] Skipping retry for \(connector.name): connector is disabled")
            retryAttempts.removeValue(forKey: connectorID)
            retryTasks.removeValue(forKey: connectorID)
            return
        }

        let attempts = (retryAttempts[connectorID] ?? 0) + 1
        retryAttempts[connectorID] = attempts

        // Capture name for use in Task
        let connectorName = connector.name

        guard attempts <= ConnectorConstants.maxReconnectAttempts else {
            print("[ConnectorRegistry] Max retry attempts reached for \(connectorName)")
            return
        }

        // Exponential backoff: 1s, 2s, 4s
        let delay = ConnectorConstants.reconnectBaseDelay * pow(2.0, Double(attempts - 1))

        retryTasks[connectorID] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            // Re-check if connector is still enabled after the delay
            guard let currentConnector = self.connectors[connectorID],
                  currentConnector.isEnabled else {
                print("[ConnectorRegistry] Retry cancelled for \(connectorName): connector disabled")
                return
            }

            do {
                try await self.connect(connectorID: connectorID)
                print("[ConnectorRegistry] Retry successful for \(connectorName)")
            } catch {
                print("[ConnectorRegistry] Retry \(attempts) failed for \(connectorName): \(error.localizedDescription)")
                self.scheduleRetry(for: connectorID)
            }
        }
    }

    /// Observe state changes for a connector
    private func observeStateChanges(for connector: any Connector) {
        // For CustomMCPConnector, we need to observe Published state
        if let customConnector = connector as? CustomMCPConnector {
            // We'll use the connector's published state directly
            // Update when accessed via state property
            Task {
                for await newState in customConnector.$state.values {
                    await MainActor.run {
                        let currentState = self.connectionStates[connector.id]

                        // Don't overwrite .disconnected with .error from cancelled requests
                        // This happens when disconnect() cancels pending operations
                        if case .disconnected = currentState,
                           case .error = newState {
                            return
                        }

                        self.connectionStates[connector.id] = newState
                        self.refreshAvailableTools()
                    }
                }
            }
        }

        // For ShellConnector, observe Published state
        if let shellConnector = connector as? ShellConnector {
            Task {
                for await newState in shellConnector.$state.values {
                    await MainActor.run {
                        let currentState = self.connectionStates[connector.id]

                        // Don't overwrite .disconnected with .error from cancelled requests
                        if case .disconnected = currentState,
                           case .error = newState {
                            return
                        }

                        self.connectionStates[connector.id] = newState
                        self.refreshAvailableTools()
                    }
                }
            }
        }
    }
}

// MARK: - Convenience Extensions

extension ConnectorRegistry {
    /// Check if any connectors are connected
    var hasConnectedConnectors: Bool {
        connectors.values.contains { $0.state.isConnected }
    }

    /// Get all connected connectors
    var connectedConnectors: [any Connector] {
        connectors.values.filter { $0.state.isConnected }
    }

    /// Get all custom MCP connectors
    var customConnectors: [CustomMCPConnector] {
        connectors.values.compactMap { $0 as? CustomMCPConnector }
    }

    /// Check if a specific tool is available
    func hasTool(named name: String) -> Bool {
        availableTools.contains { $0.name == name || $0.originalName == name }
    }

    /// Get tool definitions for LLM
    var toolDefinitions: [ConnectorTool] {
        availableTools
    }
}
