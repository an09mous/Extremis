// MARK: - HTTP Transport
// Transport implementation for remote MCP servers using HTTP/SSE

import Foundation
import MCP
import Logging

/// Transport implementation for remote MCP servers via HTTP/SSE.
///
/// This transport wraps the MCP SDK's `HTTPClientTransport` to communicate with
/// remote MCP servers using the Streamable HTTP transport protocol with optional SSE.
public actor HTTPTransport: Transport {
    // MARK: - Configuration

    /// Configuration for the HTTP transport
    public struct Configuration: Sendable {
        /// Server endpoint URL
        let url: URL
        /// Custom headers for requests
        let headers: [String: String]
        /// Whether to enable SSE streaming mode (default: true)
        let streaming: Bool

        public init(url: URL, headers: [String: String] = [:], streaming: Bool = true) {
            self.url = url
            self.headers = headers
            self.streaming = streaming
        }
    }

    // MARK: - Properties

    public nonisolated let logger: Logger

    private let config: Configuration
    private var underlyingTransport: HTTPClientTransport?
    private var isConnectedFlag = false

    // We need to manage our own stream since we can't call receive() synchronously on the underlying actor
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let messageContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private var receiveTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(config: Configuration, logger: Logger? = nil) {
        self.config = config
        self.logger = logger ?? Logger(label: "mcp.transport.http")

        // Create our own message stream
        var continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        self.messageStream = AsyncThrowingStream { continuation = $0 }
        self.messageContinuation = continuation
    }

    // MARK: - Transport Protocol

    public func connect() async throws {
        guard !isConnectedFlag else {
            logger.debug("Already connected, skipping")
            return
        }

        logger.info("Connecting to HTTP endpoint: \(config.url.absoluteString)")

        // Create request modifier to add custom headers
        let headers = config.headers
        let requestModifier: @Sendable (URLRequest) -> URLRequest = { request in
            var modifiedRequest = request
            for (key, value) in headers {
                modifiedRequest.addValue(value, forHTTPHeaderField: key)
            }
            return modifiedRequest
        }

        // Create the underlying SDK transport
        let transport = HTTPClientTransport(
            endpoint: config.url,
            streaming: config.streaming,
            requestModifier: requestModifier,
            logger: logger
        )

        do {
            try await transport.connect()
            underlyingTransport = transport
            isConnectedFlag = true

            // Start forwarding messages from underlying transport to our stream
            receiveTask = Task { [weak self] in
                await self?.forwardMessages(from: transport)
            }

            logger.info("HTTP transport connected successfully")
        } catch {
            logger.error("Failed to connect to HTTP endpoint: \(error.localizedDescription)")
            throw MCPError.transportError(error)
        }
    }

    public func disconnect() async {
        guard isConnectedFlag else { return }

        logger.info("Disconnecting HTTP transport...")
        isConnectedFlag = false

        // Cancel receive task
        receiveTask?.cancel()
        receiveTask = nil

        // Finish our message stream
        messageContinuation.finish()

        if let transport = underlyingTransport {
            await transport.disconnect()
        }

        underlyingTransport = nil
        logger.info("HTTP transport disconnected")
    }

    public func send(_ data: Data) async throws {
        guard isConnectedFlag else {
            throw MCPError.internalError("Transport not connected")
        }

        guard let transport = underlyingTransport else {
            throw MCPError.internalError("Underlying transport not available")
        }

        try await transport.send(data)
        logger.trace("Sent message (\(data.count) bytes)")
    }

    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        return messageStream
    }

    // MARK: - Private Methods

    /// Forward messages from underlying transport to our stream
    private func forwardMessages(from transport: HTTPClientTransport) async {
        let stream = await transport.receive()

        do {
            for try await data in stream {
                if Task.isCancelled || !isConnectedFlag {
                    break
                }
                messageContinuation.yield(data)
            }
        } catch {
            if !Task.isCancelled && isConnectedFlag {
                logger.error("Error receiving from underlying transport: \(error.localizedDescription)")
                messageContinuation.finish(throwing: error)
            }
        }
    }
}
