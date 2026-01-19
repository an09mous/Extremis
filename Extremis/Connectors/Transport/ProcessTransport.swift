import Foundation
import MCP
import Logging

/// Helper class to manage mutable state for readability handler callbacks
/// This is needed because readabilityHandler is callback-based and needs thread-safe state
private final class ReadState: @unchecked Sendable {
    private let logger: Logger
    private let continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private var buffer = Data()
    private let lock = NSLock()

    init(logger: Logger, continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation) {
        self.logger = logger
        self.continuation = continuation
    }

    func processData(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)

        // Process complete lines (newline-delimited)
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])

            if lineData.isEmpty { continue }

            // Check if line looks like JSON (starts with '{' or '[', allowing leading whitespace)
            // Some MCP servers incorrectly print status messages to stdout
            if looksLikeJSON(lineData) {
                logger.trace("Received message (\(lineData.count) bytes)")
                continuation.yield(Data(lineData))
            } else {
                // Log non-JSON lines as debug (likely server status messages)
                if let line = String(data: lineData, encoding: .utf8) {
                    logger.debug("Ignoring non-JSON stdout: \(line)")
                }
            }
        }
    }

    /// Check if data looks like JSON (starts with '{' or '[', allowing leading whitespace)
    private func looksLikeJSON(_ data: Data) -> Bool {
        // Find first non-whitespace byte
        for byte in data {
            // Skip whitespace (space, tab, carriage return)
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\r") {
                continue
            }
            // Check if it's a JSON start character
            return byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[")
        }
        return false
    }
}

/// Transport implementation for MCP servers running as subprocesses.
///
/// This transport spawns an MCP server as a subprocess and communicates with it
/// via stdin/stdout pipes using the MCP stdio transport protocol.
public actor ProcessTransport: Transport {
    // MARK: - Configuration

    /// Configuration for the subprocess
    public struct Configuration: Sendable {
        /// Path to the executable
        let command: String
        /// Arguments to pass to the executable
        let args: [String]
        /// Environment variables for the process
        let environment: [String: String]

        public init(command: String, args: [String] = [], environment: [String: String] = [:]) {
            self.command = command
            self.args = args
            self.environment = environment
        }
    }

    // MARK: - Properties

    public nonisolated let logger: Logger

    private let config: Configuration
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var isConnectedFlag = false

    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation

    private var stderrTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(config: Configuration, logger: Logger? = nil) {
        self.config = config
        self.logger = logger ?? Logger(label: "mcp.transport.process")

        // Create message stream
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
    }

    deinit {
        stderrTask?.cancel()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
    }

    // MARK: - Transport Protocol

    public func connect() async throws {
        guard !isConnectedFlag else {
            logger.debug("Already connected, skipping")
            return
        }

        logger.info("Spawning subprocess: \(config.command) \(config.args.joined(separator: " "))")

        // Resolve command path (supports both absolute paths and commands in PATH)
        guard let resolvedPath = resolveCommandPath(config.command) else {
            let errorMessage = "Command not found: '\(config.command)'. Make sure it's installed and in your PATH."
            logger.error("\(errorMessage)")
            throw MCPError.internalError(errorMessage)
        }

        logger.debug("Resolved command path: \(resolvedPath)")

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPath)
        process.arguments = config.args

        // Merge current environment with config environment
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in config.environment {
            environment[key] = value
        }

        // Force unbuffered stdout for Node.js processes
        // Without this, Node.js buffers output when stdout is not a TTY
        environment["NODE_OPTIONS"] = (environment["NODE_OPTIONS"] ?? "") + " --no-warnings"
        environment["FORCE_COLOR"] = "0"  // Disable color codes

        // Python unbuffered mode
        environment["PYTHONUNBUFFERED"] = "1"

        process.environment = environment

        // Create pipes
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Store references
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        // Start process
        do {
            try process.run()
            logger.info("Process started (PID: \(process.processIdentifier))")
        } catch {
            logger.error("Failed to spawn process: \(error.localizedDescription)")
            throw MCPError.transportError(error)
        }

        // Wait briefly for process to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Verify process is running
        guard process.isRunning else {
            let exitCode = process.terminationStatus
            logger.error("Process exited immediately with code \(exitCode)")
            throw MCPError.internalError("Process exited with code \(exitCode)")
        }

        isConnectedFlag = true

        // Set up stdout reading using readabilityHandler
        // This works better than async byte iteration for Node.js processes
        setupStdoutHandler()

        // Start reading stderr for logging
        stderrTask = Task { [weak self] in
            await self?.readStderrLoop()
        }

        logger.info("Process transport connected successfully")
    }

    public func disconnect() async {
        guard isConnectedFlag else { return }

        logger.info("Disconnecting process transport...")
        isConnectedFlag = false

        // Clean up stdout handler
        cleanupStdoutHandler()

        // Cancel stderr task
        stderrTask?.cancel()

        // Finish the message stream
        messageContinuation.finish()

        // Terminate process
        if let process = process, process.isRunning {
            process.terminate()
            logger.debug("Process terminated")
        }

        // Clean up
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        logger.info("Process transport disconnected")
    }

    public func send(_ data: Data) async throws {
        guard isConnectedFlag else {
            throw MCPError.internalError("Transport not connected")
        }

        guard let stdinPipe = stdinPipe else {
            throw MCPError.internalError("stdin pipe not available")
        }

        // Add newline delimiter
        var messageWithNewline = data
        messageWithNewline.append(UInt8(ascii: "\n"))

        let fileHandle = stdinPipe.fileHandleForWriting

        do {
            try fileHandle.write(contentsOf: messageWithNewline)
            // Note: synchronize() doesn't work on pipes (returns ENOTSUP)
            // The write is unbuffered for pipes, so no explicit flush is needed
            logger.trace("Sent message (\(data.count) bytes)")
        } catch {
            logger.error("Failed to write to stdin: \(error.localizedDescription)")
            throw MCPError.transportError(error)
        }
    }

    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return messageStream
    }

    // MARK: - Private Methods

    /// Resolve a command to its full path by searching PATH
    /// - Parameter command: The command name (e.g., "node") or absolute path
    /// - Returns: Full path to the executable, or nil if not found
    private func resolveCommandPath(_ command: String) -> String? {
        // If it's already an absolute path, use it directly
        if command.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: command) ? command : nil
        }

        // Common paths to search (in addition to PATH env var)
        // These cover typical installation locations for tools like node, python, etc.
        let commonPaths = [
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/opt/homebrew/bin",  // Apple Silicon Homebrew
            "/opt/local/bin",     // MacPorts
            NSHomeDirectory() + "/.nvm/current/bin",  // NVM (Node Version Manager)
            NSHomeDirectory() + "/.volta/bin",        // Volta (Node version manager)
            NSHomeDirectory() + "/.local/bin",        // pipx, cargo, etc.
        ]

        // Get PATH from environment
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathDirs = pathEnv.split(separator: ":").map(String.init)

        // Combine PATH directories with common paths (PATH takes priority)
        var searchPaths = pathDirs
        for path in commonPaths {
            if !searchPaths.contains(path) {
                searchPaths.append(path)
            }
        }

        // Search for the command in all paths
        for dir in searchPaths {
            let fullPath = (dir as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }

    /// Set up stdout reading using readabilityHandler (callback-based)
    /// This works better than async byte iteration for Node.js processes which buffer stdout
    private func setupStdoutHandler() {
        guard let stdoutPipe = stdoutPipe else { return }

        let fileHandle = stdoutPipe.fileHandleForReading
        logger.debug("Setting up stdout readability handler")

        // Use a class to hold mutable state for the callback
        let state = ReadState(logger: logger, continuation: messageContinuation)

        fileHandle.readabilityHandler = { [weak self] handle in
            guard let self = self else {
                handle.readabilityHandler = nil
                return
            }

            let data = handle.availableData

            // Check if we got EOF
            if data.isEmpty {
                self.logger.debug("Stdout: EOF received")
                handle.readabilityHandler = nil
                self.messageContinuation.finish()
                return
            }

            // Process the received data
            state.processData(data)
        }
    }

    /// Clean up stdout handler
    private func cleanupStdoutHandler() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
    }

    private func readStderrLoop() async {
        guard let stderrPipe = stderrPipe else { return }

        let fileHandle = stderrPipe.fileHandleForReading

        do {
            for try await line in fileHandle.bytes.lines {
                if Task.isCancelled || !isConnectedFlag {
                    break
                }

                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    logger.warning("Server stderr: \(trimmed)")
                }
            }
        } catch {
            if !Task.isCancelled && isConnectedFlag {
                logger.debug("Stderr read ended: \(error.localizedDescription)")
            }
        }
    }
}
