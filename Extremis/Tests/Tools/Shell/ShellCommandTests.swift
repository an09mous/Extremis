// MARK: - Shell Command Unit Tests
// Tests for ShellCommand risk classification, validation, and pattern matching

import Foundation

// MARK: - Test Runner Framework

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []
    static var currentGroup = ""

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
        currentGroup = ""
    }

    static func setGroup(_ name: String) {
        currentGroup = name
        print("")
        print("📦 \(name)")
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
        assertTrue(!condition, testName)
    }

    static func printSummary() {
        print("")
        print("==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("")
            print("Failed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("==================================================")
    }
}

// MARK: - Command Risk Level (Inline for Standalone Test)

enum CommandRiskLevel: String, Codable, CaseIterable, Sendable {
    case safe
    case read
    case write
    case destructive
    case privileged

    var shouldSandbox: Bool {
        switch self {
        case .safe, .read:
            return true
        case .write, .destructive, .privileged:
            return false
        }
    }

    var isAllowed: Bool {
        self != .privileged
    }
}

// MARK: - Shell Command Classifier (Inline for Standalone Test)

enum ShellCommandClassifier {

    static let safeCommands: Set<String> = [
        "sw_vers", "uname", "hostname", "whoami", "uptime", "df", "du",
        "ps", "top", "launchctl", "ifconfig", "networksetup", "scutil",
        "diskutil", "pmset", "caffeinate", "defaults", "system_profiler",
        "date", "cal", "env", "printenv", "which", "whereis", "type",
        "id", "groups", "arch", "sysctl", "vm_stat", "iostat", "nettop",
        "mdfind", "mdls", "xcode-select", "xcrun", "swift", "swiftc"
    ]

    static let readCommands: Set<String> = [
        "cat", "head", "tail", "less", "more", "ls", "find", "grep",
        "awk", "sed", "wc", "sort", "uniq", "diff", "file", "stat",
        "xxd", "hexdump", "strings", "od", "shasum", "md5", "openssl"
    ]

    static let writeCommands: Set<String> = [
        "mkdir", "touch", "cp", "chmod", "chown", "chgrp", "ln",
        "tar", "zip", "unzip", "gzip", "gunzip", "bzip2", "xz"
    ]

    static let destructiveCommands: Set<String> = [
        "rm", "rmdir", "mv", "kill", "killall", "pkill",
        "launchctl unload", "launchctl remove"
    ]

    static let privilegedCommands: Set<String> = [
        "sudo", "su", "dscl", "security", "csrutil", "nvram",
        "bless", "diskutil eraseDisk", "diskutil partitionDisk",
        "systemsetup", "spctl", "fdesetup"
    ]

    static let operatorsRequiringApproval: [String] = [
        ";", "&&", "||", "|", "`", "$(", "${", ">", ">>", "<", "<<", "&"
    ]

    static let blockedPatterns: [String] = [
        "\0"
    ]

    static func classify(_ command: String) -> CommandRiskLevel {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .read }

        let executable = extractExecutable(from: trimmed)

        if privilegedCommands.contains(executable) {
            return .privileged
        }

        if destructiveCommands.contains(executable) {
            return .destructive
        }

        if writeCommands.contains(executable) {
            return .write
        }

        if readCommands.contains(executable) {
            return .read
        }

        if safeCommands.contains(executable) {
            return .safe
        }

        return .read
    }

    static func extractExecutable(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed

        if firstWord.contains("/") {
            return (firstWord as NSString).lastPathComponent
        }

        return firstWord
    }

    static func validate(_ command: String) -> ShellCommandValidation {
        var issues: [String] = []

        if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Command is empty")
            return ShellCommandValidation(isValid: false, issues: issues)
        }

        // Only check for blocked patterns (truly dangerous)
        for pattern in blockedPatterns {
            if command.contains(pattern) {
                issues.append("Command contains blocked pattern")
            }
        }

        let executable = extractExecutable(from: command)
        if privilegedCommands.contains(executable) {
            issues.append("Command requires elevated privileges: \(executable)")
        }

        if command.count > 10000 {
            issues.append("Command is too long (max 10000 characters)")
        }

        return ShellCommandValidation(
            isValid: issues.isEmpty,
            issues: issues
        )
    }

    static func requiresExplicitApproval(_ command: String) -> Bool {
        let executable = extractExecutable(from: command)

        // Destructive commands always require explicit approval
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

    static func extractPattern(from command: String, riskLevel: CommandRiskLevel) -> String {
        let executable = extractExecutable(from: command)

        switch riskLevel {
        case .safe, .read:
            return "\(executable) *"
        case .write:
            let parts = command.split(separator: " ", maxSplits: 2)
            if parts.count > 1 {
                let firstArg = String(parts[1])
                if firstArg.hasPrefix("-") {
                    return "\(executable) \(firstArg) *"
                }
            }
            return "\(executable) *"
        case .destructive, .privileged:
            return command
        }
    }

    static func commandMatches(_ command: String, pattern: String) -> Bool {
        if command == pattern {
            return true
        }

        if pattern.hasSuffix(" *") {
            let prefix = String(pattern.dropLast(2))
            let commandExecutable = extractExecutable(from: command)
            let patternExecutable = extractExecutable(from: prefix)
            return commandExecutable == patternExecutable
        }

        return false
    }
}

struct ShellCommandValidation: Sendable {
    let isValid: Bool
    let issues: [String]

    var summary: String {
        if isValid {
            return "Command is valid"
        }
        return issues.joined(separator: "; ")
    }
}

// MARK: - Risk Classification Tests

func testClassify_SafeCommands() {
    TestRunner.setGroup("Risk Classification - Safe Commands")

    TestRunner.assertEqual(ShellCommandClassifier.classify("df -h"), .safe, "df is safe")
    TestRunner.assertEqual(ShellCommandClassifier.classify("uptime"), .safe, "uptime is safe")
    TestRunner.assertEqual(ShellCommandClassifier.classify("sw_vers"), .safe, "sw_vers is safe")
    TestRunner.assertEqual(ShellCommandClassifier.classify("hostname"), .safe, "hostname is safe")
    TestRunner.assertEqual(ShellCommandClassifier.classify("whoami"), .safe, "whoami is safe")
    TestRunner.assertEqual(ShellCommandClassifier.classify("date"), .safe, "date is safe")
    TestRunner.assertEqual(ShellCommandClassifier.classify("env"), .safe, "env is safe")
    TestRunner.assertEqual(ShellCommandClassifier.classify("ps aux"), .safe, "ps is safe")
}

func testClassify_ReadCommands() {
    TestRunner.setGroup("Risk Classification - Read Commands")

    TestRunner.assertEqual(ShellCommandClassifier.classify("ls -la"), .read, "ls is read")
    TestRunner.assertEqual(ShellCommandClassifier.classify("cat /etc/hosts"), .read, "cat is read")
    TestRunner.assertEqual(ShellCommandClassifier.classify("head -n 10 file.txt"), .read, "head is read")
    TestRunner.assertEqual(ShellCommandClassifier.classify("tail -f log.txt"), .read, "tail is read")
    TestRunner.assertEqual(ShellCommandClassifier.classify("grep pattern file"), .read, "grep is read")
    TestRunner.assertEqual(ShellCommandClassifier.classify("find . -name '*.txt'"), .read, "find is read")
}

func testClassify_WriteCommands() {
    TestRunner.setGroup("Risk Classification - Write Commands")

    TestRunner.assertEqual(ShellCommandClassifier.classify("mkdir test"), .write, "mkdir is write")
    TestRunner.assertEqual(ShellCommandClassifier.classify("touch file.txt"), .write, "touch is write")
    TestRunner.assertEqual(ShellCommandClassifier.classify("cp src dst"), .write, "cp is write")
    TestRunner.assertEqual(ShellCommandClassifier.classify("chmod 755 file"), .write, "chmod is write")
    TestRunner.assertEqual(ShellCommandClassifier.classify("tar -czf archive.tar.gz dir"), .write, "tar is write")
}

func testClassify_DestructiveCommands() {
    TestRunner.setGroup("Risk Classification - Destructive Commands")

    TestRunner.assertEqual(ShellCommandClassifier.classify("rm file.txt"), .destructive, "rm is destructive")
    TestRunner.assertEqual(ShellCommandClassifier.classify("rm -rf directory"), .destructive, "rm -rf is destructive")
    TestRunner.assertEqual(ShellCommandClassifier.classify("rmdir empty_dir"), .destructive, "rmdir is destructive")
    TestRunner.assertEqual(ShellCommandClassifier.classify("mv old new"), .destructive, "mv is destructive")
    TestRunner.assertEqual(ShellCommandClassifier.classify("kill -9 1234"), .destructive, "kill is destructive")
    TestRunner.assertEqual(ShellCommandClassifier.classify("killall Safari"), .destructive, "killall is destructive")
}

func testClassify_PrivilegedCommands() {
    TestRunner.setGroup("Risk Classification - Privileged Commands")

    TestRunner.assertEqual(ShellCommandClassifier.classify("sudo ls"), .privileged, "sudo is privileged")
    TestRunner.assertEqual(ShellCommandClassifier.classify("su -"), .privileged, "su is privileged")
    TestRunner.assertEqual(ShellCommandClassifier.classify("dscl . -list /Users"), .privileged, "dscl is privileged")
}

func testClassify_UnknownDefaultsToRead() {
    TestRunner.setGroup("Risk Classification - Unknown Commands")

    TestRunner.assertEqual(ShellCommandClassifier.classify("unknowncommand arg1 arg2"), .read, "Unknown defaults to read")
    TestRunner.assertEqual(ShellCommandClassifier.classify("mycustomtool"), .read, "Custom tool defaults to read")
}

func testClassify_PathPrefixes() {
    TestRunner.setGroup("Risk Classification - Path Prefixes")

    TestRunner.assertEqual(ShellCommandClassifier.classify("/usr/bin/ls"), .read, "/usr/bin/ls is read")
    TestRunner.assertEqual(ShellCommandClassifier.classify("/bin/cat file"), .read, "/bin/cat is read")
    TestRunner.assertEqual(ShellCommandClassifier.classify("/usr/bin/env"), .safe, "/usr/bin/env is safe")
}

func testClassify_EmptyCommand() {
    TestRunner.setGroup("Risk Classification - Empty Command")

    TestRunner.assertEqual(ShellCommandClassifier.classify(""), .read, "Empty defaults to read")
    TestRunner.assertEqual(ShellCommandClassifier.classify("   "), .read, "Whitespace defaults to read")
}

// MARK: - Risk Level Properties Tests

func testRiskLevel_ShouldSandbox() {
    TestRunner.setGroup("Risk Level - Should Sandbox")

    TestRunner.assertTrue(CommandRiskLevel.safe.shouldSandbox, "Safe commands should sandbox")
    TestRunner.assertTrue(CommandRiskLevel.read.shouldSandbox, "Read commands should sandbox")
    TestRunner.assertFalse(CommandRiskLevel.write.shouldSandbox, "Write commands should not sandbox")
    TestRunner.assertFalse(CommandRiskLevel.destructive.shouldSandbox, "Destructive commands should not sandbox")
    TestRunner.assertFalse(CommandRiskLevel.privileged.shouldSandbox, "Privileged commands should not sandbox")
}

func testRiskLevel_IsAllowed() {
    TestRunner.setGroup("Risk Level - Is Allowed")

    TestRunner.assertTrue(CommandRiskLevel.safe.isAllowed, "Safe commands are allowed")
    TestRunner.assertTrue(CommandRiskLevel.read.isAllowed, "Read commands are allowed")
    TestRunner.assertTrue(CommandRiskLevel.write.isAllowed, "Write commands are allowed")
    TestRunner.assertTrue(CommandRiskLevel.destructive.isAllowed, "Destructive commands are allowed")
    TestRunner.assertFalse(CommandRiskLevel.privileged.isAllowed, "Privileged commands are NOT allowed")
}

// MARK: - Validation Tests

func testValidation_ValidCommands() {
    TestRunner.setGroup("Validation - Valid Commands")

    let result1 = ShellCommandClassifier.validate("ls -la")
    TestRunner.assertTrue(result1.isValid, "ls -la is valid")

    let result2 = ShellCommandClassifier.validate("df -h")
    TestRunner.assertTrue(result2.isValid, "df -h is valid")

    let result3 = ShellCommandClassifier.validate("cat /etc/hosts")
    TestRunner.assertTrue(result3.isValid, "cat /etc/hosts is valid")
}

func testValidation_EmptyCommand() {
    TestRunner.setGroup("Validation - Empty Command")

    let result = ShellCommandClassifier.validate("")
    TestRunner.assertFalse(result.isValid, "Empty command is invalid")
    TestRunner.assertTrue(result.issues.contains("Command is empty"), "Has empty command issue")
}

func testValidation_OperatorsAreValid() {
    TestRunner.setGroup("Validation - Operators Are Valid (But Require Approval)")

    // Operators are now valid for execution - they just require explicit approval
    let result1 = ShellCommandClassifier.validate("ls; rm -rf /")
    TestRunner.assertTrue(result1.isValid, "Command with ; is valid (but requires approval)")

    let result2 = ShellCommandClassifier.validate("ls && rm -rf /")
    TestRunner.assertTrue(result2.isValid, "Command with && is valid (but requires approval)")

    let result3 = ShellCommandClassifier.validate("ls | grep foo")
    TestRunner.assertTrue(result3.isValid, "Command with | is valid (but requires approval)")

    let result4 = ShellCommandClassifier.validate("echo $(cat /etc/passwd)")
    TestRunner.assertTrue(result4.isValid, "Command with $() is valid (but requires approval)")

    let result5 = ShellCommandClassifier.validate("cat file > output")
    TestRunner.assertTrue(result5.isValid, "Command with > is valid (but requires approval)")
}

func testRequiresExplicitApproval_Operators() {
    TestRunner.setGroup("Requires Explicit Approval - Operators")

    // Commands with operators always require explicit approval
    TestRunner.assertTrue(
        ShellCommandClassifier.requiresExplicitApproval("ls; rm -rf /"),
        "Command with ; requires explicit approval"
    )
    TestRunner.assertTrue(
        ShellCommandClassifier.requiresExplicitApproval("ls && rm -rf /"),
        "Command with && requires explicit approval"
    )
    TestRunner.assertTrue(
        ShellCommandClassifier.requiresExplicitApproval("ls | grep foo"),
        "Command with | requires explicit approval"
    )
    TestRunner.assertTrue(
        ShellCommandClassifier.requiresExplicitApproval("echo $(cat /etc/passwd)"),
        "Command with $() requires explicit approval"
    )
    TestRunner.assertTrue(
        ShellCommandClassifier.requiresExplicitApproval("cat file > output"),
        "Command with > requires explicit approval"
    )
}

func testRequiresExplicitApproval_DestructiveCommands() {
    TestRunner.setGroup("Requires Explicit Approval - Destructive Commands")

    // Destructive commands always require explicit approval
    TestRunner.assertTrue(
        ShellCommandClassifier.requiresExplicitApproval("rm file.txt"),
        "rm requires explicit approval"
    )
    TestRunner.assertTrue(
        ShellCommandClassifier.requiresExplicitApproval("rmdir folder"),
        "rmdir requires explicit approval"
    )
    TestRunner.assertTrue(
        ShellCommandClassifier.requiresExplicitApproval("mv file.txt dest"),
        "mv requires explicit approval"
    )
    TestRunner.assertTrue(
        ShellCommandClassifier.requiresExplicitApproval("kill 1234"),
        "kill requires explicit approval"
    )
}

func testRequiresExplicitApproval_SafeCommands() {
    TestRunner.setGroup("Requires Explicit Approval - Safe Commands")

    // Safe commands without operators do NOT require explicit approval
    TestRunner.assertFalse(
        ShellCommandClassifier.requiresExplicitApproval("ls -la"),
        "ls does NOT require explicit approval"
    )
    TestRunner.assertFalse(
        ShellCommandClassifier.requiresExplicitApproval("df -h"),
        "df does NOT require explicit approval"
    )
    TestRunner.assertFalse(
        ShellCommandClassifier.requiresExplicitApproval("cat /etc/hosts"),
        "cat does NOT require explicit approval"
    )
    TestRunner.assertFalse(
        ShellCommandClassifier.requiresExplicitApproval("uptime"),
        "uptime does NOT require explicit approval"
    )
}

func testValidation_PrivilegedCommandsFlag() {
    TestRunner.setGroup("Validation - Privileged Commands Flag")

    let result = ShellCommandClassifier.validate("sudo ls")
    TestRunner.assertFalse(result.isValid, "sudo command is flagged")
    TestRunner.assertTrue(result.issues.contains { $0.contains("elevated privileges") }, "Has privilege issue")
}

func testValidation_TooLongCommand() {
    TestRunner.setGroup("Validation - Too Long Command")

    let longCommand = String(repeating: "a", count: 10001)
    let result = ShellCommandClassifier.validate(longCommand)
    TestRunner.assertFalse(result.isValid, "Too long command is invalid")
    TestRunner.assertTrue(result.issues.contains { $0.contains("too long") }, "Has length issue")
}

// MARK: - Executable Extraction Tests

func testExtractExecutable_Simple() {
    TestRunner.setGroup("Extract Executable - Simple")

    TestRunner.assertEqual(ShellCommandClassifier.extractExecutable(from: "ls"), "ls", "Simple command")
    TestRunner.assertEqual(ShellCommandClassifier.extractExecutable(from: "ls -la"), "ls", "Command with args")
    TestRunner.assertEqual(ShellCommandClassifier.extractExecutable(from: "df -h"), "df", "df command")
}

func testExtractExecutable_WithPath() {
    TestRunner.setGroup("Extract Executable - With Path")

    TestRunner.assertEqual(ShellCommandClassifier.extractExecutable(from: "/usr/bin/ls"), "ls", "Full path")
    TestRunner.assertEqual(ShellCommandClassifier.extractExecutable(from: "/bin/cat file"), "cat", "Path with args")
    TestRunner.assertEqual(ShellCommandClassifier.extractExecutable(from: "./script.sh"), "script.sh", "Relative path")
}

func testExtractExecutable_Whitespace() {
    TestRunner.setGroup("Extract Executable - Whitespace")

    TestRunner.assertEqual(ShellCommandClassifier.extractExecutable(from: "  ls -la  "), "ls", "Leading/trailing whitespace")
}

// MARK: - Pattern Tests

func testPatternExtraction_SafeCommands() {
    TestRunner.setGroup("Pattern Extraction - Safe Commands")

    let pattern1 = ShellCommandClassifier.extractPattern(from: "df -h", riskLevel: .safe)
    TestRunner.assertEqual(pattern1, "df *", "Safe command gets wildcard pattern")

    let pattern2 = ShellCommandClassifier.extractPattern(from: "uptime", riskLevel: .safe)
    TestRunner.assertEqual(pattern2, "uptime *", "Safe command without args gets wildcard pattern")
}

func testPatternExtraction_ReadCommands() {
    TestRunner.setGroup("Pattern Extraction - Read Commands")

    let pattern1 = ShellCommandClassifier.extractPattern(from: "ls -la /home", riskLevel: .read)
    TestRunner.assertEqual(pattern1, "ls *", "Read command gets wildcard pattern")

    let pattern2 = ShellCommandClassifier.extractPattern(from: "cat /etc/hosts", riskLevel: .read)
    TestRunner.assertEqual(pattern2, "cat *", "cat command gets wildcard pattern")
}

func testPatternExtraction_WriteCommands() {
    TestRunner.setGroup("Pattern Extraction - Write Commands")

    let pattern1 = ShellCommandClassifier.extractPattern(from: "mkdir -p dir/subdir", riskLevel: .write)
    TestRunner.assertEqual(pattern1, "mkdir -p *", "Write command with flag gets flag-specific pattern")

    let pattern2 = ShellCommandClassifier.extractPattern(from: "mkdir newdir", riskLevel: .write)
    TestRunner.assertEqual(pattern2, "mkdir *", "Write command without flag gets wildcard pattern")
}

func testPatternExtraction_DestructiveCommands() {
    TestRunner.setGroup("Pattern Extraction - Destructive Commands")

    let pattern1 = ShellCommandClassifier.extractPattern(from: "rm file.txt", riskLevel: .destructive)
    TestRunner.assertEqual(pattern1, "rm file.txt", "Destructive command gets exact match")

    let pattern2 = ShellCommandClassifier.extractPattern(from: "rm -rf directory", riskLevel: .destructive)
    TestRunner.assertEqual(pattern2, "rm -rf directory", "Destructive command with flags gets exact match")
}

func testPatternMatching_Wildcard() {
    TestRunner.setGroup("Pattern Matching - Wildcard")

    TestRunner.assertTrue(ShellCommandClassifier.commandMatches("df -h", pattern: "df *"), "df -h matches df *")
    TestRunner.assertTrue(ShellCommandClassifier.commandMatches("df", pattern: "df *"), "df matches df *")
    TestRunner.assertTrue(ShellCommandClassifier.commandMatches("ls -la /home/user", pattern: "ls *"), "ls with path matches ls *")
    TestRunner.assertFalse(ShellCommandClassifier.commandMatches("cat file", pattern: "ls *"), "cat does not match ls *")
}

func testPatternMatching_Exact() {
    TestRunner.setGroup("Pattern Matching - Exact")

    TestRunner.assertTrue(ShellCommandClassifier.commandMatches("rm file.txt", pattern: "rm file.txt"), "Exact match works")
    TestRunner.assertFalse(ShellCommandClassifier.commandMatches("rm other.txt", pattern: "rm file.txt"), "Different file doesn't match")
}

// MARK: - Main Entry Point

@main
struct ShellCommandTestRunner {
    static func main() {
        print("")
        print("🧪 Shell Command Tests")
        print("==================================================")

        // Risk Classification Tests
        testClassify_SafeCommands()
        testClassify_ReadCommands()
        testClassify_WriteCommands()
        testClassify_DestructiveCommands()
        testClassify_PrivilegedCommands()
        testClassify_UnknownDefaultsToRead()
        testClassify_PathPrefixes()
        testClassify_EmptyCommand()

        // Risk Level Properties
        testRiskLevel_ShouldSandbox()
        testRiskLevel_IsAllowed()

        // Validation Tests
        testValidation_ValidCommands()
        testValidation_EmptyCommand()
        testValidation_OperatorsAreValid()
        testValidation_PrivilegedCommandsFlag()
        testValidation_TooLongCommand()

        // Explicit Approval Tests
        testRequiresExplicitApproval_Operators()
        testRequiresExplicitApproval_DestructiveCommands()
        testRequiresExplicitApproval_SafeCommands()

        // Executable Extraction Tests
        testExtractExecutable_Simple()
        testExtractExecutable_WithPath()
        testExtractExecutable_Whitespace()

        // Pattern Tests
        testPatternExtraction_SafeCommands()
        testPatternExtraction_ReadCommands()
        testPatternExtraction_WriteCommands()
        testPatternExtraction_DestructiveCommands()
        testPatternMatching_Wildcard()
        testPatternMatching_Exact()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
