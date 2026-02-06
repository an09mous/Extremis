// MARK: - Shell Command Models
// Models for shell command risk classification and validation

import Foundation

// MARK: - Command Risk Level

/// Risk level classification for shell commands
enum CommandRiskLevel: String, Codable, CaseIterable, Sendable {
    /// Read-only system information commands (df, uptime, sw_vers)
    case safe

    /// Read filesystem commands (ls, cat, head)
    case read

    /// Modify filesystem commands (mkdir, touch, cp)
    case write

    /// Remove/overwrite commands (rm, mv)
    case destructive

    /// Sudo/admin commands - always blocked
    case privileged

    // MARK: - Display Properties

    /// Human-readable description
    var displayDescription: String {
        switch self {
        case .safe:
            return "Read-only system info"
        case .read:
            return "Read filesystem"
        case .write:
            return "Modify filesystem"
        case .destructive:
            return "Destructive operation"
        case .privileged:
            return "Privileged command"
        }
    }

    /// SF Symbol icon for UI
    var icon: String {
        switch self {
        case .safe:
            return "checkmark.shield"
        case .read:
            return "doc.text.magnifyingglass"
        case .write:
            return "pencil"
        case .destructive:
            return "exclamationmark.triangle"
        case .privileged:
            return "lock.shield"
        }
    }

    /// Color name for UI
    var colorName: String {
        switch self {
        case .safe:
            return "green"
        case .read:
            return "blue"
        case .write:
            return "yellow"
        case .destructive:
            return "red"
        case .privileged:
            return "purple"
        }
    }

    /// Whether this risk level requires sandboxing
    var shouldSandbox: Bool {
        switch self {
        case .safe, .read:
            return true
        case .write, .destructive, .privileged:
            return false
        }
    }

    /// Whether this risk level is allowed to execute
    var isAllowed: Bool {
        self != .privileged
    }
}

// MARK: - Shell Command Classification

/// Utility for classifying shell commands by risk level
enum ShellCommandClassifier {

    // MARK: - Known Command Lists

    /// Commands that are safe (read-only system info)
    static let safeCommands: Set<String> = [
        "sw_vers", "uname", "hostname", "whoami", "uptime", "df", "du",
        "ps", "top", "launchctl", "ifconfig", "networksetup", "scutil",
        "diskutil", "pmset", "caffeinate", "defaults", "system_profiler",
        "date", "cal", "env", "printenv", "which", "whereis", "type",
        "id", "groups", "arch", "sysctl", "vm_stat", "iostat", "nettop",
        "mdfind", "mdls", "xcode-select", "xcrun", "swift", "swiftc"
    ]

    /// Commands that read filesystem
    static let readCommands: Set<String> = [
        "cat", "head", "tail", "less", "more", "ls", "find", "grep",
        "awk", "sed", "wc", "sort", "uniq", "diff", "file", "stat",
        "xxd", "hexdump", "strings", "od", "shasum", "md5", "openssl"
    ]

    /// Commands that modify filesystem
    static let writeCommands: Set<String> = [
        "mkdir", "touch", "cp", "chmod", "chown", "chgrp", "ln",
        "tar", "zip", "unzip", "gzip", "gunzip", "bzip2", "xz",
        "curl", "wget", "tee", "dd", "install", "rsync", "ditto",
        "pbpaste", "npm", "yarn", "pip", "pip3", "brew", "git",
        "python", "python3", "ruby", "node", "perl"
    ]

    /// Commands that are destructive
    static let destructiveCommands: Set<String> = [
        "rm", "rmdir", "mv", "kill", "killall", "pkill",
        "launchctl unload", "launchctl remove"
    ]

    /// Commands that require elevated privileges - always blocked
    static let privilegedCommands: Set<String> = [
        "sudo", "su", "dscl", "security", "csrutil", "nvram",
        "bless", "diskutil eraseDisk", "diskutil partitionDisk",
        "systemsetup", "spctl", "fdesetup"
    ]

    /// Shell operators that ALWAYS require explicit approval
    /// These are legitimate shell features but should never be auto-approved
    /// via "Remember for Session" or "Allow All Once"
    static let operatorsRequiringApproval: [String] = [
        ";",     // Command chaining - could hide malicious commands
        "&&",    // Conditional execution
        "||",    // Conditional execution
        "|",     // Pipes - could chain to dangerous commands
        "`",     // Backtick command substitution
        "$(",    // Command substitution
        "${",    // Variable expansion (could be used for injection)
        ">",     // Output redirection (could overwrite files)
        ">>",    // Append redirection
        "<",     // Input redirection
        "<<",    // Here document
        "&"      // Background execution
    ]

    /// Operators that are BLOCKED entirely (cannot execute)
    /// These indicate definite injection attempts or security risks
    static let blockedPatterns: [String] = [
        "\0"     // Null bytes - definite injection attempt
    ]

    // MARK: - Classification

    /// Shell patterns that indicate the command intends to write to the filesystem
    /// When present, the command should bypass the read-only sandbox
    private static let writeIndicators: [String] = [
        ">",     // Output redirection (overwrite)
        ">>",    // Output redirection (append)
        "| tee", // Pipe to tee (writes to file)
    ]

    /// Classify a command by its risk level
    /// - Parameter command: The full command string
    /// - Returns: The risk level of the command
    static func classify(_ command: String) -> CommandRiskLevel {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .read }

        // Extract the executable (first word)
        let executable = extractExecutable(from: trimmed)

        // Check against known command lists in order of severity
        if privilegedCommands.contains(executable) {
            return .privileged
        }

        if destructiveCommands.contains(executable) {
            return .destructive
        }

        if writeCommands.contains(executable) {
            return .write
        }

        // Check for write indicators (output redirection, tee, etc.)
        // These mean the command intends to write to the filesystem
        // regardless of the executable being a "read" or "safe" command
        for indicator in writeIndicators {
            if trimmed.contains(indicator) {
                return .write
            }
        }

        if readCommands.contains(executable) {
            return .read
        }

        if safeCommands.contains(executable) {
            return .safe
        }

        // Default to read for unknown commands (safer than assuming safe)
        return .read
    }

    /// Extract the executable name from a command string
    /// - Parameter command: The full command string
    /// - Returns: The executable name (first component)
    static func extractExecutable(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle path prefixes (e.g., /usr/bin/ls -> ls)
        let firstWord = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed

        // Extract just the executable name from path
        if firstWord.contains("/") {
            return (firstWord as NSString).lastPathComponent
        }

        return firstWord
    }

    // MARK: - Validation

    /// Validate a command for execution
    /// Only blocks truly dangerous patterns (null bytes, privileged commands)
    /// Commands with operators are allowed but require explicit approval
    /// - Parameter command: The command to validate
    /// - Returns: Validation result with any issues found
    static func validate(_ command: String) -> ShellCommandValidation {
        var issues: [String] = []

        // Check for empty command
        if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Command is empty")
            return ShellCommandValidation(isValid: false, issues: issues)
        }

        // Check for blocked patterns (truly dangerous)
        for pattern in blockedPatterns {
            if command.contains(pattern) {
                issues.append("Command contains blocked pattern")
            }
        }

        // Check for privileged commands (always blocked)
        let executable = extractExecutable(from: command)
        if privilegedCommands.contains(executable) {
            issues.append("Command requires elevated privileges: \(executable)")
        }

        // Check for excessive length
        if command.count > 10000 {
            issues.append("Command is too long (max 10000 characters)")
        }

        return ShellCommandValidation(
            isValid: issues.isEmpty,
            issues: issues
        )
    }

    /// Check if a command requires explicit approval every time
    /// Commands with certain operators should NEVER be auto-approved
    /// via "Remember for Session" or "Allow All Once"
    /// - Parameter command: The command to check
    /// - Returns: true if command must always be explicitly approved
    static func requiresExplicitApproval(_ command: String) -> Bool {
        // Destructive commands always require explicit approval
        let executable = extractExecutable(from: command)
        if destructiveCommands.contains(executable) {
            return true
        }

        // Privileged commands always require explicit approval
        if privilegedCommands.contains(executable) {
            return true
        }

        // Commands with certain operators always require explicit approval
        for op in operatorsRequiringApproval {
            if command.contains(op) {
                return true
            }
        }

        return false
    }

    // MARK: - Pattern Extraction

    /// Extract an approval pattern from a command based on risk level
    /// - Parameters:
    ///   - command: The command that was approved
    ///   - riskLevel: The risk level of the command
    /// - Returns: A pattern string for session memory
    static func extractPattern(from command: String, riskLevel: CommandRiskLevel) -> String {
        let executable = extractExecutable(from: command)

        switch riskLevel {
        case .safe, .read:
            // Broad pattern for safe/read commands
            return "\(executable) *"
        case .write:
            // More specific pattern for write commands
            let parts = command.split(separator: " ", maxSplits: 2)
            if parts.count > 1 {
                let firstArg = String(parts[1])
                if firstArg.hasPrefix("-") {
                    return "\(executable) \(firstArg) *"
                }
            }
            return "\(executable) *"
        case .destructive, .privileged:
            // Exact match only for destructive/privileged
            return command
        }
    }

    /// Check if a command matches an approved pattern
    /// - Parameters:
    ///   - command: The command to check
    ///   - pattern: The pattern to match against
    /// - Returns: Whether the command matches the pattern
    static func commandMatches(_ command: String, pattern: String) -> Bool {
        // Exact match
        if command == pattern {
            return true
        }

        // Wildcard pattern (e.g., "ls *")
        if pattern.hasSuffix(" *") {
            let prefix = String(pattern.dropLast(2))
            let commandExecutable = extractExecutable(from: command)
            let patternExecutable = extractExecutable(from: prefix)
            return commandExecutable == patternExecutable
        }

        return false
    }
}

// MARK: - Validation Result

/// Result of shell command validation
struct ShellCommandValidation: Sendable {
    /// Whether the command is valid for execution
    let isValid: Bool

    /// List of validation issues found
    let issues: [String]

    /// Summary message for display
    var summary: String {
        if isValid {
            return "Command is valid"
        }
        return issues.joined(separator: "; ")
    }
}
