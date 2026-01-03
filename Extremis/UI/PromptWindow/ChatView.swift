// MARK: - Chat View
// Scrollable message list for chat conversations

import SwiftUI

/// View displaying a scrollable list of chat messages with auto-scroll
struct ChatView: View {
    @ObservedObject var conversation: ChatConversation
    let streamingContent: String
    let isGenerating: Bool
    let error: String?
    /// Callback to retry/regenerate a specific assistant message by its ID
    var onRetryMessage: ((UUID) -> Void)?
    /// Callback to retry after an error (retries the last user message)
    var onRetryError: (() -> Void)?

    // Track if user has manually scrolled away from bottom
    @State private var userHasScrolledUp = false
    @State private var lastContentLength = 0

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        // Display all completed messages
                        ForEach(conversation.messages) { message in
                            ChatMessageView(
                                message: message,
                                onRetry: message.role == .assistant ? { onRetryMessage?(message.id) } : nil,
                                isGenerating: isGenerating
                            )
                            .id(message.id)
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
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: conversation.messages.count) { _ in
                    // Always scroll when new message is added
                    userHasScrolledUp = false
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isGenerating) { generating in
                    if generating {
                        // Reset scroll tracking when generation starts
                        userHasScrolledUp = false
                        lastContentLength = 0
                    }
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: streamingContent) { newValue in
                    // Only auto-scroll if user hasn't manually scrolled up
                    // and only every ~100 characters to reduce scroll calls
                    guard !userHasScrolledUp else { return }
                    let newLength = newValue.count
                    if newLength == 0 || newLength - lastContentLength > 100 {
                        lastContentLength = newLength
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onChange(of: error) { _ in
                    scrollToBottom(proxy: proxy)
                }
            }
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
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
}

/// Compact chat view for displaying conversation history in response mode
struct CompactChatHistoryView: View {
    @ObservedObject var conversation: ChatConversation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show only the last few messages as context
            let recentMessages = Array(conversation.messages.suffix(4))
            
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
            
            if conversation.messages.count > 4 {
                Text("... and \(conversation.messages.count - 4) earlier messages")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Preview

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        let conversation = ChatConversation(originalContext: nil, initialRequest: "Help me write")

        VStack {
            ChatView(
                conversation: conversation,
                streamingContent: "Here's an improved version...",
                isGenerating: true,
                error: nil,
                onRetryMessage: { messageId in print("Retry message: \(messageId)") }
            )
            .frame(height: 300)

            Divider()

            CompactChatHistoryView(conversation: conversation)
                .padding()
        }
        .frame(width: 400, height: 500)
    }
}

