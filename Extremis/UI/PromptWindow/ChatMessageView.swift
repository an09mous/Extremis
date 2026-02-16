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
    /// Collapse tool history by default after generation completes
    /// User can expand it by clicking the wrench icon if needed
    @State private var showToolHistory = false

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

    private var hasToolHistory: Bool {
        message.hasToolExecutions
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

                    // Tool history indicator (wrench) for assistant messages with tool executions
                    if isAssistant && hasToolHistory {
                        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { showToolHistory.toggle() } }) {
                            HStack(spacing: 2) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Text("\(message.toolCallCount)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("View tool execution history")
                    }
                }

                // Tool execution history (expandable)
                if isAssistant && hasToolHistory && showToolHistory {
                    PersistedToolHistoryView(toolRounds: message.toolRounds ?? [])
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Message content
                if isAssistant {
                    // Assistant: clean text, no bubble — like ChatGPT/Claude.ai
                    MarkdownContentRenderer().render(content: message.content)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                } else {
                    // User: prominent colored bubble
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DS.Colors.userBubble)
                        .continuousCornerRadius(DS.Radii.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radii.large, style: .continuous)
                                .stroke(DS.Colors.userBubbleBorder, lineWidth: 1)
                        )
                }

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
            withAnimation(DS.Animation.hoverTransition) {
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

// MARK: - Persisted Tool History View

/// View showing persisted tool execution history from a completed message
struct PersistedToolHistoryView: View {
    let toolRounds: [ToolExecutionRoundRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(toolRounds.enumerated()), id: \.offset) { index, round in
                VStack(alignment: .leading, spacing: 4) {
                    if toolRounds.count > 1 {
                        Text("Round \(index + 1)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, index > 0 ? 4 : 0)
                    }

                    // Show assistant's partial response before tool calls (if any)
                    if let assistantResponse = round.assistantResponse, !assistantResponse.isEmpty {
                        Text(assistantResponse)
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.9))
                            .padding(.vertical, 2)
                    }

                    ForEach(round.toolCalls) { call in
                        PersistedToolCallRow(
                            call: call,
                            result: round.results.first { $0.callID == call.id }
                        )
                    }
                }
            }
        }
        .padding(8)
        .background(DS.Colors.surfaceSecondary)
        .continuousCornerRadius(DS.Radii.medium)
    }
}

/// Row showing a single persisted tool call with its result
struct PersistedToolCallRow: View {
    let call: ToolCallRecord
    let result: ToolResultRecord?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header
            HStack(spacing: 6) {
                // Status icon
                if let result = result {
                    Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(result.isSuccess ? .green : .red)
                } else {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Tool name
                Text(call.toolName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)

                // Connector badge
                Text(call.connectorID)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(DS.Colors.hoverSubtle)
                    .continuousCornerRadius(DS.Radii.small)

                Spacer()

                // Duration
                if let result = result {
                    Text(result.durationString)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Expand button
                Button(action: { withAnimation(.easeInOut(duration: 0.1)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.1)) { isExpanded.toggle() }
            }

            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    // Arguments
                    if !call.argumentsDisplay.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Text("Args:")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(call.argumentsDisplay)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.8))
                                .lineLimit(3)
                        }
                    }

                    // Result
                    if let result = result {
                        HStack(alignment: .top, spacing: 4) {
                            Text(result.isSuccess ? "Result:" : "Error:")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(result.isSuccess ? .secondary : .red)
                            Text(result.displaySummary)
                                .font(.system(size: 9))
                                .foregroundColor(result.isSuccess ? .primary.opacity(0.8) : .red.opacity(0.8))
                                .lineLimit(4)
                        }
                    }
                }
                .padding(.leading, 16)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
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

                // Message content — no bubble for assistant (clean text)
                if content.isEmpty && isGenerating {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 12)
                } else {
                    Text(content)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
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
            withAnimation(DS.Animation.hoverTransition) {
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

