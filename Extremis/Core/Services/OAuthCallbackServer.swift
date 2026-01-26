// MARK: - OAuth Callback Server
// Local HTTP server to receive OAuth authorization callbacks

import Foundation
import Network

/// Local HTTP server that listens for OAuth callbacks
/// Binds to 127.0.0.1 on a random available port
actor OAuthCallbackServer {

    // MARK: - Types

    /// Result of waiting for a callback
    struct CallbackResult {
        let code: String
        let state: String
    }

    // MARK: - Properties

    private var listener: NWListener?
    private var port: UInt16 = 0
    private var continuation: CheckedContinuation<CallbackResult, Error>?
    private var isRunning = false

    // MARK: - Public Interface

    /// The port the server is listening on (0 if not started)
    var listeningPort: Int {
        Int(port)
    }

    /// Start the server and wait for a callback
    /// Returns the authorization code and state from the callback
    /// - Parameter timeout: Maximum time to wait for callback (default 5 minutes)
    func waitForCallback(timeout: TimeInterval = 300) async throws -> CallbackResult {
        // Start the server
        try await start()

        // Wait for callback with timeout
        return try await withThrowingTaskGroup(of: CallbackResult.self) { group in
            // Task 1: Wait for the actual callback
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    Task { await self.setContinuation(continuation) }
                }
            }

            // Task 2: Timeout
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw OAuthError.flowExpired
            }

            // Return whichever completes first
            let result = try await group.next()!
            group.cancelAll()
            await stop()
            return result
        }
    }

    /// Stop the server
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        port = 0

        // Cancel any pending continuation
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    // MARK: - Private Methods

    private func setContinuation(_ cont: CheckedContinuation<CallbackResult, Error>) {
        self.continuation = cont
    }

    private func start() async throws {
        guard !isRunning else { return }

        // Create parameters for TCP on localhost only
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 0)!  // Let system assign port
        )

        // Create listener
        let listener = try NWListener(using: parameters)

        // Set up state handler
        listener.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleStateUpdate(state) }
        }

        // Set up new connection handler
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }

        self.listener = listener
        listener.start(queue: .global(qos: .userInitiated))

        // Wait for listener to be ready
        try await waitForListenerReady()

        isRunning = true
    }

    private func waitForListenerReady() async throws {
        // Poll for port assignment (NWListener assigns port asynchronously)
        for _ in 0..<50 {  // 5 second timeout
            if let listenerPort = listener?.port?.rawValue, listenerPort > 0 {
                self.port = listenerPort
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }
        throw OAuthError.callbackServerFailed("Failed to bind to port")
    }

    private func handleStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let assignedPort = listener?.port?.rawValue {
                self.port = assignedPort
                print("🔐 OAuth callback server listening on port \(assignedPort)")
            }
        case .failed(let error):
            print("🔐 OAuth callback server failed: \(error)")
            continuation?.resume(throwing: OAuthError.callbackServerFailed(error.localizedDescription))
            continuation = nil
        case .cancelled:
            print("🔐 OAuth callback server cancelled")
        default:
            break
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                Task { await self?.receiveRequest(connection) }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func receiveRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            Task { await self?.processRequest(data: data, error: error, connection: connection) }
        }
    }

    private func processRequest(data: Data?, error: NWError?, connection: NWConnection) {
        defer { connection.cancel() }

        guard error == nil, let data = data else {
            print("🔐 OAuth callback: Error receiving data: \(error?.localizedDescription ?? "unknown")")
            return
        }

        guard let request = String(data: data, encoding: .utf8) else {
            sendErrorResponse(connection: connection, message: "Invalid request encoding")
            return
        }

        // Parse HTTP request to extract path and query
        guard let (path, queryParams) = parseHTTPRequest(request) else {
            sendErrorResponse(connection: connection, message: "Invalid HTTP request")
            return
        }

        // Only handle /callback path
        guard path == "/callback" || path == "/oauth/callback" else {
            sendErrorResponse(connection: connection, message: "Not found", statusCode: 404)
            return
        }

        // Check for error from OAuth provider
        if let oauthError = queryParams["error"] {
            let description = queryParams["error_description"] ?? oauthError
            sendErrorResponse(connection: connection, message: "Authorization failed: \(description)")
            continuation?.resume(throwing: OAuthError.authorizationFailed(description))
            continuation = nil
            return
        }

        // Extract code and state
        guard let code = queryParams["code"], let state = queryParams["state"] else {
            sendErrorResponse(connection: connection, message: "Missing code or state parameter")
            return
        }

        // Send success response
        sendSuccessResponse(connection: connection)

        // Resume the continuation with the result
        let result = CallbackResult(code: code, state: state)
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func parseHTTPRequest(_ request: String) -> (path: String, queryParams: [String: String])? {
        // Parse first line: GET /callback?code=xxx&state=yyy HTTP/1.1
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let fullPath = String(parts[1])

        // Split path and query string
        let pathParts = fullPath.split(separator: "?", maxSplits: 1)
        let path = String(pathParts[0])

        var queryParams: [String: String] = [:]
        if pathParts.count > 1 {
            let queryString = String(pathParts[1])
            for param in queryString.split(separator: "&") {
                let keyValue = param.split(separator: "=", maxSplits: 1)
                if keyValue.count == 2 {
                    let key = String(keyValue[0])
                    let value = String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1])
                    queryParams[key] = value
                }
            }
        }

        return (path, queryParams)
    }

    private func sendSuccessResponse(connection: NWConnection) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Authorization Successful</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                }
                .container {
                    text-align: center;
                    padding: 40px;
                    background: rgba(255,255,255,0.1);
                    border-radius: 16px;
                    backdrop-filter: blur(10px);
                }
                h1 { font-size: 24px; margin-bottom: 16px; }
                p { opacity: 0.9; }
                .checkmark {
                    font-size: 48px;
                    margin-bottom: 16px;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="checkmark">✓</div>
                <h1>Authorization Successful</h1>
                <p>You can close this window and return to Extremis.</p>
            </div>
            <script>setTimeout(() => window.close(), 3000);</script>
        </body>
        </html>
        """

        sendHTTPResponse(connection: connection, statusCode: 200, body: html)
    }

    private func sendErrorResponse(connection: NWConnection, message: String, statusCode: Int = 400) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Authorization Failed</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                    background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
                    color: white;
                }
                .container {
                    text-align: center;
                    padding: 40px;
                    background: rgba(255,255,255,0.1);
                    border-radius: 16px;
                    backdrop-filter: blur(10px);
                }
                h1 { font-size: 24px; margin-bottom: 16px; }
                p { opacity: 0.9; }
                .icon { font-size: 48px; margin-bottom: 16px; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="icon">✗</div>
                <h1>Authorization Failed</h1>
                <p>\(message)</p>
                <p>Please close this window and try again.</p>
            </div>
        </body>
        </html>
        """

        sendHTTPResponse(connection: connection, statusCode: statusCode, body: html)
    }

    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, body: String) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        default: statusText = "Error"
        }

        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }
}
