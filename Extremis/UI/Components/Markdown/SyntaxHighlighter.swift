// MARK: - Syntax Highlighter
// Protocol-based syntax highlighting using JavaScriptCore + highlight.js

import Foundation
import JavaScriptCore

/// Protocol for syntax highlighting engines.
/// Decouples CodeBlockView from a specific highlighting library,
/// enabling future swaps to Splash, Tree-sitter, or custom highlighters.
protocol SyntaxHighlighting: Sendable {
    /// Highlights code and returns a syntax-colored AttributedString.
    /// - Parameters:
    ///   - code: The source code text to highlight
    ///   - language: Optional language identifier (e.g., "swift", "python"). Nil triggers auto-detection.
    ///   - colorScheme: The current color scheme for theme selection
    /// - Returns: A highlighted AttributedString, or nil if highlighting failed
    func highlight(code: String, language: String?, colorScheme: ColorSchemeValue) async -> AttributedString?
}

/// Represents light or dark color scheme for highlighting.
enum ColorSchemeValue: Sendable {
    case light
    case dark
}

/// Lightweight syntax highlighter using JavaScriptCore + highlight.js directly.
/// Uses Xcode-style themes for both light and dark modes.
final class HighlightJSHighlighter: SyntaxHighlighting, @unchecked Sendable {
    /// Shared instance — JavaScriptCore context is reused across calls
    static let shared = HighlightJSHighlighter()

    private var jsContext: JSContext?
    private var hljsObject: JSValue?
    private let lock = NSLock()

    private init() {}

    func highlight(code: String, language: String?, colorScheme: ColorSchemeValue) async -> AttributedString? {
        // Skip highlighting for empty code
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Step 1: Get highlighted HTML from JSContext (thread-safe via lock)
        let htmlResult: String
        do {
            htmlResult = try invokeHighlight(code: code, language: language)
        } catch {
            return nil
        }

        // If hljs returned "undefined" or empty, skip highlighting
        guard htmlResult != "undefined", !htmlResult.isEmpty else { return nil }

        let css = colorScheme == .dark ? Self.xcodeDarkCSS : Self.xcodeLightCSS
        let fullHTML = "<style>\n\(css)\n</style>\n<pre><code class=\"hljs\">\(htmlResult.trimmingCharacters(in: .whitespacesAndNewlines))</code></pre>"

        // Step 2: Parse HTML to AttributedString on main thread
        // NSAttributedString HTML parsing uses WebKit internally and requires the main thread
        return await MainActor.run {
            guard let data = fullHTML.data(using: .utf8) else { return nil as AttributedString? }

            do {
                let nsAttr = try NSMutableAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue,
                    ],
                    documentAttributes: nil
                )

                // Remove font attributes so the SwiftUI Text view uses its own font
                nsAttr.removeAttribute(.font, range: NSRange(location: 0, length: nsAttr.length))

                // Trim trailing newline that HTML parsing adds
                let length = max(nsAttr.length - 1, 0)
                let trimmed = nsAttr.attributedSubstring(from: NSRange(location: 0, length: length))

                return try AttributedString(trimmed, including: \.appKit)
            } catch {
                return nil as AttributedString?
            }
        }
    }

    // MARK: - JavaScript Invocation

    private func invokeHighlight(code: String, language: String?) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        let hljs = try loadHLJS()

        let jsResult: JSValue?
        if let language, !language.isEmpty {
            let options: [String: Any] = ["language": language]
            jsResult = hljs.invokeMethod("highlight", withArguments: [code, options])
        } else {
            jsResult = hljs.invokeMethod("highlightAuto", withArguments: [code])
        }

        guard let result = jsResult,
              let value = result.objectForKeyedSubscript("value").toString() else {
            return ""
        }

        return value
    }

    private func loadHLJS() throws -> JSValue {
        if let hljs = hljsObject {
            return hljs
        }

        guard let context = JSContext() else {
            throw HighlightError.contextCreationFailed
        }

        guard let jsPath = Bundle.module.path(forResource: "highlight.min", ofType: "js") else {
            throw HighlightError.jsFileNotFound
        }

        let script = try String(contentsOfFile: jsPath, encoding: .utf8)
        context.evaluateScript(script)

        guard let hljs = context.objectForKeyedSubscript("hljs") else {
            throw HighlightError.hljsNotFound
        }

        self.jsContext = context
        self.hljsObject = hljs
        return hljs
    }

    // MARK: - Error Types

    private enum HighlightError: Error {
        case contextCreationFailed
        case jsFileNotFound
        case hljsNotFound
    }

    // MARK: - Xcode Theme CSS

    /// Xcode Light theme CSS for highlight.js
    private static let xcodeLightCSS = "pre code.hljs{display:block;overflow-x:auto;padding:1em}code.hljs{padding:3px 5px}.hljs{color:#000}.xml .hljs-meta{color:silver}.hljs-comment,.hljs-quote{color:#007400}.hljs-attribute,.hljs-keyword,.hljs-literal,.hljs-name,.hljs-selector-tag,.hljs-tag{color:#aa0d91}.hljs-template-variable,.hljs-variable{color:#3f6e74}.hljs-code,.hljs-meta .hljs-string,.hljs-string{color:#c41a16}.hljs-link,.hljs-regexp{color:#0e0eff}.hljs-bullet,.hljs-number,.hljs-symbol,.hljs-title{color:#1c00cf}.hljs-meta,.hljs-section{color:#643820}.hljs-built_in,.hljs-class .hljs-title,.hljs-params,.hljs-title.class_,.hljs-type{color:#5c2699}.hljs-attr{color:#836c28}.hljs-subst{color:#000}.hljs-formula{font-style:italic}.hljs-selector-class,.hljs-selector-id{color:#9b703f}.hljs-doctag,.hljs-strong{font-weight:700}.hljs-emphasis{font-style:italic}"

    /// Xcode Dark theme CSS for highlight.js
    private static let xcodeDarkCSS = ".hljs{display:block;overflow-x:auto;padding:0.5em;color:white}.xml .hljs-meta{color:#6C7986}.hljs-comment,.hljs-quote{color:#6C7986}.hljs-tag,.hljs-attribute,.hljs-keyword,.hljs-selector-tag,.hljs-literal,.hljs-name{color:#FC5FA3}.hljs-variable,.hljs-template-variable{color:#FC5FA3}.hljs-code,.hljs-string,.hljs-meta-string{color:#FC6A5D}.hljs-regexp,.hljs-link{color:#5482FF}.hljs-title,.hljs-symbol,.hljs-bullet,.hljs-number{color:#41A1C0}.hljs-section,.hljs-meta{color:#FC5FA3}.hljs-class .hljs-title,.hljs-type,.hljs-built_in,.hljs-builtin-name,.hljs-params{color:#D0A8FF}.hljs-attr{color:#BF8555}.hljs-subst{color:#FFF}.hljs-formula{font-style:italic}.hljs-selector-id,.hljs-selector-class{color:#9b703f}.hljs-doctag,.hljs-strong{font-weight:bold}.hljs-emphasis{font-style:italic}"
}
