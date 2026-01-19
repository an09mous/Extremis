// MARK: - Connector Config Storage Unit Tests
// Tests for ConnectorConfigStorage CRUD operations

import Foundation

// MARK: - Test Framework

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []
    static var currentSuite = ""

    static func suite(_ name: String) {
        currentSuite = name
        print("\n📦 \(name)")
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
            let message = "Expected nil but got '\(value!)'"
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
        if !condition {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected false but got true"))
            print("  ✗ \(testName): Expected false but got true")
        }
    }

    static func printSummary() {
        print("\n==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("\nFailed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("==================================================")
    }
}

// MARK: - Inline Model Definitions (for standalone test)

/// Transport type enumeration
enum MCPTransportType: String, Codable, CaseIterable {
    case stdio
    case http
}

/// STDIO configuration
struct StdioConfig: Codable, Equatable {
    var command: String
    var args: [String]
    var env: [String: String]

    init(command: String, args: [String] = [], env: [String: String] = [:]) {
        self.command = command
        self.args = args
        self.env = env
    }

    func validate() -> [String] {
        var errors: [String] = []
        if command.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append("Command cannot be empty")
        }
        return errors
    }
}

/// HTTP configuration
struct HTTPConfig: Codable, Equatable {
    var url: URL
    var headers: [String: String]

    init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers
    }

    func validate() -> [String] {
        var errors: [String] = []
        if url.scheme?.lowercased() != "https" {
            errors.append("URL must use HTTPS for security")
        }
        if url.host?.isEmpty ?? true {
            errors.append("URL must have a valid host")
        }
        return errors
    }
}

/// Transport configuration
enum MCPTransportConfig: Codable, Equatable {
    case stdio(StdioConfig)
    case http(HTTPConfig)

    private enum CodingKeys: String, CodingKey {
        case stdio
        case http
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stdioConfig = try container.decodeIfPresent(StdioConfig.self, forKey: .stdio) {
            self = .stdio(stdioConfig)
        } else if let httpConfig = try container.decodeIfPresent(HTTPConfig.self, forKey: .http) {
            self = .http(httpConfig)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "No valid transport configuration found"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stdio(let config):
            try container.encode(config, forKey: .stdio)
        case .http(let config):
            try container.encode(config, forKey: .http)
        }
    }
}

/// Custom MCP server configuration
struct CustomMCPServerConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var type: MCPTransportType
    var enabled: Bool
    var transport: MCPTransportConfig
    let createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: MCPTransportType,
        enabled: Bool = true,
        transport: MCPTransportConfig,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.transport = transport
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    static func stdio(
        name: String,
        command: String,
        args: [String] = [],
        env: [String: String] = [:],
        enabled: Bool = true
    ) -> CustomMCPServerConfig {
        CustomMCPServerConfig(
            name: name,
            type: .stdio,
            enabled: enabled,
            transport: .stdio(StdioConfig(command: command, args: args, env: env))
        )
    }

    func withUpdatedTimestamp() -> CustomMCPServerConfig {
        var copy = self
        copy.modifiedAt = Date()
        return copy
    }
}

/// Built-in connector config placeholder
struct BuiltInConnectorConfig: Codable, Equatable {
    var enabled: Bool
    var settings: [String: String]?

    static let disabled = BuiltInConnectorConfig(enabled: false, settings: nil)

    init(enabled: Bool, settings: [String: String]? = nil) {
        self.enabled = enabled
        self.settings = settings
    }
}

/// Root configuration file structure
struct ConnectorConfigFile: Codable, Equatable {
    var version: Int
    var builtIn: [String: BuiltInConnectorConfig]
    var custom: [CustomMCPServerConfig]

    static let currentVersion = 1

    static let empty = ConnectorConfigFile(
        version: currentVersion,
        builtIn: [:],
        custom: []
    )

    init(version: Int = currentVersion, builtIn: [String: BuiltInConnectorConfig] = [:], custom: [CustomMCPServerConfig] = []) {
        self.version = version
        self.builtIn = builtIn
        self.custom = custom
    }

    mutating func addCustomServer(_ config: CustomMCPServerConfig) {
        custom.removeAll { $0.id == config.id }
        custom.append(config)
    }

    mutating func updateCustomServer(_ config: CustomMCPServerConfig) {
        if let index = custom.firstIndex(where: { $0.id == config.id }) {
            custom[index] = config.withUpdatedTimestamp()
        }
    }

    mutating func removeCustomServer(id: UUID) {
        custom.removeAll { $0.id == id }
    }

    func customServer(id: UUID) -> CustomMCPServerConfig? {
        custom.first { $0.id == id }
    }

    var enabledCustomServers: [CustomMCPServerConfig] {
        custom.filter { $0.enabled }
    }
}

// MARK: - Test Storage Class (simplified for standalone testing)

/// Test version of ConnectorConfigStorage for standalone testing
final class TestConnectorConfigStorage {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let testDir: URL

    var configFileURL: URL {
        testDir.appendingPathComponent("connectors.json")
    }

    init() {
        self.fileManager = .default
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Use a unique temp directory for each test run
        let tempDir = fileManager.temporaryDirectory
        self.testDir = tempDir.appendingPathComponent("ExtremisTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    deinit {
        cleanup()
    }

    func cleanup() {
        try? fileManager.removeItem(at: testDir)
    }

    func load() throws -> ConnectorConfigFile {
        let url = configFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            return .empty
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(ConnectorConfigFile.self, from: data)
    }

    func save(_ config: ConnectorConfigFile) throws {
        let url = configFileURL
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(config)
        try data.write(to: url, options: [.atomic])
    }

    func addCustomServer(_ config: CustomMCPServerConfig) throws {
        var connectorConfig = try load()
        connectorConfig.addCustomServer(config)
        try save(connectorConfig)
    }

    func updateCustomServer(_ config: CustomMCPServerConfig) throws {
        var connectorConfig = try load()
        connectorConfig.updateCustomServer(config)
        try save(connectorConfig)
    }

    func removeCustomServer(id: UUID) throws {
        var connectorConfig = try load()
        connectorConfig.removeCustomServer(id: id)
        try save(connectorConfig)
    }

    func customServer(id: UUID) throws -> CustomMCPServerConfig? {
        let config = try load()
        return config.customServer(id: id)
    }

    func allCustomServers() throws -> [CustomMCPServerConfig] {
        let config = try load()
        return config.custom
    }

    func enabledCustomServers() throws -> [CustomMCPServerConfig] {
        let config = try load()
        return config.enabledCustomServers
    }

    func setEnabled(_ enabled: Bool, forCustomServer id: UUID) throws {
        var config = try load()
        if var serverConfig = config.customServer(id: id) {
            serverConfig.enabled = enabled
            config.updateCustomServer(serverConfig)
            try save(config)
        }
    }

    var configFileExists: Bool {
        fileManager.fileExists(atPath: configFileURL.path)
    }

    func deleteConfigFile() throws {
        if configFileExists {
            try fileManager.removeItem(at: configFileURL)
        }
    }
}

// MARK: - Tests

func testEmptyConfigOnNoFile() {
    TestRunner.suite("Empty Config When No File Exists")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    do {
        let config = try storage.load()
        TestRunner.assertEqual(config.version, ConnectorConfigFile.currentVersion, "Version is current")
        TestRunner.assertTrue(config.custom.isEmpty, "Custom servers array is empty")
        TestRunner.assertTrue(config.builtIn.isEmpty, "Built-in config is empty")
        TestRunner.assertFalse(storage.configFileExists, "Config file does not exist")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testSaveAndLoad() {
    TestRunner.suite("Save and Load Configuration")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    let server1 = CustomMCPServerConfig.stdio(
        name: "Test Server",
        command: "/usr/bin/node",
        args: ["server.js"],
        env: ["DEBUG": "true"]
    )

    do {
        // Save a config with one server
        var config = ConnectorConfigFile.empty
        config.addCustomServer(server1)
        try storage.save(config)

        TestRunner.assertTrue(storage.configFileExists, "Config file exists after save")

        // Load and verify
        let loaded = try storage.load()
        TestRunner.assertEqual(loaded.custom.count, 1, "One custom server loaded")
        TestRunner.assertEqual(loaded.custom[0].name, "Test Server", "Server name matches")
        TestRunner.assertEqual(loaded.custom[0].id, server1.id, "Server ID matches")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testAddCustomServer() {
    TestRunner.suite("Add Custom Server")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    let server = CustomMCPServerConfig.stdio(
        name: "MCP Server 1",
        command: "/path/to/server"
    )

    do {
        // Add server
        try storage.addCustomServer(server)

        // Verify
        let servers = try storage.allCustomServers()
        TestRunner.assertEqual(servers.count, 1, "One server added")
        TestRunner.assertEqual(servers[0].name, "MCP Server 1", "Server name correct")
        TestRunner.assertEqual(servers[0].id, server.id, "Server ID correct")

        // Add another server
        let server2 = CustomMCPServerConfig.stdio(
            name: "MCP Server 2",
            command: "/path/to/server2"
        )
        try storage.addCustomServer(server2)

        let allServers = try storage.allCustomServers()
        TestRunner.assertEqual(allServers.count, 2, "Two servers total")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testUpdateCustomServer() {
    TestRunner.suite("Update Custom Server")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    let serverId = UUID()
    let server = CustomMCPServerConfig(
        id: serverId,
        name: "Original Name",
        type: .stdio,
        enabled: true,
        transport: .stdio(StdioConfig(command: "/usr/bin/node"))
    )

    do {
        // Add server
        try storage.addCustomServer(server)

        // Create updated version
        var updatedServer = server
        updatedServer.name = "Updated Name"
        updatedServer.enabled = false

        // Update server
        try storage.updateCustomServer(updatedServer)

        // Verify
        let loaded = try storage.customServer(id: serverId)
        TestRunner.assertNotNil(loaded, "Server still exists")
        TestRunner.assertEqual(loaded?.name, "Updated Name", "Name was updated")
        TestRunner.assertFalse(loaded?.enabled ?? true, "Enabled was updated")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testRemoveCustomServer() {
    TestRunner.suite("Remove Custom Server")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    let server1 = CustomMCPServerConfig.stdio(name: "Server 1", command: "/bin/1")
    let server2 = CustomMCPServerConfig.stdio(name: "Server 2", command: "/bin/2")

    do {
        // Add two servers
        try storage.addCustomServer(server1)
        try storage.addCustomServer(server2)

        TestRunner.assertEqual(try storage.allCustomServers().count, 2, "Two servers before removal")

        // Remove first server
        try storage.removeCustomServer(id: server1.id)

        // Verify
        let remaining = try storage.allCustomServers()
        TestRunner.assertEqual(remaining.count, 1, "One server remaining")
        TestRunner.assertEqual(remaining[0].id, server2.id, "Correct server remains")

        // Verify removed server is not found
        let notFound = try storage.customServer(id: server1.id)
        TestRunner.assertNil(notFound, "Removed server not found")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testGetCustomServerById() {
    TestRunner.suite("Get Custom Server by ID")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    let server = CustomMCPServerConfig.stdio(
        name: "Specific Server",
        command: "/usr/local/bin/mcp"
    )

    do {
        try storage.addCustomServer(server)

        // Get by ID
        let found = try storage.customServer(id: server.id)
        TestRunner.assertNotNil(found, "Server found by ID")
        TestRunner.assertEqual(found?.name, "Specific Server", "Correct server returned")

        // Get by non-existent ID
        let notFound = try storage.customServer(id: UUID())
        TestRunner.assertNil(notFound, "Non-existent ID returns nil")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testEnabledCustomServers() {
    TestRunner.suite("Enabled Custom Servers Filter")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    let enabledServer = CustomMCPServerConfig.stdio(name: "Enabled", command: "/bin/1", enabled: true)
    let disabledServer = CustomMCPServerConfig.stdio(name: "Disabled", command: "/bin/2", enabled: false)

    do {
        try storage.addCustomServer(enabledServer)
        try storage.addCustomServer(disabledServer)

        let allServers = try storage.allCustomServers()
        TestRunner.assertEqual(allServers.count, 2, "Two total servers")

        let enabled = try storage.enabledCustomServers()
        TestRunner.assertEqual(enabled.count, 1, "One enabled server")
        TestRunner.assertEqual(enabled[0].name, "Enabled", "Correct enabled server")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testSetEnabled() {
    TestRunner.suite("Set Enabled State")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    let server = CustomMCPServerConfig.stdio(name: "Toggle Server", command: "/bin/toggle", enabled: true)

    do {
        try storage.addCustomServer(server)

        // Verify initially enabled
        let initial = try storage.customServer(id: server.id)
        TestRunner.assertTrue(initial?.enabled ?? false, "Initially enabled")

        // Disable
        try storage.setEnabled(false, forCustomServer: server.id)
        let disabled = try storage.customServer(id: server.id)
        TestRunner.assertFalse(disabled?.enabled ?? true, "Now disabled")

        // Re-enable
        try storage.setEnabled(true, forCustomServer: server.id)
        let enabled = try storage.customServer(id: server.id)
        TestRunner.assertTrue(enabled?.enabled ?? false, "Re-enabled")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testDeleteConfigFile() {
    TestRunner.suite("Delete Config File")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    do {
        // Create config file by saving
        let server = CustomMCPServerConfig.stdio(name: "Test", command: "/bin/test")
        try storage.addCustomServer(server)

        TestRunner.assertTrue(storage.configFileExists, "Config file exists before delete")

        // Delete config file
        try storage.deleteConfigFile()

        TestRunner.assertFalse(storage.configFileExists, "Config file deleted")

        // Load should return empty config
        let config = try storage.load()
        TestRunner.assertTrue(config.custom.isEmpty, "Empty config after delete")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testMultipleServersRoundTrip() {
    TestRunner.suite("Multiple Servers Round Trip")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    let servers = [
        CustomMCPServerConfig.stdio(name: "Server A", command: "/bin/a"),
        CustomMCPServerConfig.stdio(name: "Server B", command: "/bin/b", enabled: false),
        CustomMCPServerConfig.stdio(name: "Server C", command: "/bin/c", args: ["-v", "--debug"])
    ]

    do {
        // Add all servers
        for server in servers {
            try storage.addCustomServer(server)
        }

        // Verify all servers persisted
        let loaded = try storage.allCustomServers()
        TestRunner.assertEqual(loaded.count, 3, "Three servers loaded")

        // Verify names are all present
        let names = Set(loaded.map { $0.name })
        TestRunner.assertTrue(names.contains("Server A"), "Server A present")
        TestRunner.assertTrue(names.contains("Server B"), "Server B present")
        TestRunner.assertTrue(names.contains("Server C"), "Server C present")

        // Verify enabled filter
        let enabledCount = try storage.enabledCustomServers().count
        TestRunner.assertEqual(enabledCount, 2, "Two enabled servers")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testConfigVersionPreserved() {
    TestRunner.suite("Config Version Preserved")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    do {
        // Save empty config
        let config = ConnectorConfigFile.empty
        try storage.save(config)

        // Load and check version
        let loaded = try storage.load()
        TestRunner.assertEqual(loaded.version, ConnectorConfigFile.currentVersion, "Version preserved")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testTransportConfigPreserved() {
    TestRunner.suite("Transport Config Preserved")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    let stdioServer = CustomMCPServerConfig.stdio(
        name: "STDIO Server",
        command: "/usr/bin/node",
        args: ["--inspect", "server.js"],
        env: ["NODE_ENV": "production", "DEBUG": "mcp:*"]
    )

    do {
        try storage.addCustomServer(stdioServer)

        let loaded = try storage.customServer(id: stdioServer.id)
        TestRunner.assertNotNil(loaded, "Server loaded")

        if case .stdio(let config) = loaded?.transport {
            TestRunner.assertEqual(config.command, "/usr/bin/node", "Command preserved")
            TestRunner.assertEqual(config.args.count, 2, "Args count preserved")
            TestRunner.assertEqual(config.args[0], "--inspect", "First arg preserved")
            TestRunner.assertEqual(config.env["NODE_ENV"], "production", "Env var preserved")
            TestRunner.assertEqual(config.env["DEBUG"], "mcp:*", "Second env var preserved")
        } else {
            TestRunner.assertTrue(false, "Transport config should be STDIO")
        }
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

func testAddServerWithSameIdReplaces() {
    TestRunner.suite("Add Server With Same ID Replaces")

    let storage = TestConnectorConfigStorage()
    defer { storage.cleanup() }

    let serverId = UUID()
    let server1 = CustomMCPServerConfig(
        id: serverId,
        name: "Original",
        type: .stdio,
        transport: .stdio(StdioConfig(command: "/bin/1"))
    )
    let server2 = CustomMCPServerConfig(
        id: serverId,
        name: "Replacement",
        type: .stdio,
        transport: .stdio(StdioConfig(command: "/bin/2"))
    )

    do {
        try storage.addCustomServer(server1)
        TestRunner.assertEqual(try storage.allCustomServers().count, 1, "One server after first add")

        try storage.addCustomServer(server2)
        TestRunner.assertEqual(try storage.allCustomServers().count, 1, "Still one server after second add")

        let loaded = try storage.customServer(id: serverId)
        TestRunner.assertEqual(loaded?.name, "Replacement", "Server was replaced")
    } catch {
        TestRunner.assertTrue(false, "Should not throw: \(error)")
    }
}

// MARK: - Main

@main
struct ConnectorConfigStorageTestsMain {
    static func main() {
        print("🧪 Connector Config Storage Unit Tests")
        print("==================================================")

        testEmptyConfigOnNoFile()
        testSaveAndLoad()
        testAddCustomServer()
        testUpdateCustomServer()
        testRemoveCustomServer()
        testGetCustomServerById()
        testEnabledCustomServers()
        testSetEnabled()
        testDeleteConfigFile()
        testMultipleServersRoundTrip()
        testConfigVersionPreserved()
        testTransportConfigPreserved()
        testAddServerWithSameIdReplaces()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
