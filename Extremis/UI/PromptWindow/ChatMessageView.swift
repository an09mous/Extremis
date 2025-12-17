// MARK: - Chat Message View
// Individual message bubble for chat conversations

import SwiftUI

/// View displaying a single chat message bubble
struct ChatMessageView: View {
    let message: ChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    private var bubbleColor: Color {
        isUser ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor)
    }

    private var alignment: HorizontalAlignment {
        isUser ? .trailing : .leading
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: alignment, spacing: 4) {
                // Role label
                HStack(spacing: 4) {
                    if !isUser {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    Text(isUser ? "You" : "Extremis")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if isUser {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Message content - Markdown for assistant, plain text for user
                Group {
                    if isUser {
                        Text(message.content)
                            .font(.body)
                            .textSelection(.enabled)
                    } else {
                        MarkdownTextView(content: message.content)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleColor)
                .cornerRadius(12)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

/// View for displaying a streaming message that's still being generated
struct StreamingMessageView: View {
    let content: String
    let isGenerating: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Role label
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                    Text("Extremis")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if isGenerating {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    }
                }

                // Message content
                if content.isEmpty && isGenerating {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                } else {
                    // Use plain text during streaming for performance, Markdown when done
                    Group {
                        if isGenerating {
                            Text(content)
                                .font(.body)
                                .textSelection(.enabled)
                        } else {
                            MarkdownTextView(content: content)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 40)
        }
    }
}

// MARK: - Preview

struct ChatMessageView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 16) {
                ChatMessageView(message: ChatMessage(role: .user, content: "Can you help me write a Swift function?"))
                ChatMessageView(message: ChatMessage(role: .assistant, content: """
                Of course! Here's a simple example:

                ```swift
                func greet(name: String) -> String {
                    return "Hello, \\(name)!"
                }
                ```

                **Key points:**
                - The function takes a `String` parameter
                - It returns a greeting message
                - Use *string interpolation* for dynamic content
                """))
                StreamingMessageView(content: "I'm currently generating...", isGenerating: true)
                StreamingMessageView(content: "", isGenerating: true)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
    }
}

