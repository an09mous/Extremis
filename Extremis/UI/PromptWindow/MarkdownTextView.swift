// MARK: - Markdown Text View
// Renders Markdown content using MarkdownUI library

import SwiftUI
import MarkdownUI

/// A view that renders Markdown content with custom styling for Extremis
struct MarkdownTextView: View {
    let content: String

    var body: some View {
        Markdown(content)
            .markdownTheme(.extremis)
            .textSelection(.enabled)
    }
}

// MARK: - Extremis Theme

extension MarkdownUI.Theme {
    /// Custom theme for Extremis that matches the app's visual style
    /// Designed for readability in chat responses with proper code block styling
    static let extremis = Theme()
        // MARK: Text Styles
        .text {
            ForegroundColor(.extremisText)
            FontSize(14)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(.extremisInlineCode)
            BackgroundColor(.extremisInlineCodeBackground)
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .link {
            ForegroundColor(.extremisLink)
            UnderlineStyle(.single)
        }
        .strikethrough {
            StrikethroughStyle(.single)
            ForegroundColor(.extremisSecondaryText)
        }

        // MARK: Block Styles
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.25))
                .markdownMargin(top: 0, bottom: 12)
        }
        .heading1 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: 16, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.6))
                }
        }
        .heading2 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: 14, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.4))
                }
        }
        .heading3 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: 12, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.2))
                }
        }
        .heading4 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: 10, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.1))
                }
        }
        .codeBlock { configuration in
            CodeBlockView(configuration: configuration)
                .markdownMargin(top: 8, bottom: 12)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.extremisQuoteBorder)
                    .frame(width: 4)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.extremisSecondaryText)
                        FontStyle(.italic)
                    }
                    .relativePadding(.leading, length: .em(1))
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)
            .background(Color.extremisQuoteBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .markdownMargin(top: 8, bottom: 12)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.3))
        }
        .taskListMarker { configuration in
            Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor, Color.extremisSecondaryText.opacity(0.3))
                .imageScale(.medium)
                .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: Color.extremisTableBorder))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.extremisTableRowEven, Color.extremisTableRowOdd)
                )
                .markdownMargin(top: 8, bottom: 12)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    BackgroundColor(nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .relativeLineSpacing(.em(0.2))
        }
        .thematicBreak {
            Divider()
                .relativeFrame(height: .em(0.15))
                .overlay(Color.extremisDivider)
                .markdownMargin(top: 16, bottom: 16)
        }
}

// MARK: - Code Block View with Copy Button

/// A custom code block view with a copy button overlay
private struct CodeBlockView: View {
    let configuration: CodeBlockConfiguration
    @State private var isHovering = false
    @State private var showCopied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.3))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                        ForegroundColor(.extremisCodeBlockText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .padding(.top, 8) // Extra top padding for copy button
            }
            .background(Color.extremisCodeBlockBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.extremisCodeBlockBorder, lineWidth: 1)
            )

            // Copy button
            Button(action: copyCode) {
                HStack(spacing: 4) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                    if showCopied {
                        Text("Copied")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundColor(showCopied ? .green : .extremisCodeBlockText.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.extremisCodeBlockBackground.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.extremisCodeBlockBorder, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .opacity(isHovering || showCopied ? 1 : 0.5)
            .padding(6)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration.content, forType: .string)

        withAnimation(.easeInOut(duration: 0.2)) {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopied = false
            }
        }
    }
}

// MARK: - Extremis Color Palette

extension Color {
    // Helper for light/dark mode colors
    fileprivate static func adaptiveColor(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(dark)
            } else {
                return NSColor(light)
            }
        })
    }

    // Text colors
    fileprivate static let extremisText = Color(nsColor: .labelColor)
    fileprivate static let extremisSecondaryText = Color(nsColor: .secondaryLabelColor)

    // Link colors
    fileprivate static let extremisLink = adaptiveColor(
        light: Color(red: 0.2, green: 0.45, blue: 0.85),
        dark: Color(red: 0.4, green: 0.6, blue: 1.0)
    )

    // Inline code colors
    fileprivate static let extremisInlineCode = adaptiveColor(
        light: Color(red: 0.75, green: 0.35, blue: 0.45),
        dark: Color(red: 0.95, green: 0.55, blue: 0.55)
    )
    fileprivate static let extremisInlineCodeBackground = adaptiveColor(
        light: Color(red: 0.95, green: 0.93, blue: 0.94),
        dark: Color(red: 0.2, green: 0.18, blue: 0.2)
    )

    // Code block colors (darker, more contrast)
    fileprivate static let extremisCodeBlockBackground = adaptiveColor(
        light: Color(red: 0.96, green: 0.97, blue: 0.98),
        dark: Color(red: 0.12, green: 0.13, blue: 0.15)
    )
    fileprivate static let extremisCodeBlockText = adaptiveColor(
        light: Color(red: 0.2, green: 0.25, blue: 0.3),
        dark: Color(red: 0.85, green: 0.87, blue: 0.9)
    )
    fileprivate static let extremisCodeBlockBorder = adaptiveColor(
        light: Color(red: 0.88, green: 0.89, blue: 0.91),
        dark: Color(red: 0.25, green: 0.27, blue: 0.3)
    )

    // Blockquote colors
    fileprivate static let extremisQuoteBorder = adaptiveColor(
        light: Color(red: 0.7, green: 0.75, blue: 0.85),
        dark: Color(red: 0.4, green: 0.45, blue: 0.55)
    )
    fileprivate static let extremisQuoteBackground = adaptiveColor(
        light: Color(red: 0.95, green: 0.96, blue: 0.98),
        dark: Color(red: 0.15, green: 0.16, blue: 0.18)
    )

    // Table colors
    fileprivate static let extremisTableBorder = adaptiveColor(
        light: Color(red: 0.85, green: 0.87, blue: 0.9),
        dark: Color(red: 0.3, green: 0.32, blue: 0.35)
    )
    fileprivate static let extremisTableRowEven = adaptiveColor(
        light: Color.white,
        dark: Color(red: 0.13, green: 0.14, blue: 0.16)
    )
    fileprivate static let extremisTableRowOdd = adaptiveColor(
        light: Color(red: 0.97, green: 0.97, blue: 0.98),
        dark: Color(red: 0.16, green: 0.17, blue: 0.19)
    )

    // Divider/thematic break
    fileprivate static let extremisDivider = adaptiveColor(
        light: Color(red: 0.85, green: 0.86, blue: 0.88),
        dark: Color(red: 0.3, green: 0.31, blue: 0.33)
    )
}

// MARK: - Preview

struct MarkdownTextView_Previews: PreviewProvider {
    static var previews: some View {
        MarkdownTextView(content: """
        # Heading 1
        ## Heading 2
        ### Heading 3
        
        This is a paragraph with **bold** and *italic* text.
        
        Here's some `inline code` in a sentence.
        
        ```swift
        func hello() {
            print("Hello, World!")
        }
        ```
        
        > This is a blockquote
        > with multiple lines
        
        - Item 1
        - Item 2
        - Item 3
        
        1. First
        2. Second
        3. Third
        
        [Link to Apple](https://apple.com)
        """)
        .padding()
        .frame(width: 400)
    }
}

