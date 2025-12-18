// MARK: - Chat Message View
// Individual message bubble for chat conversations

import SwiftUI
import AppKit

/// View displaying a single chat message bubble with copy functionality
struct ChatMessageView: View {
    let message: ChatMessage

    @State private var isHovering = false
    @State private var showCopied = false

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

                // Message content
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleColor)
                    .cornerRadius(12)

                // Copy button at bottom (always in layout, visibility controlled by opacity)
                HStack(spacing: 4) {
                    Button(action: copyMessage) {
                        HStack(spacing: 3) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(showCopied ? "Copied" : "Copy")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(showCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy message")
                }
                .opacity(isHovering || showCopied ? 1 : 0)
            }

            if !isUser { Spacer(minLength: 40) }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
}

/// View for displaying a streaming message that's still being generated
struct StreamingMessageView: View {
    let content: String
    let isGenerating: Bool

    @State private var isHovering = false
    @State private var showCopied = false

    private var canCopy: Bool {
        !content.isEmpty && !isGenerating
    }

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
                    Text(content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                }

                // Copy button at bottom (always in layout, visibility controlled by opacity)
                HStack(spacing: 4) {
                    Button(action: copyContent) {
                        HStack(spacing: 3) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(showCopied ? "Copied" : "Copy")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(showCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy message")
                    .disabled(!canCopy)
                }
                .opacity(canCopy && (isHovering || showCopied) ? 1 : 0)
            }

            Spacer(minLength: 40)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }
}

// MARK: - Preview

struct ChatMessageView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ChatMessageView(message: ChatMessage(role: .user, content: "Can you help me improve this text?"))
            ChatMessageView(message: ChatMessage(role: .assistant, content: "Of course! I'd be happy to help you improve your text. Please share what you'd like me to work on."))
            StreamingMessageView(content: "I'm currently generating...", isGenerating: true)
            StreamingMessageView(content: "", isGenerating: true)
        }
        .padding()
        .frame(width: 400)
    }
}

