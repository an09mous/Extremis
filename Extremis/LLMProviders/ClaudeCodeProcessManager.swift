// MARK: - Claude Code Process Manager
// Manages a persistent Claude Code CLI subprocess
// Uses --input-format stream-json for bidirectional NDJSON communication
// One long-lived process handles all messages via stdin/stdout

import Foundation

/// Manages the persistent Claude Code CLI subprocess
@MainActor
final class ClaudeCodeProcessManager {

    // MARK: - Types

    enum ProcessState: Equatable {
        case stopped
        case starting
        case ready
        case generating
        case error(String)

        static func == (lhs: ProcessState, rhs: ProcessState) -> Bool {
            switch (lhs, rhs) {
            case (.stopped, .stopped), (.starting, .starting),
                 (.ready, .ready), (.generating, .generating):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    @Published private(set) var processState: ProcessState = .stopped

    /// The persistent CLI process
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdinPipe: Pipe?

    private let parser = CLIStreamParser()

    /// Captured tools from system/init event
    private(set) var discoveredTools: [String] = []

    /// Session ID from the CLI process
    private(set) var sessionId: String?

    /// Active continuation for current generation stream
    private var activeContinuation: AsyncThrowingStream<ParsedCLIEvent, Error>.Continuation?

    /// Stderr accumulator for error reporting
    private var stderrBuffer: String = ""

    /// Line buffer for incremental stdout reads
    private var stdoutBuffer = Data()

    /// Generation counter — prevents stale handlers from affecting newer generations
    private var generationId: UInt64 = 0

    /// Whether the process has emitted its first system/init (ready to accept messages)
    private var processInitialized = false

    // MARK: - Process Lifecycle

    /// Start the persistent CLI process
    func start(
        binaryPath: String = "claude",
        model: String = "sonnet",
        allowedTools: [String] = [],
        systemPrompt: String? = nil
    ) async throws {
        // Already running — no-op
        if process?.isRunning == true {
            return
        }

        // Kill any existing process before starting fresh
        stopProcess()

        processState = .starting
        processInitialized = false
        stderrBuffer = ""
        stdoutBuffer = Data()

        let resolvedPath: String
        if binaryPath != "claude" {
            resolvedPath = binaryPath
        } else {
            resolvedPath = await Self.resolveClaudePath() ?? "claude"
        }

        var args = [
            resolvedPath, "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--model", model,
            "--include-partial-messages"
        ]

        if !allowedTools.isEmpty {
            args += ["--allowedTools", allowedTools.joined(separator: ",")]
        }

        // Suppress notification hooks (sounds) when running as subprocess
        args += ["--settings", "{\"disableAllHooks\":true}"]

        if let prompt = systemPrompt, !prompt.isEmpty {
            args += ["--append-system-prompt", prompt]
        }

        let proc = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = args
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr
        // Inherit environment but suppress sounds/notifications
        // TERM=dumb tells CLI it's in a non-interactive context
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        proc.environment = env

        self.process = proc
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.stdinPipe = stdin

        // Non-blocking stdout reader via readabilityHandler
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                Task { @MainActor [weak self] in
                    self?.handleStdoutEOF()
                }
                return
            }
            Task { @MainActor [weak self] in
                self?.handleStdoutData(data)
            }
        }

        // Non-blocking stderr reader
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    self?.stderrBuffer += text
                }
            }
        }

        // Termination handler — process crashed or was killed
        proc.terminationHandler = { [weak self] terminatedProc in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let exitCode = terminatedProc.terminationStatus

                if exitCode != 0 && self.processState != .stopped {
                    let errMsg = self.stderrBuffer.isEmpty
                        ? "Process exited with code \(exitCode)"
                        : self.stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

                    // If we were generating, fail the active stream
                    if self.processState == .generating {
                        self.activeContinuation?.finish(throwing: LLMProviderError.unknown(errMsg))
                        self.activeContinuation = nil
                    }

                    self.processState = .error(errMsg)
                } else if self.processState != .stopped {
                    // Clean exit but we didn't ask for it
                    self.activeContinuation?.finish()
                    self.activeContinuation = nil
                    self.processState = .stopped
                }

                self.processInitialized = false
                self.cleanupProcessState()
                print("Claude Code CLI process terminated (exit: \(exitCode))")
            }
        }

        try proc.run()
        // Process is running — mark ready immediately
        // system/init event arrives after first message with --input-format stream-json
        processState = .ready
        print("Claude Code CLI started (PID: \(proc.processIdentifier), model: \(model))")
    }

    /// Send a user message to the persistent process
    /// - Parameters:
    ///   - content: The text content of the message
    ///   - images: Optional image attachments to include (uses Anthropic multimodal content blocks)
    func sendMessage(_ content: String, images: [ImageAttachment]? = nil) -> AsyncThrowingStream<ParsedCLIEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                // Cancel any in-flight generation
                if self.activeContinuation != nil {
                    self.activeContinuation?.finish()
                    self.activeContinuation = nil
                }

                self.generationId &+= 1
                let currentGenId = self.generationId
                self.activeContinuation = continuation
                self.processState = .generating

                // Register cancellation handler
                continuation.onTermination = { @Sendable _ in
                    Task { @MainActor [weak self] in
                        guard let self = self, self.generationId == currentGenId else { return }
                        // Stream was cancelled by consumer — don't kill process, just clear state
                        if self.activeContinuation != nil {
                            self.activeContinuation = nil
                            if self.processState == .generating {
                                self.processState = .ready
                            }
                        }
                    }
                }

                guard self.process?.isRunning == true else {
                    continuation.finish(throwing: LLMProviderError.unknown("CLI process not running"))
                    self.activeContinuation = nil
                    self.processState = .error("CLI process not running")
                    return
                }

                // Build the NDJSON user message
                // If images are present, use Anthropic multimodal content blocks array
                // Otherwise, use plain string content
                let messageContent: Any
                if let images = images, !images.isEmpty {
                    messageContent = PromptBuilder.shared.formatAnthropicMultimodalContent(
                        text: content, images: images
                    )
                } else {
                    messageContent = content
                }

                let message: [String: Any] = [
                    "type": "user",
                    "message": [
                        "role": "user",
                        "content": messageContent
                    ]
                ]

                guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
                      var jsonString = String(data: jsonData, encoding: .utf8) else {
                    continuation.finish(throwing: LLMProviderError.unknown("Failed to encode message"))
                    self.activeContinuation = nil
                    self.processState = .ready
                    return
                }

                // Ensure newline terminator
                jsonString += "\n"

                guard let writeData = jsonString.data(using: .utf8) else {
                    continuation.finish(throwing: LLMProviderError.unknown("Failed to encode message data"))
                    self.activeContinuation = nil
                    self.processState = .ready
                    return
                }

                // Write to stdin
                self.stdinPipe?.fileHandleForWriting.write(writeData)

                let imageCount = images?.count ?? 0
                let imageInfo = imageCount > 0 ? ", images: \(imageCount)" : ""
                print("Sent message to CLI (gen: \(currentGenId)\(imageInfo), \(content.prefix(50))...)")
            }
        }
    }

    /// Cancel the current generation (does NOT kill the process)
    func cancelGeneration() {
        activeContinuation?.finish()
        activeContinuation = nil
        if processState == .generating {
            processState = .ready
        }
    }

    /// Reset conversation — kills process so next start() creates a fresh session
    func resetConversation() {
        cancelGeneration()
        stopProcess()
        sessionId = nil
        discoveredTools = []
        print("Claude Code conversation reset")
    }

    /// Stop the persistent process
    func stop() {
        cancelGeneration()
        stopProcess()
        sessionId = nil
        discoveredTools = []
        processState = .stopped
    }

    /// Force cleanup — registered in NSApplication.willTerminateNotification
    func forceCleanup() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        activeContinuation?.finish()
        activeContinuation = nil

        // Close stdin gracefully first (tells CLI to finish up)
        try? stdinPipe?.fileHandleForWriting.close()

        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        cleanupProcessState()
        processState = .stopped
    }

    /// Whether the process is running and ready to accept messages
    /// Note: with --input-format stream-json, system/init only arrives after first message
    var isReady: Bool {
        process?.isRunning == true
    }

    // MARK: - Private Helpers

    /// Handle incoming stdout data
    private func handleStdoutData(_ data: Data) {
        stdoutBuffer.append(data)

        // Process complete lines (NDJSON — one JSON object per line)
        while let newlineRange = stdoutBuffer.range(of: Data([0x0A])) {
            let lineData = stdoutBuffer[stdoutBuffer.startIndex..<newlineRange.lowerBound]
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newlineRange.lowerBound)

            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            handleParsedLine(trimmed)
        }
    }

    /// Handle stdout EOF (process closed stdout)
    private func handleStdoutEOF() {
        if activeContinuation != nil {
            activeContinuation?.finish()
            activeContinuation = nil
            if processState == .generating {
                processState = .error("Process closed stdout unexpectedly")
            }
        }
    }

    /// Handle a parsed NDJSON line from stdout
    private func handleParsedLine(_ line: String) {
        guard let event = parser.parseLine(line) else { return }

        switch event {
        case .initialized(let sid, let tools):
            // Capture session ID and tools
            if let sid = sid {
                sessionId = sid
            }
            discoveredTools = tools

            if !processInitialized {
                // First init — process is now ready
                processInitialized = true
                if processState == .starting {
                    processState = .ready
                }
                print("Claude Code CLI initialized (session: \(sid ?? "none"), tools: \(tools.count))")
            }
            // Per-turn init events are normal — just update tools/session

        case .resultSuccess(let sid, _, _):
            if let sid = sid {
                sessionId = sid
            }
            activeContinuation?.yield(event)
            activeContinuation?.finish()
            activeContinuation = nil
            processState = .ready

        case .resultError:
            activeContinuation?.yield(event)
            activeContinuation?.finish()
            activeContinuation = nil
            processState = .ready

        default:
            // Forward event to active generation stream
            activeContinuation?.yield(event)
        }
    }

    /// Stop the process gracefully
    private func stopProcess() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        // Close stdin to signal EOF — process should exit gracefully
        try? stdinPipe?.fileHandleForWriting.close()

        if let proc = process, proc.isRunning {
            proc.terminate()
        }

        cleanupProcessState()
        processInitialized = false
    }

    /// Clean up state without stopping process
    private func cleanupProcessState() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()
        stdoutPipe = nil
        stderrPipe = nil
        stdinPipe = nil
        process = nil
    }

    /// Resolve the full path to the claude binary
    static func resolveClaudePath() async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let proc = Process()
                let pipe = Pipe()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                proc.arguments = ["which", "claude"]
                proc.standardOutput = pipe
                proc.standardError = FileHandle.nullDevice

                do {
                    try proc.run()
                    proc.waitUntilExit()

                    if proc.terminationStatus == 0 {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                            cont.resume(returning: path)
                            return
                        }
                    }
                } catch {}
                cont.resume(returning: nil)
            }
        }
    }
}
