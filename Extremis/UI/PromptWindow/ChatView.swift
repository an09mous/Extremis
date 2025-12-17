// MARK: - Chat View
// Scrollable message list for chat conversations

import SwiftUI

/// View displaying a scrollable list of chat messages with auto-scroll
struct ChatView: View {
    @ObservedObject var conversation: ChatConversation
    let streamingContent: String
    let isGenerating: Bool
    
    @State private var scrollProxy: ScrollViewProxy?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Display all completed messages
                    ForEach(conversation.messages) { message in
                        ChatMessageView(message: message)
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
                    
                    // Invisible anchor for scrolling to bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding()
            }
            .onAppear {
                scrollProxy = proxy
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: conversation.messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: streamingContent) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
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
                isGenerating: true
            )
            .frame(height: 300)

            Divider()

            CompactChatHistoryView(conversation: conversation)
                .padding()
        }
        .frame(width: 400, height: 500)
    }
}

