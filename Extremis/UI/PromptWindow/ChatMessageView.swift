// MARK: - Chat Message View
// Individual message bubble for chat conversations

import SwiftUI
import AppKit

/// View displaying a single chat message bubble with copy and retry functionality
struct ChatMessageView: View {
    let message: ChatMessage
    /// Callback to retry/regenerate this assistant message (nil for user messages)
    var onRetry: (() -> Void)?
    /// Whether generation is currently in progress (disables retry button)
    var isGenerating: Bool = false
    /// Context associated with this message (optional, for user messages)
    var context: Context? = nil

    @State private var isHovering = false
    @State private var showCopied = false
    @State private var showContextSheet = false

    private var isUser: Bool {
        message.role == .user
    }

    private var isAssistant: Bool {
        message.role == .assistant
    }

    private var canRetry: Bool {
        isAssistant && onRetry != nil && !isGenerating
    }

    private var hasContext: Bool {
        context != nil
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

                        // Context indicator (paperclip) for user messages with context
                        if hasContext {
                            Button(action: { showContextSheet = true }) {
                                Image(systemName: "paperclip")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("View captured context")
                        }
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

                // Action buttons at bottom (always in layout, visibility controlled by opacity)
                HStack(spacing: 8) {
                    // Copy button
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

                    // Retry button (only for assistant messages)
                    if isAssistant, let retryAction = onRetry {
                        Button(action: retryAction) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                Text("Retry")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Retry this response")
                        .disabled(isGenerating)
                        .opacity(isGenerating ? 0.5 : 1)
                    }
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
        .sheet(isPresented: $showContextSheet) {
            if let ctx = context {
                ContextViewerSheet(context: ctx, onDismiss: { showContextSheet = false })
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
    static var sampleContext: Context {
        Context(
            source: ContextSource(
                applicationName: "Visual Studio Code",
                bundleIdentifier: "com.microsoft.VSCode",
                windowTitle: "main.swift - MyProject",
                url: nil
            ),
            selectedText: "func calculateTotal() -> Double { return items.reduce(0) { $0 + $1.price } }",
            metadata: .generic(GenericMetadata(focusedElementRole: "AXTextArea", focusedElementLabel: "Editor"))
        )
    }

    static var previews: some View {
        VStack(spacing: 16) {
            // User message without context
            ChatMessageView(message: ChatMessage(role: .user, content: "Can you help me improve this text?"))

            // User message WITH context (shows paperclip)
            ChatMessageView(
                message: ChatMessage(role: .user, content: "Can you help me fix this function?"),
                context: sampleContext
            )

            ChatMessageView(
                message: ChatMessage(role: .assistant, content: "Of course! I'd be happy to help you improve your text. Please share what you'd like me to work on."),
                onRetry: { print("Retry tapped") },
                isGenerating: false
            )
            ChatMessageView(
                message: ChatMessage(role: .assistant, content: "This response is being regenerated..."),
                onRetry: { },
                isGenerating: true
            )
            StreamingMessageView(content: "I'm currently generating...", isGenerating: true)
            StreamingMessageView(content: "", isGenerating: true)
        }
        .padding()
        .frame(width: 400)
    }
}

