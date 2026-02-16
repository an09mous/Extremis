// MARK: - Chat View
// Scrollable message list for chat sessions

import SwiftUI

/// View displaying a scrollable list of chat messages with auto-scroll
struct ChatView: View {
    @ObservedObject var session: ChatSession
    let streamingContent: String
    let isGenerating: Bool
    let error: String?
    /// Active tool calls currently being executed
    let activeToolCalls: [ChatToolCall]
    /// Whether tools are currently executing
    let isExecutingTools: Bool
    /// Callback to retry/regenerate a specific assistant message by its ID
    var onRetryMessage: ((UUID) -> Void)?
    /// Callback to retry after an error (retries the last user message)
    var onRetryError: (() -> Void)?

    // Track streaming state for scroll decisions
    @State private var lastContentLength = 0
    @State private var wasGenerating = false

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    // NOTE: Using VStack (not LazyVStack) intentionally.
                    // LazyVStack is incompatible with bottom-aligned content because it only renders
                    // content in the visible viewport. With `.frame(alignment: .bottom)`, content is
                    // pushed to the bottom, but if scroll starts at top, LazyVStack won't render it
                    // → blank screen. This is a known SwiftUI limitation for chat-style UIs.
                    // See: https://developer.apple.com/forums/thread/741406
                    VStack(spacing: 16) {
                        // Display all completed messages
                        ForEach(Array(session.messages.enumerated()), id: \.element.id) { index, message in
                            ChatMessageView(
                                message: message,
                                onRetry: canRetry(message: message, at: index) ? { onRetryMessage?(message.id) } : nil,
                                isGenerating: isGenerating,
                                context: message.context
                            )
                            .id(message.id)
                        }

                        // Display active tool calls if any
                        if !activeToolCalls.isEmpty {
                            ToolCallsGroupView(toolCalls: activeToolCalls)
                                .id("tool-calls")
                        }

                        // Display streaming message if generating
                        if isGenerating || !streamingContent.isEmpty {
                            StreamingMessageView(
                                content: streamingContent,
                                isGenerating: isGenerating
                            )
                            .id("streaming")
                        }

                        // Display error if present (after streaming content)
                        if let errorMessage = error, !isGenerating {
                            ChatErrorView(message: errorMessage, onRetry: onRetryError)
                                .id("error")
                        }

                        // Bottom anchor for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Ensure content fills at least the available height so messages align to bottom
                    .frame(minHeight: geometry.size.height, alignment: .bottom)
                }
                .onAppear {
                    scrollToBottomAfterLayout(proxy: proxy)
                }
                .onChange(of: session.messages.count) { _ in
                    // Always scroll when new message is added
                    scrollToBottomAfterLayout(proxy: proxy)
                }
                .onChange(of: session.id) { _ in
                    // Scroll to bottom when session changes
                    scrollToBottomAfterLayout(proxy: proxy)
                }
                .onChange(of: isGenerating) { generating in
                    if generating {
                        // Reset tracking when generation starts
                        lastContentLength = 0
                        wasGenerating = true
                    } else if wasGenerating {
                        // Generation just ended - ensure final scroll
                        wasGenerating = false
                        scrollToBottomAfterLayout(proxy: proxy)
                    }
                    scrollToBottomAfterLayout(proxy: proxy)
                }
                .onChange(of: streamingContent) { newValue in
                    // Throttle scroll during streaming: every ~100 chars or on empty (start)
                    let newLength = newValue.count
                    if newLength == 0 || newLength - lastContentLength > 100 {
                        lastContentLength = newLength
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onChange(of: error) { _ in
                    scrollToBottomAfterLayout(proxy: proxy)
                }
                .onChange(of: activeToolCalls.count) { _ in
                    scrollToBottomAfterLayout(proxy: proxy)
                }
            }
        }
    }

    /// Scroll to bottom after giving SwiftUI time to complete layout
    private func scrollToBottomAfterLayout(proxy: ScrollViewProxy, animated: Bool = true) {
        // Small delay to ensure layout is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scrollToBottom(proxy: proxy, animated: animated)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    /// Determine if a message can be retried
    /// Only assistant messages outside the summarized portion can be retried
    private func canRetry(message: ChatMessage, at index: Int) -> Bool {
        // Only assistant messages can be retried
        guard message.role == .assistant else { return false }
        // Cannot retry messages within summarized portion
        return index >= session.summaryCoversCount
    }
}

// MARK: - Chat Error View

/// Error view styled for chat context with optional retry button
struct ChatErrorView: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.headline)
                    .foregroundColor(.red)
                Text(message)
                    .font(.body)
                    .foregroundColor(.primary)
            }

            Spacer()

            // Retry button
            if let retryAction = onRetry {
                Button(action: retryAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                        Text("Retry")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .continuousCornerRadius(DS.Radii.medium)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(DS.Colors.errorSubtle)
        .continuousCornerRadius(DS.Radii.large)
    }
}

/// Compact chat view for displaying session history in response mode
struct CompactChatHistoryView: View {
    @ObservedObject var session: ChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show only the last few messages as context
            let recentMessages = Array(session.messages.suffix(4))

            ForEach(recentMessages) { message in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                        .font(.caption)
                        .foregroundColor(message.role == .user ? .secondary : .accentColor)
                        .frame(width: 16)

                    Text(message.content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if session.messages.count > 4 {
                Text("... and \(session.messages.count - 4) earlier messages")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(8)
        .background(DS.Colors.surfaceSecondary)
        .continuousCornerRadius(DS.Radii.medium)
    }
}

// MARK: - Preview

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let session = ChatSession(originalContext: nil, initialRequest: "Help me write")

        VStack {
            ChatView(
                session: session,
                streamingContent: "Here's an improved version...",
                isGenerating: true,
                error: nil,
                activeToolCalls: [],
                isExecutingTools: false,
                onRetryMessage: { messageId in print("Retry message: \(messageId)") }
            )
            .frame(height: 300)

            Divider()

            CompactChatHistoryView(session: session)
                .padding()
        }
        .frame(width: 400, height: 500)
    }
}

