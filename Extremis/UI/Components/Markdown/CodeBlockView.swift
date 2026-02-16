// MARK: - Code Block View
// Custom code block component with syntax highlighting, language label, and copy button

import SwiftUI
import MarkdownUI

/// A code block view with a header bar (language label + copy button)
/// and syntax-highlighted content. Falls back to plain monospaced text
/// if highlighting fails or while it loads asynchronously.
struct CodeBlockView: View {
    let configuration: CodeBlockConfiguration

    @State private var highlightedCode: AttributedString?
    @State private var showCopied = false
    @Environment(\.colorScheme) private var colorScheme

    private let syntaxHighlighter: SyntaxHighlighting = HighlightJSHighlighter.shared

    private var displayLanguage: String? {
        languageDisplayName(for: configuration.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider().opacity(0.3)
            codeContent
        }
        .background(codeBlockBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .task(id: highlightKey) {
            await performHighlighting()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            if let name = displayLanguage {
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: copyCode) {
                HStack(spacing: 3) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(showCopied ? "Copied!" : "Copy")
                        .font(.system(size: 10))
                }
                .foregroundColor(showCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(headerBackground)
    }

    // MARK: - Code Content

    private var codeContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if let highlighted = highlightedCode {
                    Text(highlighted)
                        .font(.system(size: 12, design: .monospaced))
                } else {
                    Text(configuration.content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Colors

    private var codeBlockBackground: Color {
        colorScheme == .dark
            ? Color(NSColor.controlBackgroundColor)
            : Color(NSColor.controlBackgroundColor).opacity(0.7)
    }

    private var headerBackground: Color {
        colorScheme == .dark
            ? Color(NSColor.controlBackgroundColor).opacity(0.8)
            : Color(NSColor.controlBackgroundColor).opacity(0.5)
    }

    private var borderColor: Color {
        Color.secondary.opacity(0.15)
    }

    // MARK: - Highlighting

    /// Unique key that triggers re-highlighting when content or color scheme changes
    private var highlightKey: String {
        "\(configuration.content.hashValue)-\(colorScheme)"
    }

    private func performHighlighting() async {
        let scheme: ColorSchemeValue = colorScheme == .dark ? .dark : .light
        let result = await syntaxHighlighter.highlight(
            code: configuration.content,
            language: configuration.language,
            colorScheme: scheme
        )
        highlightedCode = result
    }

    // MARK: - Actions

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration.content, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
}
