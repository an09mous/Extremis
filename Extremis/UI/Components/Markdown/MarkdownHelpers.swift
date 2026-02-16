// MARK: - Markdown Helpers
// Pure utility functions for markdown rendering support

import Foundation

/// Maps programming language identifiers to human-readable display names.
/// Used by CodeBlockView to show a friendly language label in the header.
///
/// - Parameter identifier: The language identifier from a markdown code fence (e.g., "js", "py", "swift")
/// - Returns: A human-readable name, or nil if the identifier is nil or empty
private let languageNameMap: [String: String] = [
        // JavaScript / TypeScript
        "js": "JavaScript",
        "javascript": "JavaScript",
        "jsx": "JSX",
        "ts": "TypeScript",
        "typescript": "TypeScript",
        "tsx": "TSX",

        // Python
        "py": "Python",
        "python": "Python",
        "python3": "Python",

        // Swift / Apple
        "swift": "Swift",
        "objc": "Objective-C",
        "objective-c": "Objective-C",
        "objectivec": "Objective-C",

        // C family
        "c": "C",
        "cpp": "C++",
        "c++": "C++",
        "cxx": "C++",
        "cs": "C#",
        "csharp": "C#",

        // JVM
        "java": "Java",
        "kt": "Kotlin",
        "kotlin": "Kotlin",
        "scala": "Scala",
        "groovy": "Groovy",
        "clj": "Clojure",
        "clojure": "Clojure",

        // Systems
        "rs": "Rust",
        "rust": "Rust",
        "go": "Go",
        "golang": "Go",
        "zig": "Zig",

        // Scripting
        "rb": "Ruby",
        "ruby": "Ruby",
        "pl": "Perl",
        "perl": "Perl",
        "lua": "Lua",
        "r": "R",
        "php": "PHP",
        "elixir": "Elixir",
        "ex": "Elixir",
        "erl": "Erlang",
        "erlang": "Erlang",

        // Shell
        "sh": "Shell",
        "bash": "Bash",
        "zsh": "Zsh",
        "fish": "Fish",
        "ps1": "PowerShell",
        "powershell": "PowerShell",
        "bat": "Batch",
        "cmd": "Batch",

        // Web
        "html": "HTML",
        "css": "CSS",
        "scss": "SCSS",
        "sass": "Sass",
        "less": "Less",

        // Data / Config
        "json": "JSON",
        "jsonc": "JSON",
        "yaml": "YAML",
        "yml": "YAML",
        "toml": "TOML",
        "xml": "XML",
        "csv": "CSV",
        "ini": "INI",
        "env": "ENV",
        "properties": "Properties",

        // Markup / Docs
        "md": "Markdown",
        "markdown": "Markdown",
        "rst": "reStructuredText",
        "tex": "LaTeX",
        "latex": "LaTeX",

        // Database
        "sql": "SQL",
        "mysql": "MySQL",
        "pgsql": "PostgreSQL",
        "plsql": "PL/SQL",
        "sqlite": "SQLite",
        "graphql": "GraphQL",
        "gql": "GraphQL",

        // DevOps / Infra
        "dockerfile": "Dockerfile",
        "docker": "Dockerfile",
        "makefile": "Makefile",
        "make": "Makefile",
        "cmake": "CMake",
        "tf": "Terraform",
        "terraform": "Terraform",
        "hcl": "HCL",
        "nginx": "Nginx",

        // Other
        "diff": "Diff",
        "patch": "Patch",
        "vim": "Vim",
        "proto": "Protobuf",
        "protobuf": "Protobuf",
        "wasm": "WebAssembly",
        "asm": "Assembly",
        "dart": "Dart",
        "haskell": "Haskell",
        "hs": "Haskell",
        "ocaml": "OCaml",
        "ml": "OCaml",
        "fsharp": "F#",
        "fs": "F#",
        "lisp": "Lisp",
        "scheme": "Scheme",
        "racket": "Racket",
]

func languageDisplayName(for identifier: String?) -> String? {
    guard let id = identifier, !id.isEmpty else { return nil }
    return languageNameMap[id.lowercased()] ?? id.capitalized
}
