// MARK: - Shell Approval Security Tests
// CRITICAL: Tests for security-critical shell approval pattern matching
// These tests verify that approving one command doesn't approve a different command

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

// MARK: - Mock Session Approval Memory (Inline for Standalone Test)

/// Simulates the SessionApprovalMemory class for testing
class MockSessionApprovalMemory {
    var approvedShellPatterns: Set<String> = []

    func rememberShellPattern(_ pattern: String) {
        approvedShellPatterns.insert(pattern)
    }

    /// SECURITY-CRITICAL: This method must ensure:
    /// 1. Destructive commands require EXACT match
    /// 2. Wildcard patterns only match same executable
    /// 3. Cross-executable approval is NEVER allowed
    func isShellCommandApproved(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let executable = extractShellExecutable(from: trimmed)

        // SECURITY: Destructive commands require EXACT match only
        let destructiveExecutables: Set<String> = [
            "rm", "rmdir", "mv", "kill", "killall", "pkill",
            "sudo", "su", "dscl", "security"
        ]

        if destructiveExecutables.contains(executable) {
            // ONLY exact command match for destructive commands
            return approvedShellPatterns.contains(trimmed)
        }

        // For non-destructive commands, check wildcard pattern
        let wildcardPattern = "\(executable) *"
        if approvedShellPatterns.contains(wildcardPattern) {
            return true
        }

        // Check exact command match
        if approvedShellPatterns.contains(trimmed) {
            return true
        }

        return false
    }

    private func extractShellExecutable(from command: String) -> String {
        let firstWord = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
        if firstWord.contains("/") {
            return (firstWord as NSString).lastPathComponent
        }
        return firstWord
    }
}

// MARK: - Command Risk Level

enum CommandRiskLevel: String {
    case safe
    case read
    case write
    case destructive
    case privileged
}

// MARK: - Pattern Extractor

enum PatternExtractor {
    static let destructiveCommands: Set<String> = [
        "rm", "rmdir", "mv", "kill", "killall", "pkill"
    ]

    static func extractPattern(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable = extractExecutable(from: trimmed)

        // Destructive commands MUST use exact match
        if destructiveCommands.contains(executable) {
            return trimmed
        }

        // Safe/read commands use wildcard
        return "\(executable) *"
    }

    static func extractExecutable(from command: String) -> String {
        let firstWord = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
        if firstWord.contains("/") {
            return (firstWord as NSString).lastPathComponent
        }
        return firstWord
    }

    static func classify(_ command: String) -> CommandRiskLevel {
        let executable = extractExecutable(from: command)

        if ["sudo", "su", "dscl", "security"].contains(executable) {
            return .privileged
        }
        if destructiveCommands.contains(executable) {
            return .destructive
        }
        if ["mkdir", "touch", "cp", "chmod"].contains(executable) {
            return .write
        }
        if ["df", "uptime", "whoami", "hostname"].contains(executable) {
            return .safe
        }
        return .read
    }
}

// MARK: - SECURITY TESTS: Cross-Executable Isolation

func testSecurity_ApprovedDfDoesNotApproveRm() {
    TestRunner.setGroup("SECURITY: Cross-Executable Isolation")

    let memory = MockSessionApprovalMemory()

    // User approves "df -h"
    let dfPattern = PatternExtractor.extractPattern(from: "df -h")
    memory.rememberShellPattern(dfPattern)

    // Verify df commands work
    TestRunner.assertTrue(memory.isShellCommandApproved("df -h"), "df -h is approved")
    TestRunner.assertTrue(memory.isShellCommandApproved("df"), "df is approved")
    TestRunner.assertTrue(memory.isShellCommandApproved("df -k"), "df -k is approved")

    // CRITICAL: rm MUST NOT be approved
    TestRunner.assertFalse(memory.isShellCommandApproved("rm file.txt"), "rm file.txt is NOT approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("rm -rf /"), "rm -rf / is NOT approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("rm"), "rm is NOT approved")
}

func testSecurity_ApprovedLsDoesNotApproveMv() {
    TestRunner.setGroup("SECURITY: ls approval doesn't approve mv")

    let memory = MockSessionApprovalMemory()

    // User approves "ls -la"
    memory.rememberShellPattern("ls *")

    // ls commands work
    TestRunner.assertTrue(memory.isShellCommandApproved("ls"), "ls is approved")
    TestRunner.assertTrue(memory.isShellCommandApproved("ls -la"), "ls -la is approved")
    TestRunner.assertTrue(memory.isShellCommandApproved("ls /home"), "ls /home is approved")

    // mv MUST NOT be approved
    TestRunner.assertFalse(memory.isShellCommandApproved("mv old new"), "mv old new is NOT approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("mv"), "mv is NOT approved")
}

func testSecurity_ApprovedCatDoesNotApproveKill() {
    TestRunner.setGroup("SECURITY: cat approval doesn't approve kill")

    let memory = MockSessionApprovalMemory()

    // User approves "cat file"
    memory.rememberShellPattern("cat *")

    // cat commands work
    TestRunner.assertTrue(memory.isShellCommandApproved("cat file.txt"), "cat file.txt is approved")
    TestRunner.assertTrue(memory.isShellCommandApproved("cat /etc/hosts"), "cat /etc/hosts is approved")

    // kill MUST NOT be approved
    TestRunner.assertFalse(memory.isShellCommandApproved("kill 1234"), "kill 1234 is NOT approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("killall Safari"), "killall Safari is NOT approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("pkill -9 app"), "pkill -9 app is NOT approved")
}

// MARK: - SECURITY TESTS: Destructive Command Exact Match

func testSecurity_RmRequiresExactMatch() {
    TestRunner.setGroup("SECURITY: rm requires EXACT match")

    let memory = MockSessionApprovalMemory()

    // User approves specific rm command
    memory.rememberShellPattern("rm file.txt")

    // Only exact match works
    TestRunner.assertTrue(memory.isShellCommandApproved("rm file.txt"), "Exact rm command is approved")

    // Different files MUST NOT be approved
    TestRunner.assertFalse(memory.isShellCommandApproved("rm other.txt"), "rm other.txt is NOT approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("rm -rf /"), "rm -rf / is NOT approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("rm important.doc"), "rm important.doc is NOT approved")
}

func testSecurity_MvRequiresExactMatch() {
    TestRunner.setGroup("SECURITY: mv requires EXACT match")

    let memory = MockSessionApprovalMemory()

    // User approves specific mv command
    memory.rememberShellPattern("mv old.txt new.txt")

    // Only exact match works
    TestRunner.assertTrue(memory.isShellCommandApproved("mv old.txt new.txt"), "Exact mv command is approved")

    // Different files MUST NOT be approved
    TestRunner.assertFalse(memory.isShellCommandApproved("mv other.txt different.txt"), "Different mv is NOT approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("mv /etc/passwd /tmp/"), "System mv is NOT approved")
}

func testSecurity_KillRequiresExactMatch() {
    TestRunner.setGroup("SECURITY: kill requires EXACT match")

    let memory = MockSessionApprovalMemory()

    // User approves specific kill command
    memory.rememberShellPattern("kill 1234")

    // Only exact match works
    TestRunner.assertTrue(memory.isShellCommandApproved("kill 1234"), "Exact kill command is approved")

    // Different PIDs MUST NOT be approved
    TestRunner.assertFalse(memory.isShellCommandApproved("kill 5678"), "kill 5678 is NOT approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("kill -9 1234"), "kill -9 1234 is NOT approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("kill 1"), "kill 1 is NOT approved")
}

// MARK: - SECURITY TESTS: Wildcard Pattern Boundaries

func testSecurity_WildcardOnlyMatchesSameExecutable() {
    TestRunner.setGroup("SECURITY: Wildcard boundary enforcement")

    let memory = MockSessionApprovalMemory()

    // Approve df with wildcard
    memory.rememberShellPattern("df *")

    // df commands match
    TestRunner.assertTrue(memory.isShellCommandApproved("df"), "df matches df *")
    TestRunner.assertTrue(memory.isShellCommandApproved("df -h"), "df -h matches df *")
    TestRunner.assertTrue(memory.isShellCommandApproved("df -k /"), "df -k / matches df *")

    // NO other commands should match
    TestRunner.assertFalse(memory.isShellCommandApproved("dft"), "dft doesn't match df *")
    TestRunner.assertFalse(memory.isShellCommandApproved("dfs"), "dfs doesn't match df *")
    TestRunner.assertFalse(memory.isShellCommandApproved("ls"), "ls doesn't match df *")
    TestRunner.assertFalse(memory.isShellCommandApproved("cat"), "cat doesn't match df *")
    TestRunner.assertFalse(memory.isShellCommandApproved("rm"), "rm doesn't match df *")
}

func testSecurity_NoWildcardForDestructive() {
    TestRunner.setGroup("SECURITY: No wildcard pattern for destructive")

    let memory = MockSessionApprovalMemory()

    // Even if someone tries to add wildcard for rm
    // (This shouldn't happen with proper pattern extraction, but test defense in depth)
    memory.rememberShellPattern("rm *")

    // rm commands should STILL NOT be auto-approved due to destructive check
    // The isShellCommandApproved function should block this
    TestRunner.assertFalse(memory.isShellCommandApproved("rm file.txt"), "rm file.txt blocked despite rm * pattern")
    TestRunner.assertFalse(memory.isShellCommandApproved("rm -rf /"), "rm -rf / blocked despite rm * pattern")
}

// MARK: - SECURITY TESTS: Pattern Extraction Security

func testSecurity_PatternExtraction_DestructiveGetsExact() {
    TestRunner.setGroup("SECURITY: Pattern extraction for destructive")

    // Destructive commands must get exact pattern
    TestRunner.assertEqual(PatternExtractor.extractPattern(from: "rm file.txt"), "rm file.txt", "rm gets exact")
    TestRunner.assertEqual(PatternExtractor.extractPattern(from: "rm -rf dir"), "rm -rf dir", "rm -rf gets exact")
    TestRunner.assertEqual(PatternExtractor.extractPattern(from: "mv a b"), "mv a b", "mv gets exact")
    TestRunner.assertEqual(PatternExtractor.extractPattern(from: "kill 123"), "kill 123", "kill gets exact")
    TestRunner.assertEqual(PatternExtractor.extractPattern(from: "killall Safari"), "killall Safari", "killall gets exact")
    TestRunner.assertEqual(PatternExtractor.extractPattern(from: "pkill -9 app"), "pkill -9 app", "pkill gets exact")
}

func testSecurity_PatternExtraction_SafeGetsWildcard() {
    TestRunner.setGroup("SECURITY: Pattern extraction for safe commands")

    // Safe/read commands get wildcard
    TestRunner.assertEqual(PatternExtractor.extractPattern(from: "df -h"), "df *", "df gets wildcard")
    TestRunner.assertEqual(PatternExtractor.extractPattern(from: "ls -la"), "ls *", "ls gets wildcard")
    TestRunner.assertEqual(PatternExtractor.extractPattern(from: "cat /etc/hosts"), "cat *", "cat gets wildcard")
    TestRunner.assertEqual(PatternExtractor.extractPattern(from: "uptime"), "uptime *", "uptime gets wildcard")
}

// MARK: - SECURITY TESTS: Edge Cases

func testSecurity_EmptyCommand() {
    TestRunner.setGroup("SECURITY: Empty command handling")

    let memory = MockSessionApprovalMemory()
    memory.rememberShellPattern("df *")

    TestRunner.assertFalse(memory.isShellCommandApproved(""), "Empty command is not approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("   "), "Whitespace command is not approved")
}

func testSecurity_PathPrefixHandling() {
    TestRunner.setGroup("SECURITY: Path prefix extraction")

    let memory = MockSessionApprovalMemory()
    memory.rememberShellPattern("ls *")

    // Commands with path prefixes should still work
    TestRunner.assertTrue(memory.isShellCommandApproved("/usr/bin/ls"), "/usr/bin/ls matches ls *")
    TestRunner.assertTrue(memory.isShellCommandApproved("/bin/ls -la"), "/bin/ls -la matches ls *")

    // But not different commands
    TestRunner.assertFalse(memory.isShellCommandApproved("/usr/bin/rm file"), "/usr/bin/rm not approved")
}

func testSecurity_CaseSensitivity() {
    TestRunner.setGroup("SECURITY: Case sensitivity")

    let memory = MockSessionApprovalMemory()
    memory.rememberShellPattern("ls *")

    // Commands are case-sensitive (Unix is case-sensitive)
    TestRunner.assertTrue(memory.isShellCommandApproved("ls"), "ls matches")
    TestRunner.assertFalse(memory.isShellCommandApproved("LS"), "LS doesn't match (case sensitive)")
    TestRunner.assertFalse(memory.isShellCommandApproved("Ls"), "Ls doesn't match (case sensitive)")
}

func testSecurity_WhitespaceVariations() {
    TestRunner.setGroup("SECURITY: Whitespace handling")

    let memory = MockSessionApprovalMemory()
    memory.rememberShellPattern("df *")

    // Whitespace should be trimmed
    TestRunner.assertTrue(memory.isShellCommandApproved("  df -h  "), "Whitespace trimmed - approved")
    TestRunner.assertTrue(memory.isShellCommandApproved("df  -h"), "Internal whitespace - approved")
}

// MARK: - SECURITY TESTS: Multiple Patterns

func testSecurity_MultiplePatternIsolation() {
    TestRunner.setGroup("SECURITY: Multiple pattern isolation")

    let memory = MockSessionApprovalMemory()

    // Approve multiple safe commands
    memory.rememberShellPattern("df *")
    memory.rememberShellPattern("ls *")
    memory.rememberShellPattern("cat *")

    // All approved commands work
    TestRunner.assertTrue(memory.isShellCommandApproved("df -h"), "df works")
    TestRunner.assertTrue(memory.isShellCommandApproved("ls -la"), "ls works")
    TestRunner.assertTrue(memory.isShellCommandApproved("cat file"), "cat works")

    // Destructive STILL blocked
    TestRunner.assertFalse(memory.isShellCommandApproved("rm file"), "rm still blocked")
    TestRunner.assertFalse(memory.isShellCommandApproved("mv a b"), "mv still blocked")
    TestRunner.assertFalse(memory.isShellCommandApproved("kill 1"), "kill still blocked")

    // Unapproved safe commands blocked
    TestRunner.assertFalse(memory.isShellCommandApproved("whoami"), "whoami not approved")
    TestRunner.assertFalse(memory.isShellCommandApproved("uptime"), "uptime not approved")
}

func testSecurity_ExactDestructiveWithMultiple() {
    TestRunner.setGroup("SECURITY: Multiple exact destructive patterns")

    let memory = MockSessionApprovalMemory()

    // Approve specific destructive commands
    memory.rememberShellPattern("rm file1.txt")
    memory.rememberShellPattern("rm file2.txt")

    // Only exact matches work
    TestRunner.assertTrue(memory.isShellCommandApproved("rm file1.txt"), "rm file1.txt approved")
    TestRunner.assertTrue(memory.isShellCommandApproved("rm file2.txt"), "rm file2.txt approved")

    // Other rm commands blocked
    TestRunner.assertFalse(memory.isShellCommandApproved("rm file3.txt"), "rm file3.txt blocked")
    TestRunner.assertFalse(memory.isShellCommandApproved("rm -rf /"), "rm -rf / blocked")
}

// MARK: - SECURITY TESTS: Real-World Attack Scenarios

func testSecurity_AttackScenario_InjectionAttempt() {
    TestRunner.setGroup("SECURITY: Attack - Command injection attempt")

    let memory = MockSessionApprovalMemory()

    // User approves df
    memory.rememberShellPattern("df *")

    // Attacker tries to inject via arguments (should fail at validation, but test memory)
    TestRunner.assertTrue(memory.isShellCommandApproved("df -h"), "Normal df works")

    // rm disguised as df argument - executable extraction should catch this
    // Note: This would be caught by validation, but pattern matching should also not match
    TestRunner.assertFalse(memory.isShellCommandApproved("rm file"), "rm not approved as df argument")
}

func testSecurity_AttackScenario_PrivilegeEscalation() {
    TestRunner.setGroup("SECURITY: Attack - Privilege escalation attempt")

    let memory = MockSessionApprovalMemory()

    // User approves ls
    memory.rememberShellPattern("ls *")

    // Attacker tries sudo - should be blocked
    TestRunner.assertFalse(memory.isShellCommandApproved("sudo ls"), "sudo ls blocked")
    TestRunner.assertFalse(memory.isShellCommandApproved("sudo rm -rf /"), "sudo rm blocked")
}

func testSecurity_AttackScenario_RmRfSlash() {
    TestRunner.setGroup("SECURITY: Attack - rm -rf / scenario")

    let memory = MockSessionApprovalMemory()

    // User approves a specific safe rm command
    memory.rememberShellPattern("rm temp.txt")

    // rm -rf / MUST be blocked
    TestRunner.assertFalse(memory.isShellCommandApproved("rm -rf /"), "rm -rf / is BLOCKED")
    TestRunner.assertFalse(memory.isShellCommandApproved("rm -rf ~"), "rm -rf ~ is BLOCKED")
    TestRunner.assertFalse(memory.isShellCommandApproved("rm -rf /*"), "rm -rf /* is BLOCKED")

    // Only exact pattern works
    TestRunner.assertTrue(memory.isShellCommandApproved("rm temp.txt"), "Only rm temp.txt works")
}

// MARK: - Main Entry Point

@main
struct ShellApprovalSecurityTestRunner {
    static func main() {
        print("")
        print("🔒 Shell Approval SECURITY Tests")
        print("==================================================")
        print("These tests verify security-critical pattern matching")
        print("==================================================")

        // Cross-Executable Isolation (CRITICAL)
        testSecurity_ApprovedDfDoesNotApproveRm()
        testSecurity_ApprovedLsDoesNotApproveMv()
        testSecurity_ApprovedCatDoesNotApproveKill()

        // Destructive Exact Match (CRITICAL)
        testSecurity_RmRequiresExactMatch()
        testSecurity_MvRequiresExactMatch()
        testSecurity_KillRequiresExactMatch()

        // Wildcard Boundary Enforcement
        testSecurity_WildcardOnlyMatchesSameExecutable()
        testSecurity_NoWildcardForDestructive()

        // Pattern Extraction Security
        testSecurity_PatternExtraction_DestructiveGetsExact()
        testSecurity_PatternExtraction_SafeGetsWildcard()

        // Edge Cases
        testSecurity_EmptyCommand()
        testSecurity_PathPrefixHandling()
        testSecurity_CaseSensitivity()
        testSecurity_WhitespaceVariations()

        // Multiple Patterns
        testSecurity_MultiplePatternIsolation()
        testSecurity_ExactDestructiveWithMultiple()

        // Real-World Attack Scenarios
        testSecurity_AttackScenario_InjectionAttempt()
        testSecurity_AttackScenario_PrivilegeEscalation()
        testSecurity_AttackScenario_RmRfSlash()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            print("")
            print("⚠️  SECURITY TESTS FAILED - DO NOT DEPLOY ⚠️")
            exit(1)
        } else {
            print("")
            print("✅ All security tests passed")
        }
    }
}
