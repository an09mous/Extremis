// MARK: - Message Content Renderer
// Protocol-based content rendering abstraction for extensibility

import SwiftUI
import MarkdownUI

/// Protocol defining how message content is rendered.
/// Enables swapping rendering strategies (e.g., MarkdownUI today, WKWebView tomorrow)
/// without modifying integration points in ChatMessageView or ResponseView.
@MainActor
protocol MessageContentRenderer {
    associatedtype RenderedContent: View
    func render(content: String) -> RenderedContent
}

/// Renders message content as rich markdown using MarkdownUI with the Extremis theme.
/// Handles all valid and invalid markdown gracefully — malformed syntax is rendered
/// as literal text per the CommonMark specification.
@MainActor
struct MarkdownContentRenderer: MessageContentRenderer {
    func render(content: String) -> some View {
        Markdown(content)
            .markdownTheme(.extremis)
            .textSelection(.enabled)
    }
}
