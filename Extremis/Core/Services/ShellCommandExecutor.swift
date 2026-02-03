// MARK: - Shell Command Executor
// Safe execution of shell commands with sandboxing support

import Foundation

// MARK: - Shell Execution Result

/// Result of a shell command execution
struct ShellExecutionResult: Sendable {
    /// Standard output from the command
    let stdout: String

    /// Standard error from the command
    let stderr: String

    /// Exit code of the command
    let exitCode: Int32

    /// Execution duration in seconds
    let duration: TimeInterval

    /// Whether the command was sandboxed
    let wasSandboxed: Bool

    /// Whether execution succeeded (exit code 0)
    var isSuccess: Bool { exitCode == 0 }

    /// Combined output (stdout + stderr)
    var combinedOutput: String {
        var output = stdout
        if !stderr.isEmpty {
            if !output.isEmpty {
                output += "\n"
            }
            output += stderr
        }
        return output
    }

    /// Truncated output for display (max 10000 chars)
    var truncatedOutput: String {
        let output = combinedOutput
        if output.count > 10000 {
            return String(output.prefix(10000)) + "\n... (output truncated)"
        }
        return output
    }
}

// MARK: - Shell Execution Error

/// Errors that can occur during shell execution
enum ShellExecutionError: LocalizedError, Sendable {
    case commandEmpty
    case commandBlocked(reason: String)
    case validationFailed(issues: [String])
    case executionFailed(message: String)
    case timeout
    case sandboxFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .commandEmpty:
            return "Command is empty"
        case .commandBlocked(let reason):
            return "Command blocked: \(reason)"
        case .validationFailed(let issues):
            return "Validation failed: \(issues.joined(separator: "; "))"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .timeout:
            return "Command execution timed out"
        case .sandboxFailed(let message):
            return "Sandbox error: \(message)"
        }
    }
}

// MARK: - Shell Command Executor

/// Executes shell commands safely with optional sandboxing
@MainActor
final class ShellCommandExecutor {

    // MARK: - Singleton

    static let shared = ShellCommandExecutor()

    // MARK: - Configuration

    /// Default timeout for command execution (30 seconds)
    private let defaultTimeout: TimeInterval = 30.0

    /// Maximum output size (1MB)
    private let maxOutputSize = 1024 * 1024

    // MARK: - Sandbox Profile

    /// Read-only sandbox profile content
    /// Restricts: network, file writes, process control
    private let readOnlySandboxProfile = """
    (version 1)
    (deny default)

    ; Allow read access to most of the filesystem
    (allow file-read*)

    ; Allow executing programs
    (allow process-exec*)
    (allow process-fork)

    ; Allow basic system operations
    (allow sysctl-read)
    (allow mach-lookup)
    (allow signal (target self))

    ; Allow reading system info
    (allow system-info)

    ; Deny network access
    (deny network*)

    ; Deny file writes
    (deny file-write*)

    ; Allow writing to /dev/null and /dev/tty
    (allow file-write* (literal "/dev/null"))
    (allow file-write* (literal "/dev/tty"))
    (allow file-write* (regex #"^/dev/ttys[0-9]+$"))

    ; Allow IPC for basic functionality
    (allow ipc-posix-shm-read*)
    """

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Execute a shell command with appropriate safety measures
    /// - Parameters:
    ///   - command: The command to execute
    ///   - workingDirectory: Optional working directory
    ///   - timeout: Optional timeout (defaults to 30 seconds)
    /// - Returns: The execution result
    /// - Throws: ShellExecutionError on failure
    func execute(
        _ command: String,
        workingDirectory: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ShellExecutionResult {
        // Validate the command
        let validation = ShellCommandClassifier.validate(command)
        guard validation.isValid else {
            throw ShellExecutionError.validationFailed(issues: validation.issues)
        }

        // Classify the command
        let riskLevel = ShellCommandClassifier.classify(command)

        // Block privileged commands
        guard riskLevel.isAllowed else {
            throw ShellExecutionError.commandBlocked(
                reason: "Privileged commands are not allowed"
            )
        }

        // Execute with or without sandbox based on risk level
        if riskLevel.shouldSandbox {
            return try await executeInSandbox(
                command,
                workingDirectory: workingDirectory,
                timeout: timeout ?? defaultTimeout
            )
        } else {
            return try await executeDirect(
                command,
                workingDirectory: workingDirectory,
                timeout: timeout ?? defaultTimeout
            )
        }
    }

    /// Get the risk level of a command without executing it
    /// - Parameter command: The command to classify
    /// - Returns: The risk level
    func classifyCommand(_ command: String) -> CommandRiskLevel {
        ShellCommandClassifier.classify(command)
    }

    /// Validate a command without executing it
    /// - Parameter command: The command to validate
    /// - Returns: Validation result
    func validateCommand(_ command: String) -> ShellCommandValidation {
        ShellCommandClassifier.validate(command)
    }

    // MARK: - Private Methods

    /// Execute a command directly without sandboxing
    private func executeDirect(
        _ command: String,
        workingDirectory: String?,
        timeout: TimeInterval
    ) async throws -> ShellExecutionResult {
        let startTime = Date()
        let maxOutput = maxOutputSize

        return try await withThrowingTaskGroup(of: ShellExecutionResult.self) { group in
            // Main execution task
            group.addTask {
                try self.runProcess(
                    executablePath: "/bin/bash",
                    arguments: ["-c", command],
                    workingDirectory: workingDirectory,
                    wasSandboxed: false,
                    startTime: startTime,
                    maxOutputSize: maxOutput
                )
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ShellExecutionError.timeout
            }

            // Return first completed result (or throw first error)
            guard let result = try await group.next() else {
                throw ShellExecutionError.executionFailed(message: "No result from execution")
            }

            // Cancel remaining tasks
            group.cancelAll()

            return result
        }
    }

    /// Execute a command inside a sandbox
    private func executeInSandbox(
        _ command: String,
        workingDirectory: String?,
        timeout: TimeInterval
    ) async throws -> ShellExecutionResult {
        let startTime = Date()
        let maxOutput = maxOutputSize

        // Create temporary sandbox profile file
        let profilePath = try createSandboxProfile()
        defer {
            try? FileManager.default.removeItem(atPath: profilePath)
        }

        return try await withThrowingTaskGroup(of: ShellExecutionResult.self) { group in
            // Main execution task
            group.addTask {
                try self.runProcess(
                    executablePath: "/usr/bin/sandbox-exec",
                    arguments: ["-f", profilePath, "/bin/bash", "-c", command],
                    workingDirectory: workingDirectory,
                    wasSandboxed: true,
                    startTime: startTime,
                    maxOutputSize: maxOutput
                )
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ShellExecutionError.timeout
            }

            // Return first completed result
            guard let result = try await group.next() else {
                throw ShellExecutionError.executionFailed(message: "No result from execution")
            }

            // Cancel remaining tasks
            group.cancelAll()

            return result
        }
    }

    /// Run a process and capture output
    /// Uses synchronous waitUntilExit to avoid concurrency issues with mutable captures
    private nonisolated func runProcess(
        executablePath: String,
        arguments: [String],
        workingDirectory: String?,
        wasSandboxed: Bool,
        startTime: Date,
        maxOutputSize: Int
    ) throws -> ShellExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        if let dir = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ShellExecutionError.executionFailed(
                message: error.localizedDescription
            )
        }

        // Wait for process to complete
        process.waitUntilExit()

        // Read all output after process exits (no concurrency issues)
        var stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        var stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        // Truncate if exceeds max size
        if stdoutData.count > maxOutputSize {
            stdoutData = stdoutData.prefix(maxOutputSize)
        }
        if stderrData.count > maxOutputSize {
            stderrData = stderrData.prefix(maxOutputSize)
        }

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let duration = Date().timeIntervalSince(startTime)

        return ShellExecutionResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus,
            duration: duration,
            wasSandboxed: wasSandboxed
        )
    }

    /// Create a temporary sandbox profile file
    private func createSandboxProfile() throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let profileURL = tempDir.appendingPathComponent("extremis-sandbox-\(UUID().uuidString).sb")

        try readOnlySandboxProfile.write(to: profileURL, atomically: true, encoding: .utf8)

        return profileURL.path
    }
}
