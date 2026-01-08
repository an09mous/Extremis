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
                // Use existing context or create a minimal one for new sessions
                let context = self?.currentContext ?? Context(
                    source: ContextSource(applicationName: "Extremis", bundleIdentifier: "com.extremis.app")
                )
                print("🔧 Triggering generation with context")
                self?.viewModel.generate(with: context)
            },
            onSummarize: { [weak self] in
                print("📝 Summarize button clicked")
                self?.viewModel.summarizeSelection()
            },
            onSelectSession: { [weak self] id in
                print("📋 Selecting session: \(id)")
                Task { @MainActor in
                    await self?.selectSession(id: id)
                }
            },
            onNewSession: { [weak self] in
                print("📋 Starting new session")
                Task { @MainActor in
                    await self?.startNewSession()
                }
            },
            onDeleteSession: { [weak self] id in
                print("📋 Deleting session: \(id)")
                Task { @MainActor in
                    await self?.deleteSession(id: id)
                }
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

        // Update SessionManager with the new context so it's saved with messages
        SessionManager.shared.updateCurrentContext(context)

        // Prepare for new input but preserve session state
        // Don't call reset() - keep the session/conversation intact
        viewModel.prepareForNewInput()

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

    /// Hide the prompt window (preserves session state)
    func hidePrompt() {
        print("📋 PromptWindow: Hiding (session preserved)")
        viewModel.cancelGeneration()
        // Don't reset - preserve session state for continuity
        // Just clear the transient UI state
        viewModel.clearTransientState()
        currentContext = nil  // Clear the context
        window?.orderOut(nil)
    }

    /// Set a restored session (for session persistence)
    func setSession(_ session: ChatSession, id: UUID?) {
        viewModel.setRestoredSession(session, id: id)
    }

    /// Start a new session (clear current and create fresh)
    /// Note: Does NOT clear currentContext - context persists until new hotkey invocation
    func startNewSession() async {
        print("📋 PromptWindow: Starting new session")
        viewModel.cancelGeneration()

        // Save the current context before reset (reset clears it)
        let preservedContext = viewModel.currentContext

        viewModel.reset()

        // Restore the context - it should persist until next hotkey invocation
        viewModel.currentContext = preservedContext
        // Keep controller's currentContext as is (don't set to nil)

        await SessionManager.shared.startNewSession()
    }

    /// Select and load a specific session
    func selectSession(id: UUID) async {
        print("📋 PromptWindow: Selecting session \(id)")
        viewModel.cancelGeneration()

        do {
            try await SessionManager.shared.loadSession(id: id)

            // Get the loaded session and set it on the view model
            if let session = SessionManager.shared.currentSession {
                viewModel.setRestoredSession(session, id: id)
            }
        } catch {
            print("📋 PromptWindow: Failed to load session: \(error)")
        }
    }

    /// Delete a session
    func deleteSession(id: UUID) async {
        print("📋 PromptWindow: Deleting session \(id)")

        do {
            // Check if we're deleting the current session
            let isDeletingCurrent = id == SessionManager.shared.currentSessionId

            try await SessionManager.shared.deleteSession(id: id)

            // If we deleted the current session, reset the view model
            if isDeletingCurrent {
                viewModel.reset()
                currentContext = nil
            }
        } catch {
            print("📋 PromptWindow: Failed to delete session: \(error)")
        }
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
    @Published var session: ChatSession?
    @Published var chatInputText: String = ""
    @Published var streamingContent: String = ""
    @Published var isChatMode: Bool = false

    // Persistence properties
    private(set) var sessionId: UUID?

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
        session = nil
        sessionId = nil
        chatInputText = ""
        streamingContent = ""
        isChatMode = false
    }

    /// Prepare for new input without losing session state
    /// Called when hotkey is triggered to show prompt
    func prepareForNewInput() {
        // Cancel any in-progress generation
        generationTask?.cancel()
        generationTask = nil

        // Clear input-related state but preserve session
        instructionText = ""
        isGenerating = false
        error = nil
        showResponse = false  // Show input view, not response
        hasContext = false
        hasSelection = false
        selectedText = nil
        isSummarizing = false
        chatInputText = ""
        streamingContent = ""
        isChatMode = false  // Reset to simple mode - chat mode enables on follow-up

        // DON'T clear: session, sessionId, response (for history)
        // The session continues across invocations
    }

    /// Clear transient UI state when hiding (preserves session)
    func clearTransientState() {
        instructionText = ""
        error = nil
        hasContext = false
        hasSelection = false
        selectedText = nil
        chatInputText = ""
        streamingContent = ""
        // Keep: session, sessionId, response, isChatMode, showResponse
    }

    /// Ensure a session exists, creating one if needed
    private func ensureSession(context: Context?, instruction: String?) {
        if session == nil {
            // Create a new session
            let sess = ChatSession(originalContext: context, initialRequest: instruction)
            session = sess
            sessionId = UUID()

            // Register with SessionManager immediately
            SessionManager.shared.setCurrentSession(sess, id: sessionId)
            print("📋 PromptViewModel: Created new session \(sessionId!)")
        }
    }

    /// Set a restored session from persistence
    func setRestoredSession(_ sess: ChatSession, id: UUID?) {
        session = sess
        sessionId = id

        // If there are messages, enable chat mode
        if !sess.messages.isEmpty {
            isChatMode = true
            showResponse = true

            // Set the last assistant response for Insert/Copy
            if let lastAssistant = sess.lastAssistantMessage {
                response = lastAssistant.content
            }

            // NOTE: Do NOT restore context from persisted messages here.
            // currentContext should always reflect the CURRENT context from the most recent
            // hotkey invocation (set via showPrompt(with:)), not the historical context
            // that was saved with the session. When the user sends a message,
            // the current context will be attached to that new message.

            print("📋 PromptViewModel: Restored session with \(sess.messages.count) messages")
        }

        // Note: SessionManager.loadSession already sets the session there,
        // so we don't need to call setCurrentSession again which would mark it dirty
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

        // Determine the user message content
        // For autocomplete mode, use "Continue this text" as the user request
        let userMessageContent = isAutocomplete ? "Continue this text" : instructionText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ensure we have a session - create one if this is the first interaction
        ensureSession(context: context, instruction: userMessageContent)

        // Add user message to session immediately
        if let sess = session {
            let message = ChatMessage.user(userMessageContent)
            sess.addMessage(message)
            // Register context for this message so it's saved with the message
            SessionManager.shared.registerContextForMessage(messageId: message.id, context: context)
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

                // Add assistant response to session
                if !response.isEmpty, let sess = session {
                    sess.addAssistantMessage(response)
                    // Note: Don't auto-enable chat mode here
                    // User will transition to chat mode when they submit a follow-up
                }

                print("🔧 Generation complete - session has \(session?.messages.count ?? 0) messages")
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

        // Ensure we have a session
        ensureSession(context: surroundingContext, instruction: "Summarize this text")

        // Add summarization request as user message
        if let sess = session {
            let message = ChatMessage.user("Summarize this text")
            sess.addMessage(message)
            // Register context for this message
            SessionManager.shared.registerContextForMessage(messageId: message.id, context: surroundingContext)
        }

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

                // Add assistant response to session
                if !response.isEmpty, let sess = session {
                    sess.addAssistantMessage(response)
                    // Note: Don't auto-enable chat mode here
                    // User will transition to chat mode when they submit a follow-up
                }

                print("📝 PromptViewModel: Summarization complete - session has \(session?.messages.count ?? 0) messages")
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
    /// Note: This is now called when user submits a follow-up message
    /// The session may already exist from initial generation, so we only need to enable chat mode
    func enableChatMode() {
        guard !response.isEmpty else { return }

        // If session already exists (from initial generation), just enable chat mode
        if session != nil {
            isChatMode = true
            streamingContent = ""
            print("💬 Chat mode enabled (session already exists with \(session?.messages.count ?? 0) messages)")
            return
        }

        // Legacy path: Create session with initial exchange (for edge cases)
        let sess = ChatSession(originalContext: currentContext, initialRequest: instructionText)

        // Add the initial user message (instruction or summarize request)
        let userContent = isSummarizing ? "Summarize this text" : instructionText
        if !userContent.isEmpty {
            sess.addUserMessage(userContent)
        }

        // Add the initial assistant response
        sess.addAssistantMessage(response)

        session = sess
        sessionId = UUID()
        isChatMode = true
        // Note: Don't clear chatInputText here - it contains the follow-up message
        streamingContent = ""

        // Register with SessionManager for persistence
        SessionManager.shared.setCurrentSession(sess, id: sessionId)

        print("💬 Chat mode enabled with \(sess.messages.count) messages")
    }

    /// Send a chat message and get a response
    func sendChatMessage() {
        let messageText = chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }
        guard let sess = session else {
            // If no session exists, create one first
            enableChatMode()
            return
        }

        // Add user message
        let message = ChatMessage.user(messageText)
        sess.addMessage(message)
        // Register context for this chat message (uses current context from last hotkey invocation)
        SessionManager.shared.registerContextForMessage(messageId: message.id, context: currentContext)
        chatInputText = ""
        streamingContent = ""
        isGenerating = true
        error = nil

        generationTask = Task {
            do {
                guard let provider = LLMProviderRegistry.shared.activeProvider else {
                    throw LLMProviderError.notConfigured(provider: .openai)
                }

                // Use chat streaming (use messagesForLLM for trimmed context)
                let stream = provider.generateChatStream(
                    messages: sess.messagesForLLM(),
                    context: currentContext
                )

                for try await chunk in stream {
                    if Task.isCancelled {
                        // Save partial content so user can view, copy, insert, or retry
                        if !streamingContent.isEmpty {
                            sess.addAssistantMessage(streamingContent)
                            response = streamingContent
                            print("💬 Generation stopped - saved partial response")
                        }
                        streamingContent = ""
                        isGenerating = false
                        return
                    }
                    streamingContent += chunk
                }

                // Add completed response to session
                if !streamingContent.isEmpty {
                    sess.addAssistantMessage(streamingContent)
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
        guard let sess = session else {
            print("🔄 Retry failed: No session")
            return
        }

        guard !isGenerating else {
            print("🔄 Retry blocked: Already generating")
            return
        }

        // Remove the assistant message and all following messages
        // The preceding user message is kept in the session
        guard let precedingUserMessage = sess.removeMessageAndFollowing(id: id) else {
            print("🔄 Retry failed: Could not find message or preceding user message")
            return
        }

        print("🔄 Retrying with user message: \(precedingUserMessage.content.prefix(50))...")

        // Clear streaming content and regenerate
        // Note: We do NOT re-add the user message - it's still in sess.messages
        streamingContent = ""
        isGenerating = true
        error = nil

        generationTask = Task {
            do {
                guard let provider = LLMProviderRegistry.shared.activeProvider else {
                    throw LLMProviderError.notConfigured(provider: .openai)
                }

                // Use chat streaming with the current messages (trimmed for LLM context)
                let stream = provider.generateChatStream(
                    messages: sess.messagesForLLM(),
                    context: currentContext
                )

                for try await chunk in stream {
                    if Task.isCancelled {
                        // Save partial content so user can view, copy, insert, or retry
                        if !streamingContent.isEmpty {
                            sess.addAssistantMessage(streamingContent)
                            response = streamingContent
                            print("🔄 Retry stopped - saved partial response")
                        }
                        streamingContent = ""
                        isGenerating = false
                        return
                    }
                    streamingContent += chunk
                }

                // Add completed response to session
                if !streamingContent.isEmpty {
                    sess.addAssistantMessage(streamingContent)
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
        guard let sess = session else {
            print("🔄 Retry error failed: No session")
            return
        }

        guard !isGenerating else {
            print("🔄 Retry error blocked: Already generating")
            return
        }

        // Find the last user message in the session
        guard let lastUserMessage = sess.messages.last(where: { $0.role == .user }) else {
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

                // Use chat streaming with the current messages (trimmed for LLM context)
                let stream = provider.generateChatStream(
                    messages: sess.messagesForLLM(),
                    context: currentContext
                )

                for try await chunk in stream {
                    if Task.isCancelled {
                        // Save partial content so user can view, copy, insert, or retry
                        if !streamingContent.isEmpty {
                            sess.addAssistantMessage(streamingContent)
                            response = streamingContent
                            print("🔄 Retry stopped - saved partial response")
                        }
                        streamingContent = ""
                        isGenerating = false
                        return
                    }
                    streamingContent += chunk
                }

                // Add completed response to session
                if !streamingContent.isEmpty {
                    sess.addAssistantMessage(streamingContent)
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
        if isChatMode, let sess = session {
            return sess.lastAssistantContent
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
    let onSelectSession: (UUID) -> Void
    let onNewSession: () -> Void
    let onDeleteSession: (UUID) -> Void

    @State private var showContextViewer = false
    @State private var showSidebar = false
    @State private var sidebarRefreshKey = UUID()

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar (session list)
            if showSidebar {
                SessionListView(
                    sessionManager: SessionManager.shared,
                    onSelectSession: { id in
                        onSelectSession(id)
                        sidebarRefreshKey = UUID()
                    },
                    onNewSession: {
                        onNewSession()
                        sidebarRefreshKey = UUID()
                    },
                    onDeleteSession: { id in
                        onDeleteSession(id)
                        sidebarRefreshKey = UUID()
                    }
                )
                .id(sidebarRefreshKey)

                Divider()
            }

            // Main content
            VStack(spacing: 0) {
                // Header - ChatGPT style minimal icons
                HStack(spacing: 12) {
                    // Sidebar toggle (ChatGPT style - two rectangles)
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() } }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showSidebar ? "Hide sidebar" : "Show sidebar")

                    // New chat button (pencil/compose icon)
                    Button(action: { onNewSession() }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("New session")

                    Spacer()

                    // Provider status - compact
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.providerConfigured ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(viewModel.providerName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
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
                        contextInfo: viewModel.contextInfo,
                        onViewContext: viewModel.currentContext != nil ? { showContextViewer = true } : nil,
                        isChatMode: viewModel.isChatMode,
                        session: viewModel.session,
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
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 350, idealHeight: 450)
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

