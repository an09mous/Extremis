import Foundation
import MCP
import Logging

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

    private var readTask: Task<Void, Never>?
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
        readTask?.cancel()
        stderrTask?.cancel()
        process?.terminate()
    }

    // MARK: - Transport Protocol

    public func connect() async throws {
        guard !isConnectedFlag else {
            logger.debug("Already connected, skipping")
            return
        }

        logger.info("Spawning subprocess: \(config.command) \(config.args.joined(separator: " "))")

        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.command)
        process.arguments = config.args

        // Merge current environment with config environment
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in config.environment {
            environment[key] = value
        }
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

        // Start reading stdout in background
        readTask = Task { [weak self] in
            await self?.readLoop()
        }

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

        // Cancel read tasks
        readTask?.cancel()
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

    private func readLoop() async {
        guard let stdoutPipe = stdoutPipe else { return }

        let fileHandle = stdoutPipe.fileHandleForReading
        logger.debug("Read loop started")

        var buffer = Data()

        do {
            for try await byte in fileHandle.bytes {
                if Task.isCancelled || !isConnectedFlag {
                    break
                }

                buffer.append(byte)

                // Process complete lines (newline-delimited JSON)
                if byte == UInt8(ascii: "\n") {
                    if !buffer.isEmpty {
                        // Remove the trailing newline for the message
                        let messageData = buffer.dropLast()
                        if !messageData.isEmpty {
                            logger.trace("Received message (\(messageData.count) bytes)")
                            messageContinuation.yield(Data(messageData))
                        }
                        buffer = Data()
                    }
                }
            }
            logger.debug("Read loop: end of stream")
        } catch {
            if !Task.isCancelled && isConnectedFlag {
                logger.error("Read error: \(error.localizedDescription)")
            }
        }

        messageContinuation.finish()
        logger.debug("Read loop ended")
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
