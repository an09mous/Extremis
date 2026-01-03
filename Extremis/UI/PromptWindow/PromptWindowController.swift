// MARK: - Prompt Window Controller
// Manages the floating prompt window

import AppKit
import SwiftUI
import Combine

/// Controller for the floating prompt window
final class PromptWindowController: NSWindowController {

    // MARK: - Properties

    /// View model for the prompt window
    private let viewModel = PromptViewModel()

    /// Callback when text should be inserted
    var onInsertText: ((String, ContextSource) -> Void)?

    /// Current context
    private var currentContext: Context?

    // MARK: - Initialization

    convenience init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)
        configureWindow()
    }

    // MARK: - Configuration

    private func configureWindow() {
        guard let panel = window as? NSPanel else { return }

        // Configure as floating panel
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false

        // Appearance
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .windowBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.title = "Extremis"

        updateContentView()
        panel.center()
    }

    private func updateContentView() {
        let contentView = NSHostingView(rootView: PromptContainerView(
            viewModel: viewModel,
            onInsert: { [weak self] text in
                guard let context = self?.currentContext else { return }
                self?.onInsertText?(text, context.source)
                self?.hidePrompt()
            },
            onCancel: { [weak self] in
                self?.hidePrompt()
            },
            onGenerate: { [weak self] in
                guard let context = self?.currentContext else {
                    print("❌ No context available for generation")
                    return
                }
                print("🔧 Triggering generation with context")
                self?.viewModel.generate(with: context)
            },
            onSummarize: { [weak self] in
                print("📝 Summarize button clicked")
                self?.viewModel.summarizeSelection()
            }
        ))
        window?.contentView = contentView
    }

    // MARK: - Public Methods

    /// Show the prompt window with context
    func showPrompt(with context: Context) {
        showPromptInternal(with: context, autoSummarize: false)
    }

    /// Show the prompt window and auto-trigger summarization (for Magic Mode)
    func showPromptWithAutoSummarize(with context: Context) {
        showPromptInternal(with: context, autoSummarize: true)
    }

    /// Internal method to show prompt with optional auto-summarize
    private func showPromptInternal(with context: Context, autoSummarize: Bool) {
        print("📋 PromptWindow: Showing with context from \(context.source.applicationName) (autoSummarize: \(autoSummarize))")

        // Always set new context first
        currentContext = context

        // Reset the view model completely
        viewModel.reset()

        // Set the context on the viewModel so it can access source info for summarization
        viewModel.currentContext = context

        // Build context info string
        var contextInfo = context.source.applicationName
        if let windowTitle = context.source.windowTitle {
            contextInfo += " - \(windowTitle)"
        }
        if let selected = context.selectedText, !selected.isEmpty {
            contextInfo += " (text selected: \(selected.prefix(30))...)"
        }

        // Add metadata-specific info
        switch context.metadata {
        case .slack(let slack):
            if let channel = slack.channelName {
                contextInfo += " | #\(channel)"
            }
            if !slack.recentMessages.isEmpty {
                contextInfo += " | \(slack.recentMessages.count) messages"
            }
        case .gmail(let gmail):
            if let subject = gmail.subject {
                contextInfo += " | \(subject)"
            }
        case .github(let github):
            if let pr = github.prNumber {
                contextInfo += " | PR #\(pr)"
            }
        case .generic:
            break
        }

        viewModel.contextInfo = contextInfo

        // Set context state for Summarize button visibility
        // Show Summarize if there's selected text OR preceding/succeeding text
        let hasSelectedText = context.selectedText?.isEmpty == false
        let hasPrecedingText = context.precedingText?.isEmpty == false
        let hasSucceedingText = context.succeedingText?.isEmpty == false
        viewModel.hasContext = hasSelectedText || hasPrecedingText || hasSucceedingText
        viewModel.hasSelection = hasSelectedText

        // Store text for summarization - prefer selected text, otherwise combine preceding/succeeding
        if hasSelectedText {
            viewModel.selectedText = context.selectedText
        } else if hasPrecedingText || hasSucceedingText {
            // Combine preceding and succeeding text for summarization
            let combined = [context.precedingText, context.succeedingText]
                .compactMap { $0 }
                .joined(separator: "\n")
            viewModel.selectedText = combined.isEmpty ? nil : combined
        } else {
            viewModel.selectedText = nil
        }

        print("📋 PromptWindow: Context info = \(contextInfo)")

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Auto-trigger summarization if requested (Magic Mode)
        if autoSummarize, let selectedText = context.selectedText, !selectedText.isEmpty {
            print("📋 PromptWindow: Auto-triggering summarization...")
            viewModel.summarize(text: selectedText, source: context.source, surroundingContext: context)
        }
    }

    /// Hide the prompt window and clear context
    func hidePrompt() {
        print("📋 PromptWindow: Hiding and clearing context")
        viewModel.cancelGeneration()
        viewModel.reset()  // Clear everything including context info
        currentContext = nil  // Clear the context
        window?.orderOut(nil)
    }
}

// MARK: - Prompt View Model

@MainActor
final class PromptViewModel: ObservableObject {
    @Published var instructionText: String = ""
    @Published var response: String = ""
    @Published var isGenerating: Bool = false
    @Published var error: String?
    @Published var contextInfo: String?
    @Published var showResponse: Bool = false
    @Published var providerName: String = "No Provider"
    @Published var providerConfigured: Bool = false

    // Context-aware properties for summarization
    @Published var hasContext: Bool = false  // Has any text context (selected OR preceding/succeeding)
    @Published var hasSelection: Bool = false  // Has specifically selected text
    @Published var selectedText: String?  // Text to summarize (selected OR combined preceding/succeeding)
    @Published var isSummarizing: Bool = false

    // Chat mode properties
    @Published var conversation: ChatConversation?
    @Published var chatInputText: String = ""
    @Published var streamingContent: String = ""
    @Published var isChatMode: Bool = false

    private var generationTask: Task<Void, Never>?
    var currentContext: Context?  // Made internal so PromptWindowController can set it

    /// Summarization service
    private let summarizationService = SummarizationService.shared

    /// Cancellable for provider change subscription
    private var providerCancellable: AnyCancellable?

    init() {
        // Subscribe to provider changes
        providerCancellable = LLMProviderRegistry.shared.$activeProvider
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateProviderStatus()
            }
        // Initial update
        updateProviderStatus()
    }

    func reset() {
        // Cancel any in-progress generation to prevent stale updates
        generationTask?.cancel()
        generationTask = nil

        instructionText = ""
        response = ""
        isGenerating = false
        error = nil
        showResponse = false
        currentContext = nil
        hasContext = false
        hasSelection = false
        selectedText = nil
        isSummarizing = false
        // Reset chat state
        conversation = nil
        chatInputText = ""
        streamingContent = ""
        isChatMode = false
    }

    deinit {
        generationTask?.cancel()
        providerCancellable?.cancel()
    }

    func updateProviderStatus() {
        if let provider = LLMProviderRegistry.shared.activeProvider {
            providerName = provider.displayName
            providerConfigured = provider.isConfigured
        } else {
            providerName = "No Provider"
            providerConfigured = false
        }
    }

    func generate(with context: Context) {
        // Allow empty instruction - this triggers autocomplete mode
        let isAutocomplete = instructionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isAutocomplete {
            print("🔧 Autocomplete mode: No instruction provided, will continue text")
        }

        currentContext = context
        isGenerating = true
        error = nil
        showResponse = true
        response = ""

        generationTask = Task {
            do {
                guard let provider = LLMProviderRegistry.shared.activeProvider else {
                    throw LLMProviderError.notConfigured(provider: .openai)
                }

                // Use streaming for better UX - response appears incrementally
                // This matches the pattern used in summarize() for consistency
                let stream = provider.generateStream(
                    instruction: self.instructionText,
                    context: context
                )

                for try await chunk in stream {
                    // Check cancellation before appending each chunk
                    guard !Task.isCancelled else { return }
                    response += chunk
                }

                print("🔧 Generation complete")
            } catch is CancellationError {
                // User cancelled, don't show error
                print("🔧 Generation cancelled")
            } catch {
                print("🔧 Generation error: \(error)")
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    // MARK: - Summarization

    /// Summarize the given text (called from Magic Mode or Summarize button)
    func summarize(text: String, source: ContextSource, surroundingContext: Context? = nil) {
        print("📝 PromptViewModel: Starting summarization...")

        isSummarizing = true
        isGenerating = true
        error = nil
        showResponse = true
        response = ""

        generationTask = Task {
            do {
                let request = SummaryRequest(
                    text: text,
                    source: source,
                    surroundingContext: surroundingContext
                )

                // Use streaming for better UX
                let stream = summarizationService.summarizeStream(request: request)

                for try await chunk in stream {
                    guard !Task.isCancelled else { return }
                    response += chunk
                }

                print("📝 PromptViewModel: Summarization complete")
            } catch is CancellationError {
                // User cancelled, don't show error
                print("📝 PromptViewModel: Summarization cancelled")
            } catch {
                print("📝 PromptViewModel: Summarization error: \(error)")
                self.error = error.localizedDescription
            }
            isGenerating = false
            isSummarizing = false
        }
    }

    /// Summarize using current context (selected text or combined preceding/succeeding)
    func summarizeSelection() {
        // Determine what text to summarize
        let textToSummarize: String

        if let selected = selectedText, !selected.isEmpty {
            // Use selected text if available
            textToSummarize = selected
        } else if let context = currentContext {
            // Combine preceding + succeeding text if no selection
            let combined = [
                context.precedingText ?? "",
                context.succeedingText ?? ""
            ].filter { !$0.isEmpty }.joined(separator: "\n")

            if combined.isEmpty {
                error = "No text to summarize"
                return
            }
            textToSummarize = combined
        } else {
            error = "No text selected to summarize"
            return
        }

        // Use context source or fallback
        let source = currentContext?.source ?? ContextSource(
            applicationName: "Unknown",
            bundleIdentifier: "unknown",
            windowTitle: nil,
            url: nil
        )

        // Pass the full context for additional context (preceding/succeeding text)
        summarize(text: textToSummarize, source: source, surroundingContext: currentContext)
    }

    // MARK: - Chat Mode

    /// Enable chat mode after initial response is complete
    func enableChatMode() {
        guard !response.isEmpty else { return }

        // Create conversation with initial exchange
        let conv = ChatConversation(originalContext: currentContext, initialRequest: instructionText)

        // Add the initial user message (instruction or summarize request)
        let userContent = isSummarizing ? "Summarize this text" : instructionText
        if !userContent.isEmpty {
            conv.addUserMessage(userContent)
        }

        // Add the initial assistant response
        conv.addAssistantMessage(response)

        conversation = conv
        isChatMode = true
        chatInputText = ""
        streamingContent = ""

        print("💬 Chat mode enabled with \(conv.messages.count) messages")
    }

    /// Send a chat message and get a response
    func sendChatMessage() {
        let messageText = chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }
        guard let conv = conversation else {
            // If no conversation exists, create one first
            enableChatMode()
            return
        }

        // Add user message
        conv.addUserMessage(messageText)
        chatInputText = ""
        streamingContent = ""
        isGenerating = true
        error = nil

        generationTask = Task {
            do {
                guard let provider = LLMProviderRegistry.shared.activeProvider else {
                    throw LLMProviderError.notConfigured(provider: .openai)
                }

                // Use chat streaming
                let stream = provider.generateChatStream(
                    messages: conv.messages,
                    context: currentContext
                )

                for try await chunk in stream {
                    if Task.isCancelled {
                        // Save partial content so user can view, copy, insert, or retry
                        if !streamingContent.isEmpty {
                            conv.addAssistantMessage(streamingContent)
                            response = streamingContent
                            print("💬 Generation stopped - saved partial response")
                        }
                        streamingContent = ""
                        isGenerating = false
                        return
                    }
                    streamingContent += chunk
                }

                // Add completed response to conversation
                if !streamingContent.isEmpty {
                    conv.addAssistantMessage(streamingContent)
                    response = streamingContent
                }
                streamingContent = ""

                print("💬 Chat response complete")
            } catch is CancellationError {
                print("💬 Chat generation cancelled")
            } catch {
                print("💬 Chat error: \(error)")
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }

    /// Retry/regenerate a specific assistant message
    /// Removes the message and all following messages, then regenerates using the same user input
    func retryMessage(id: UUID) {
        guard let conv = conversation else {
            print("🔄 Retry failed: No conversation")
            return
        }

        guard !isGenerating else {
            print("🔄 Retry blocked: Already generating")
            return
        }

        // Remove the assistant message and all following messages
        // The preceding user message is kept in the conversation
        guard let precedingUserMessage = conv.removeMessageAndFollowing(id: id) else {
            print("🔄 Retry failed: Could not find message or preceding user message")
            return
        }

        print("🔄 Retrying with user message: \(precedingUserMessage.content.prefix(50))...")

        // Clear streaming content and regenerate
        // Note: We do NOT re-add the user message - it's still in conv.messages
        streamingContent = ""
        isGenerating = true
        error = nil

        generationTask = Task {
            do {
                guard let provider = LLMProviderRegistry.shared.activeProvider else {
                    throw LLMProviderError.notConfigured(provider: .openai)
                }

                // Use chat streaming with the current messages
                let stream = provider.generateChatStream(
                    messages: conv.messages,
                    context: currentContext
                )

                for try await chunk in stream {
                    if Task.isCancelled {
                        // Save partial content so user can view, copy, insert, or retry
                        if !streamingContent.isEmpty {
                            conv.addAssistantMessage(streamingContent)
                            response = streamingContent
                            print("🔄 Retry stopped - saved partial response")
                        }
                        streamingContent = ""
                        isGenerating = false
                        return
                    }
                    streamingContent += chunk
                }

                // Add completed response to conversation
                if !streamingContent.isEmpty {
                    conv.addAssistantMessage(streamingContent)
                    response = streamingContent
                }
                streamingContent = ""

                print("🔄 Retry complete")
            } catch is CancellationError {
                print("🔄 Retry cancelled")
            } catch {
                print("🔄 Retry error: \(error)")
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }

    /// Retry after an error - finds the last user message and regenerates
    func retryError() {
        guard let conv = conversation else {
            print("🔄 Retry error failed: No conversation")
            return
        }

        guard !isGenerating else {
            print("🔄 Retry error blocked: Already generating")
            return
        }

        // Find the last user message in the conversation
        guard let lastUserMessage = conv.messages.last(where: { $0.role == .user }) else {
            print("🔄 Retry error failed: No user message found")
            return
        }

        print("🔄 Retrying after error with user message: \(lastUserMessage.content.prefix(50))...")

        // Clear the error and regenerate
        error = nil
        streamingContent = ""
        isGenerating = true

        generationTask = Task {
            do {
                guard let provider = LLMProviderRegistry.shared.activeProvider else {
                    throw LLMProviderError.notConfigured(provider: .openai)
                }

                // Use chat streaming with the current messages
                let stream = provider.generateChatStream(
                    messages: conv.messages,
                    context: currentContext
                )

                for try await chunk in stream {
                    if Task.isCancelled {
                        // Save partial content so user can view, copy, insert, or retry
                        if !streamingContent.isEmpty {
                            conv.addAssistantMessage(streamingContent)
                            response = streamingContent
                            print("🔄 Retry stopped - saved partial response")
                        }
                        streamingContent = ""
                        isGenerating = false
                        return
                    }
                    streamingContent += chunk
                }

                // Add completed response to conversation
                if !streamingContent.isEmpty {
                    conv.addAssistantMessage(streamingContent)
                    response = streamingContent
                }
                streamingContent = ""

                print("🔄 Retry after error complete")
            } catch is CancellationError {
                print("🔄 Retry cancelled")
            } catch {
                print("🔄 Retry error: \(error)")
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }

    /// Get the content to use for Insert/Copy (latest assistant message)
    var contentForInsert: String {
        if isChatMode, let conv = conversation {
            return conv.lastAssistantContent
        }
        return response
    }
}


// MARK: - Prompt Container View

struct PromptContainerView: View {
    @ObservedObject var viewModel: PromptViewModel
    let onInsert: (String) -> Void
    let onCancel: () -> Void
    let onGenerate: () -> Void
    let onSummarize: () -> Void

    @State private var showContextViewer = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with provider status - compact inline style
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text("Extremis")
                    .font(.system(size: 13, weight: .semibold))

                Circle()
                    .fill(viewModel.providerConfigured ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(viewModel.providerName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            if viewModel.showResponse {
                // Response view with chat support
                ResponseView(
                    response: viewModel.contentForInsert,
                    isGenerating: viewModel.isGenerating,
                    error: viewModel.error,
                    onInsert: { onInsert(viewModel.contentForInsert) },
                    onCopy: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.contentForInsert, forType: .string)
                    },
                    onCancel: onCancel,
                    onStopGeneration: { viewModel.cancelGeneration() },
                    isChatMode: viewModel.isChatMode,
                    conversation: viewModel.conversation,
                    streamingContent: viewModel.streamingContent,
                    chatInputText: $viewModel.chatInputText,
                    onSendChat: { viewModel.sendChatMessage() },
                    onEnableChat: { viewModel.enableChatMode() },
                    onRetryMessage: { messageId in viewModel.retryMessage(id: messageId) },
                    onRetryError: { viewModel.retryError() }
                )
            } else {
                // Input view
                PromptInputView(
                    instructionText: $viewModel.instructionText,
                    isGenerating: $viewModel.isGenerating,
                    contextInfo: viewModel.contextInfo,
                    hasContext: viewModel.hasContext,
                    hasSelection: viewModel.hasSelection,
                    onSubmit: onGenerate,
                    onCancel: onCancel,
                    onSummarize: onSummarize,
                    onViewContext: viewModel.currentContext != nil ? { showContextViewer = true } : nil
                )
            }
        }
        .frame(minWidth: 550, minHeight: 400)
        .sheet(isPresented: $showContextViewer) {
            if let context = viewModel.currentContext {
                ContextViewerSheet(
                    context: context,
                    onDismiss: { showContextViewer = false }
                )
            }
        }
    }
}

