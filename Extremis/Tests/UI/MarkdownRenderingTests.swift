// MARK: - Markdown Rendering Tests
// Tests for markdown helper functions used in code block rendering

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

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected nil but got value"
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

// MARK: - Inline languageDisplayName (standalone copy for testing)
// This is a standalone copy of the function from MarkdownHelpers.swift
// so this test can compile without importing the full Extremis module.

func languageDisplayName(for identifier: String?) -> String? {
    guard let id = identifier, !id.isEmpty else { return nil }

    let nameMap: [String: String] = [
        "js": "JavaScript", "javascript": "JavaScript", "jsx": "JSX",
        "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TSX",
        "py": "Python", "python": "Python", "python3": "Python",
        "swift": "Swift", "objc": "Objective-C", "objective-c": "Objective-C", "objectivec": "Objective-C",
        "c": "C", "cpp": "C++", "c++": "C++", "cxx": "C++",
        "cs": "C#", "csharp": "C#",
        "java": "Java", "kt": "Kotlin", "kotlin": "Kotlin",
        "scala": "Scala", "groovy": "Groovy", "clj": "Clojure", "clojure": "Clojure",
        "rs": "Rust", "rust": "Rust", "go": "Go", "golang": "Go", "zig": "Zig",
        "rb": "Ruby", "ruby": "Ruby", "pl": "Perl", "perl": "Perl",
        "lua": "Lua", "r": "R", "php": "PHP",
        "elixir": "Elixir", "ex": "Elixir", "erl": "Erlang", "erlang": "Erlang",
        "sh": "Shell", "bash": "Bash", "zsh": "Zsh", "fish": "Fish",
        "ps1": "PowerShell", "powershell": "PowerShell", "bat": "Batch", "cmd": "Batch",
        "html": "HTML", "css": "CSS", "scss": "SCSS", "sass": "Sass", "less": "Less",
        "json": "JSON", "jsonc": "JSON", "yaml": "YAML", "yml": "YAML",
        "toml": "TOML", "xml": "XML", "csv": "CSV", "ini": "INI", "env": "ENV",
        "properties": "Properties",
        "md": "Markdown", "markdown": "Markdown", "rst": "reStructuredText",
        "tex": "LaTeX", "latex": "LaTeX",
        "sql": "SQL", "mysql": "MySQL", "pgsql": "PostgreSQL", "plsql": "PL/SQL", "sqlite": "SQLite",
        "graphql": "GraphQL", "gql": "GraphQL",
        "dockerfile": "Dockerfile", "docker": "Dockerfile",
        "makefile": "Makefile", "make": "Makefile", "cmake": "CMake",
        "tf": "Terraform", "terraform": "Terraform", "hcl": "HCL", "nginx": "Nginx",
        "diff": "Diff", "patch": "Patch", "vim": "Vim",
        "proto": "Protobuf", "protobuf": "Protobuf",
        "wasm": "WebAssembly", "asm": "Assembly", "dart": "Dart",
        "haskell": "Haskell", "hs": "Haskell",
        "ocaml": "OCaml", "ml": "OCaml",
        "fsharp": "F#", "fs": "F#",
        "lisp": "Lisp", "scheme": "Scheme", "racket": "Racket",
    ]

    return nameMap[id.lowercased()] ?? id.capitalized
}

// MARK: - Tests

func testLanguageDisplayNames() {
    TestRunner.setGroup("Language Display Name — Common Languages")

    // JavaScript family
    TestRunner.assertEqual(languageDisplayName(for: "js"), "JavaScript", "js -> JavaScript")
    TestRunner.assertEqual(languageDisplayName(for: "javascript"), "JavaScript", "javascript -> JavaScript")
    TestRunner.assertEqual(languageDisplayName(for: "jsx"), "JSX", "jsx -> JSX")
    TestRunner.assertEqual(languageDisplayName(for: "ts"), "TypeScript", "ts -> TypeScript")
    TestRunner.assertEqual(languageDisplayName(for: "typescript"), "TypeScript", "typescript -> TypeScript")
    TestRunner.assertEqual(languageDisplayName(for: "tsx"), "TSX", "tsx -> TSX")

    // Python
    TestRunner.assertEqual(languageDisplayName(for: "py"), "Python", "py -> Python")
    TestRunner.assertEqual(languageDisplayName(for: "python"), "Python", "python -> Python")
    TestRunner.assertEqual(languageDisplayName(for: "python3"), "Python", "python3 -> Python")

    // Swift / Apple
    TestRunner.assertEqual(languageDisplayName(for: "swift"), "Swift", "swift -> Swift")
    TestRunner.assertEqual(languageDisplayName(for: "objc"), "Objective-C", "objc -> Objective-C")
    TestRunner.assertEqual(languageDisplayName(for: "objective-c"), "Objective-C", "objective-c -> Objective-C")

    // C family
    TestRunner.assertEqual(languageDisplayName(for: "c"), "C", "c -> C")
    TestRunner.assertEqual(languageDisplayName(for: "cpp"), "C++", "cpp -> C++")
    TestRunner.assertEqual(languageDisplayName(for: "c++"), "C++", "c++ -> C++")
    TestRunner.assertEqual(languageDisplayName(for: "cs"), "C#", "cs -> C#")
    TestRunner.assertEqual(languageDisplayName(for: "csharp"), "C#", "csharp -> C#")

    // JVM
    TestRunner.assertEqual(languageDisplayName(for: "java"), "Java", "java -> Java")
    TestRunner.assertEqual(languageDisplayName(for: "kt"), "Kotlin", "kt -> Kotlin")
    TestRunner.assertEqual(languageDisplayName(for: "kotlin"), "Kotlin", "kotlin -> Kotlin")

    // Systems
    TestRunner.assertEqual(languageDisplayName(for: "rs"), "Rust", "rs -> Rust")
    TestRunner.assertEqual(languageDisplayName(for: "rust"), "Rust", "rust -> Rust")
    TestRunner.assertEqual(languageDisplayName(for: "go"), "Go", "go -> Go")
    TestRunner.assertEqual(languageDisplayName(for: "golang"), "Go", "golang -> Go")
}

func testLanguageDisplayNamesShell() {
    TestRunner.setGroup("Language Display Name — Shell & Scripting")

    TestRunner.assertEqual(languageDisplayName(for: "sh"), "Shell", "sh -> Shell")
    TestRunner.assertEqual(languageDisplayName(for: "bash"), "Bash", "bash -> Bash")
    TestRunner.assertEqual(languageDisplayName(for: "zsh"), "Zsh", "zsh -> Zsh")
    TestRunner.assertEqual(languageDisplayName(for: "rb"), "Ruby", "rb -> Ruby")
    TestRunner.assertEqual(languageDisplayName(for: "ruby"), "Ruby", "ruby -> Ruby")
    TestRunner.assertEqual(languageDisplayName(for: "php"), "PHP", "php -> PHP")
    TestRunner.assertEqual(languageDisplayName(for: "lua"), "Lua", "lua -> Lua")
    TestRunner.assertEqual(languageDisplayName(for: "r"), "R", "r -> R")
}

func testLanguageDisplayNamesDataConfig() {
    TestRunner.setGroup("Language Display Name — Data & Config")

    TestRunner.assertEqual(languageDisplayName(for: "json"), "JSON", "json -> JSON")
    TestRunner.assertEqual(languageDisplayName(for: "jsonc"), "JSON", "jsonc -> JSON")
    TestRunner.assertEqual(languageDisplayName(for: "yaml"), "YAML", "yaml -> YAML")
    TestRunner.assertEqual(languageDisplayName(for: "yml"), "YAML", "yml -> YAML")
    TestRunner.assertEqual(languageDisplayName(for: "toml"), "TOML", "toml -> TOML")
    TestRunner.assertEqual(languageDisplayName(for: "xml"), "XML", "xml -> XML")
    TestRunner.assertEqual(languageDisplayName(for: "sql"), "SQL", "sql -> SQL")
    TestRunner.assertEqual(languageDisplayName(for: "graphql"), "GraphQL", "graphql -> GraphQL")
    TestRunner.assertEqual(languageDisplayName(for: "gql"), "GraphQL", "gql -> GraphQL")
}

func testLanguageDisplayNamesWebMarkup() {
    TestRunner.setGroup("Language Display Name — Web & Markup")

    TestRunner.assertEqual(languageDisplayName(for: "html"), "HTML", "html -> HTML")
    TestRunner.assertEqual(languageDisplayName(for: "css"), "CSS", "css -> CSS")
    TestRunner.assertEqual(languageDisplayName(for: "scss"), "SCSS", "scss -> SCSS")
    TestRunner.assertEqual(languageDisplayName(for: "md"), "Markdown", "md -> Markdown")
    TestRunner.assertEqual(languageDisplayName(for: "markdown"), "Markdown", "markdown -> Markdown")
    TestRunner.assertEqual(languageDisplayName(for: "tex"), "LaTeX", "tex -> LaTeX")
    TestRunner.assertEqual(languageDisplayName(for: "latex"), "LaTeX", "latex -> LaTeX")
}

func testLanguageDisplayNamesDevOps() {
    TestRunner.setGroup("Language Display Name — DevOps & Infra")

    TestRunner.assertEqual(languageDisplayName(for: "dockerfile"), "Dockerfile", "dockerfile -> Dockerfile")
    TestRunner.assertEqual(languageDisplayName(for: "docker"), "Dockerfile", "docker -> Dockerfile")
    TestRunner.assertEqual(languageDisplayName(for: "makefile"), "Makefile", "makefile -> Makefile")
    TestRunner.assertEqual(languageDisplayName(for: "make"), "Makefile", "make -> Makefile")
    TestRunner.assertEqual(languageDisplayName(for: "tf"), "Terraform", "tf -> Terraform")
    TestRunner.assertEqual(languageDisplayName(for: "terraform"), "Terraform", "terraform -> Terraform")
    TestRunner.assertEqual(languageDisplayName(for: "hcl"), "HCL", "hcl -> HCL")
}

func testLanguageDisplayNamesCaseInsensitive() {
    TestRunner.setGroup("Language Display Name — Case Insensitivity")

    TestRunner.assertEqual(languageDisplayName(for: "JS"), "JavaScript", "JS (uppercase) -> JavaScript")
    TestRunner.assertEqual(languageDisplayName(for: "Python"), "Python", "Python (capitalized) -> Python")
    TestRunner.assertEqual(languageDisplayName(for: "SWIFT"), "Swift", "SWIFT (uppercase) -> Swift")
    TestRunner.assertEqual(languageDisplayName(for: "JSON"), "JSON", "JSON (uppercase) -> JSON")
    TestRunner.assertEqual(languageDisplayName(for: "Html"), "HTML", "Html (mixed) -> HTML")
}

func testLanguageDisplayNamesEdgeCases() {
    TestRunner.setGroup("Language Display Name — Edge Cases")

    // Nil input
    TestRunner.assertNil(languageDisplayName(for: nil), "nil -> nil")

    // Empty string
    TestRunner.assertNil(languageDisplayName(for: ""), "empty string -> nil")

    // Unknown language - falls back to capitalized
    TestRunner.assertEqual(languageDisplayName(for: "unknown_lang"), "Unknown_Lang", "unknown -> capitalized")
    TestRunner.assertEqual(languageDisplayName(for: "myCustomLang"), "Mycustomlang", "custom -> capitalized")

    // Single character unknown
    TestRunner.assertEqual(languageDisplayName(for: "x"), "X", "single char unknown -> capitalized")

    // Known single character
    TestRunner.assertEqual(languageDisplayName(for: "c"), "C", "c -> C")
    TestRunner.assertEqual(languageDisplayName(for: "r"), "R", "r -> R")
}

func testLanguageDisplayNamesAdditionalLanguages() {
    TestRunner.setGroup("Language Display Name — Additional Languages")

    TestRunner.assertEqual(languageDisplayName(for: "haskell"), "Haskell", "haskell -> Haskell")
    TestRunner.assertEqual(languageDisplayName(for: "hs"), "Haskell", "hs -> Haskell")
    TestRunner.assertEqual(languageDisplayName(for: "ocaml"), "OCaml", "ocaml -> OCaml")
    TestRunner.assertEqual(languageDisplayName(for: "fsharp"), "F#", "fsharp -> F#")
    TestRunner.assertEqual(languageDisplayName(for: "fs"), "F#", "fs -> F#")
    TestRunner.assertEqual(languageDisplayName(for: "dart"), "Dart", "dart -> Dart")
    TestRunner.assertEqual(languageDisplayName(for: "elixir"), "Elixir", "elixir -> Elixir")
    TestRunner.assertEqual(languageDisplayName(for: "ex"), "Elixir", "ex -> Elixir")
    TestRunner.assertEqual(languageDisplayName(for: "erlang"), "Erlang", "erlang -> Erlang")
    TestRunner.assertEqual(languageDisplayName(for: "proto"), "Protobuf", "proto -> Protobuf")
    TestRunner.assertEqual(languageDisplayName(for: "asm"), "Assembly", "asm -> Assembly")
    TestRunner.assertEqual(languageDisplayName(for: "lisp"), "Lisp", "lisp -> Lisp")
    TestRunner.assertEqual(languageDisplayName(for: "scheme"), "Scheme", "scheme -> Scheme")
}

// MARK: - Main

@main
struct MarkdownRenderingTests {
    static func main() {
        testLanguageDisplayNames()
        testLanguageDisplayNamesShell()
        testLanguageDisplayNamesDataConfig()
        testLanguageDisplayNamesWebMarkup()
        testLanguageDisplayNamesDevOps()
        testLanguageDisplayNamesCaseInsensitive()
        testLanguageDisplayNamesEdgeCases()
        testLanguageDisplayNamesAdditionalLanguages()
        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
