// MARK: - Extremis Markdown Theme
// Custom MarkdownUI theme matching the Extremis visual design

import SwiftUI
import MarkdownUI

extension Theme {
    /// Custom theme matching Extremis's native macOS design.
    /// Uses system colors for automatic dark/light mode adaptation.
    @MainActor static let extremis = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(13)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
            ForegroundColor(.pink)
            BackgroundColor(Color.extremisInlineCodeBackground)
        }
        .strong {
            FontWeight(.semibold)
        }
        .link {
            ForegroundColor(.accentColor)
        }
        .heading1 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 16, bottom: 12)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.6))
                    }
                Divider().overlay(Color.extremisDivider)
            }
        }
        .heading2 { configuration in
            VStack(alignment: .leading, spacing: 0) {
                configuration.label
                    .relativePadding(.bottom, length: .em(0.3))
                    .relativeLineSpacing(.em(0.125))
                    .markdownMargin(top: 16, bottom: 12)
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.35))
                    }
                Divider().overlay(Color.extremisDivider)
            }
        }
        .heading3 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 14, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.15))
                }
        }
        .heading4 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 12, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                }
        }
        .heading5 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 12, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.9))
                }
        }
        .heading6 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 12, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.85))
                    ForegroundColor(.secondary)
                }
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.2))
                .markdownMargin(top: 0, bottom: 8)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                    .fill(Color.accentColor.opacity(0.4))
                    .relativeFrame(width: .em(0.2))
                configuration.label
                    .markdownTextStyle { ForegroundColor(.secondary) }
                    .relativePadding(.horizontal, length: .em(0.8))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .codeBlock { configuration in
            CodeBlockView(configuration: configuration)
                .markdownMargin(top: 0, bottom: 12)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.2))
        }
        .taskListMarker { configuration in
            Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor, Color.accentColor.opacity(0.3))
                .imageScale(.small)
                .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: Color.extremisBorder))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, Color.extremisSecondaryBackground)
                )
                .markdownMargin(top: 0, bottom: 12)
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
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
        }
        .thematicBreak {
            Divider()
                .overlay(Color.extremisDivider)
                .markdownMargin(top: 12, bottom: 12)
        }
}

// MARK: - Theme Colors

extension Color {
    fileprivate static let extremisInlineCodeBackground = DS.Colors.surfacePrimary.opacity(0.6)
    fileprivate static let extremisSecondaryBackground = Color(
        light: DS.Colors.surfacePrimary.opacity(0.5),
        dark: DS.Colors.surfacePrimary.opacity(0.3)
    )
    fileprivate static let extremisBorder = DS.Colors.borderMedium
    fileprivate static let extremisDivider = Color(
        light: Color.secondary.opacity(0.3),
        dark: DS.Colors.borderMedium
    )
}
