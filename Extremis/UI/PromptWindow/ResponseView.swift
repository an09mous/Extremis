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

    // Context display (shown in chat mode)
    var contextInfo: String?
    var onViewContext: (() -> Void)?

    // Chat mode properties (optional)
    var isChatMode: Bool = false
    var session: ChatSession?
    var streamingContent: String = ""
    @Binding var chatInputText: String
    var onSendChat: (() -> Void)?
    var onEnableChat: (() -> Void)?
    var onRetryMessage: ((UUID) -> Void)?
    var onRetryError: (() -> Void)?

    // Tool execution state
    var activeToolCalls: [ChatToolCall] = []
    var isExecutingTools: Bool = false

    // Tool approval state (session-scoped)
    var showApprovalView: Bool = false
    var pendingApprovalRequests: [ApprovalRequestDisplayModel] = []
    var onApproveRequest: ((String, Bool) -> Void)?
    var onDenyRequest: ((String) -> Void)?
    var onApproveAll: (() -> Void)?

    @State private var showCopiedToast = false

    // Auto-scroll tracking for quick mode
    @State private var lastResponseLength = 0
    @State private var wasGeneratingQuickMode = false

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
        self.contextInfo = nil
        self.onViewContext = nil
        self.isChatMode = false
        self.session = nil
        self.streamingContent = ""
        self._chatInputText = .constant("")
        self.onSendChat = nil
        self.onEnableChat = nil
        self.onRetryMessage = nil
        self.onRetryError = nil
        self.activeToolCalls = []
        self.isExecutingTools = false
        self.showApprovalView = false
        self.pendingApprovalRequests = []
        self.onApproveRequest = nil
        self.onDenyRequest = nil
        self.onApproveAll = nil
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
        contextInfo: String? = nil,
        onViewContext: (() -> Void)? = nil,
        isChatMode: Bool,
        session: ChatSession?,
        streamingContent: String,
        chatInputText: Binding<String>,
        onSendChat: @escaping () -> Void,
        onEnableChat: @escaping () -> Void,
        onRetryMessage: ((UUID) -> Void)? = nil,
        onRetryError: (() -> Void)? = nil,
        activeToolCalls: [ChatToolCall] = [],
        isExecutingTools: Bool = false,
        showApprovalView: Bool = false,
        pendingApprovalRequests: [ApprovalRequestDisplayModel] = [],
        onApproveRequest: ((String, Bool) -> Void)? = nil,
        onDenyRequest: ((String) -> Void)? = nil,
        onApproveAll: (() -> Void)? = nil
    ) {
        self.response = response
        self.isGenerating = isGenerating
        self.error = error
        self.onInsert = onInsert
        self.onCopy = onCopy
        self.onCancel = onCancel
        self.onStopGeneration = onStopGeneration
        self.contextInfo = contextInfo
        self.onViewContext = onViewContext
        self.isChatMode = isChatMode
        self.session = session
        self.streamingContent = streamingContent
        self._chatInputText = chatInputText
        self.onSendChat = onSendChat
        self.onEnableChat = onEnableChat
        self.onRetryMessage = onRetryMessage
        self.onRetryError = onRetryError
        self.activeToolCalls = activeToolCalls
        self.isExecutingTools = isExecutingTools
        self.showApprovalView = showApprovalView
        self.pendingApprovalRequests = pendingApprovalRequests
        self.onApproveRequest = onApproveRequest
        self.onDenyRequest = onDenyRequest
        self.onApproveAll = onApproveAll
    }

    var body: some View {
        VStack(spacing: 0) {
            // Context banner (shown when context info is available)
            if let info = contextInfo, !info.isEmpty {
                ContextBanner(text: info, onViewContext: onViewContext)
            }

            // Content area - either chat view or simple response
            if isChatMode, let sess = session {
                ChatView(
                    session: sess,
                    streamingContent: streamingContent,
                    isGenerating: isGenerating,
                    error: error,
                    activeToolCalls: activeToolCalls,
                    isExecutingTools: isExecutingTools,
                    onRetryMessage: onRetryMessage,
                    onRetryError: onRetryError
                )
                .frame(maxHeight: .infinity)
            } else {
                // Quick mode - simple response view with auto-scroll
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let errorMessage = error {
                                ErrorBanner(message: errorMessage, onRetry: onRetryError)
                            } else if response.isEmpty && isGenerating && activeToolCalls.isEmpty {
                                GeneratingPlaceholder()
                            } else {
                                // Display tool calls if any (same as chat mode)
                                if !activeToolCalls.isEmpty {
                                    ToolCallsGroupView(toolCalls: activeToolCalls)
                                }

                                // Display response text if available
                                if !response.isEmpty {
                                    Text(response)
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else if isGenerating && !activeToolCalls.isEmpty {
                                    // Tools are running but no response yet
                                    HStack(spacing: 8) {
                                        LoadingIndicator(style: .dots)
                                        Text("Processing tool results...")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            // Bottom anchor for auto-scroll
                            Color.clear
                                .frame(height: 1)
                                .id("quickModeBottom")
                        }
                        .padding()
                    }
                    .onChange(of: response) { newValue in
                        // Auto-scroll every ~100 characters during generation
                        guard isGenerating else { return }
                        let newLength = newValue.count
                        if newLength == 0 || newLength - lastResponseLength > 100 {
                            lastResponseLength = newLength
                            proxy.scrollTo("quickModeBottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: isGenerating) { generating in
                        if generating {
                            lastResponseLength = 0
                            wasGeneratingQuickMode = true
                        } else if wasGeneratingQuickMode {
                            // Generation just ended - ensure final scroll after layout
                            wasGeneratingQuickMode = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                proxy.scrollTo("quickModeBottom", anchor: .bottom)
                            }
                        }
                        // Delay scroll slightly to ensure layout is complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo("quickModeBottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: activeToolCalls.count) { _ in
                        // Auto-scroll when tool calls appear or change
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo("quickModeBottom", anchor: .bottom)
                        }
                    }
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
        .overlay {
            // Tool approval overlay (session-scoped) - only covers this session's content
            if showApprovalView && !pendingApprovalRequests.isEmpty {
                ZStack {
                    // Semi-transparent background covering just this view
                    Color(NSColor.windowBackgroundColor).opacity(0.9)
                        .ignoresSafeArea()

                    // Approval view at bottom
                    VStack {
                        Spacer()
                        ToolApprovalView(
                            requests: pendingApprovalRequests,
                            onApprove: { requestId, remember in
                                onApproveRequest?(requestId, remember)
                            },
                            onDeny: { requestId in
                                onDenyRequest?(requestId)
                            },
                            onApproveAll: {
                                onApproveAll?()
                            }
                        )
                        .padding()
                    }
                }
                .transition(.opacity)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showApprovalView)
            }
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
                // Show "Continue chatting" prompt - entire row is clickable
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                    Text("Continue chatting...")
                        .font(.callout)
                    Spacer()
                }
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
                .onTapGesture { onEnableChat?() }
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if isGenerating && !isChatMode {
                // During generation in quick mode: minimal stop button on right
                // (In chat mode, the stop button is in ChatInputView)
                Spacer()

                Button(action: { onStopGeneration?() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.primary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Stop generating (Esc)")
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            } else if !isGenerating {
                // After generation: clean action bar
                if !isChatMode {
                    Button(action: {
                        onCopy()
                        showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedToast = false
                        }
                    }) {
                        Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundColor(showCopiedToast ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(response.isEmpty)
                    .help("Copy to clipboard")
                    .animation(.easeInOut(duration: 0.2), value: showCopiedToast)
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .keyboardShortcut(.escape, modifiers: [])

                Button(action: onInsert) {
                    Text("Insert")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(response.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.callout)
            Spacer()

            // Retry button if callback provided
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

