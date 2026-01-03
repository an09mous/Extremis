// MARK: - Response View
// SwiftUI view for displaying AI-generated response

import SwiftUI

/// View displaying the AI-generated response with optional chat mode
struct ResponseView: View {
    let response: String
    let isGenerating: Bool
    let error: String?
    let onInsert: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void
    var onStopGeneration: (() -> Void)?

    // Chat mode properties (optional)
    var isChatMode: Bool = false
    var conversation: ChatConversation?
    var streamingContent: String = ""
    @Binding var chatInputText: String
    var onSendChat: (() -> Void)?
    var onEnableChat: (() -> Void)?
    var onRetryMessage: ((UUID) -> Void)?
    var onRetryError: (() -> Void)?

    @State private var showCopiedToast = false

    // Convenience initializer for non-chat mode
    init(
        response: String,
        isGenerating: Bool,
        error: String?,
        onInsert: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onStopGeneration: (() -> Void)? = nil
    ) {
        self.response = response
        self.isGenerating = isGenerating
        self.error = error
        self.onInsert = onInsert
        self.onCopy = onCopy
        self.onCancel = onCancel
        self.onStopGeneration = onStopGeneration
        self.isChatMode = false
        self.conversation = nil
        self.streamingContent = ""
        self._chatInputText = .constant("")
        self.onSendChat = nil
        self.onEnableChat = nil
        self.onRetryMessage = nil
        self.onRetryError = nil
    }

    // Full initializer with chat support
    init(
        response: String,
        isGenerating: Bool,
        error: String?,
        onInsert: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onStopGeneration: (() -> Void)? = nil,
        isChatMode: Bool,
        conversation: ChatConversation?,
        streamingContent: String,
        chatInputText: Binding<String>,
        onSendChat: @escaping () -> Void,
        onEnableChat: @escaping () -> Void,
        onRetryMessage: ((UUID) -> Void)? = nil,
        onRetryError: (() -> Void)? = nil
    ) {
        self.response = response
        self.isGenerating = isGenerating
        self.error = error
        self.onInsert = onInsert
        self.onCopy = onCopy
        self.onCancel = onCancel
        self.onStopGeneration = onStopGeneration
        self.isChatMode = isChatMode
        self.conversation = conversation
        self.streamingContent = streamingContent
        self._chatInputText = chatInputText
        self.onSendChat = onSendChat
        self.onEnableChat = onEnableChat
        self.onRetryMessage = onRetryMessage
        self.onRetryError = onRetryError
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content area - either chat view or simple response
            if isChatMode, let conv = conversation {
                ChatView(
                    conversation: conv,
                    streamingContent: streamingContent,
                    isGenerating: isGenerating,
                    error: error,
                    onRetryMessage: onRetryMessage,
                    onRetryError: onRetryError
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let errorMessage = error {
                            ErrorBanner(message: errorMessage)
                        } else if response.isEmpty && isGenerating {
                            GeneratingPlaceholder()
                        } else {
                            Text(response)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity)
            }

            Divider()

            // Chat input (shown when in chat mode or when response is complete)
            if isChatMode || (!isGenerating && !response.isEmpty && onEnableChat != nil) {
                chatInputSection
                Divider()
            }

            // Action buttons
            actionButtons
        }
    }

    @ViewBuilder
    private var chatInputSection: some View {
        HStack(spacing: 8) {
            if isChatMode {
                ChatInputView(
                    text: $chatInputText,
                    isEnabled: !isGenerating,
                    isGenerating: isGenerating,
                    placeholder: "Ask a follow-up question...",
                    autoFocus: true,
                    onSend: { onSendChat?() },
                    onStopGeneration: onStopGeneration
                )
            } else {
                // Show "Continue chatting" prompt
                Button(action: { onEnableChat?() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                        Text("Continue chatting...")
                            .font(.callout)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            // Only show copy button in non-chat mode (chat mode has per-message copy)
            if !isChatMode {
                Button(action: {
                    onCopy()
                    showCopiedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopiedToast = false
                    }
                }) {
                    Label(showCopiedToast ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                }
                .disabled(response.isEmpty || isGenerating)
            }

            Spacer()

            Text(isChatMode ? "Insert latest response" : "Press Enter to insert")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])

            Button(action: onInsert) {
                Label("Insert", systemImage: "arrow.down.doc")
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .disabled(response.isEmpty || isGenerating)
        }
        .padding()
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.callout)
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Generating Placeholder

struct GeneratingPlaceholder: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 8) {
            LoadingIndicator(style: .dots)
            Text("Generating response\(String(repeating: ".", count: dotCount))")
                .foregroundColor(.secondary)
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 4
        }
    }
}

// MARK: - Preview

struct ResponseView_Previews: PreviewProvider {
    static var previews: some View {
        ResponseView(
            response: "This is a sample AI-generated response that demonstrates how the text will appear.",
            isGenerating: false,
            error: nil,
            onInsert: {},
            onCopy: {},
            onCancel: {}
        )
        .frame(width: 500, height: 400)
    }
}

