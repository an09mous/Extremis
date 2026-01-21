// MARK: - Prompt Window Controller
// Manages the floating prompt window

import AppKit
import SwiftUI
@preconcurrency import Combine

/// Controller for the floating prompt window
final class PromptWindowController: NSWindowController {

    // MARK: - Properties

    /// View model for the prompt window
    private let viewModel = PromptViewModel()

    // MARK: - Tool Approval State (T3.14)

    /// Represents a queued approval batch waiting to be processed
    private struct PendingApprovalBatch {
        let requests: [ToolApprovalRequest]
        /// The chat session ID this batch belongs to (for UI isolation)
        let sessionId: UUID?
        let completion: (ApprovalUIResult) -> Void
    }

    /// Queue of pending approval batches (for handling overlapping requests)
    private var approvalQueue: [PendingApprovalBatch] = []

    /// Currently active approval batch being shown in UI (nil if none active)
    private var currentApprovalBatch: PendingApprovalBatch?

    /// Accumulated decisions for the current batch (for individual approvals)
    private var accumulatedDecisions: [String: ApprovalDecision] = [:]

    /// Set of request IDs in the current batch that are still pending
    private var pendingRequestIds: Set<String> = []

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

        // Set up tool approval UI delegate (T3.14)
        ToolApprovalManager.shared.uiDelegate = self

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

        if autoSummarize, let selectedText = context.selectedText, !selectedText.isEmpty {
            // Auto-summarize path: need to wait for any existing generation to stop first
            // to avoid overlapping tasks

            // Show window immediately for responsive UX
            viewModel.prepareForNewInput()  // Non-blocking cancel to clear UI state immediately
            setupPromptUI(with: context)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Capture values for the async block to avoid stale references
            let capturedText = selectedText
            let capturedSource = context.source
            let capturedContext = context

            Task { @MainActor in
                // Wait for any in-progress generation to fully complete
                // (prepareForNewInput already called cancel, this just waits for completion)
                await viewModel.session?.cancelGenerationAndWait()

                print("📋 PromptWindow: Auto-triggering summarization...")
                viewModel.summarize(text: capturedText, source: capturedSource, surroundingContext: capturedContext)
            }
        } else {
            // Normal path: non-blocking cancellation is fine
            viewModel.prepareForNewInput()
            setupPromptUI(with: context)

            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Set up the prompt UI state (shared by sync and async paths)
    private func setupPromptUI(with context: Context) {
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
        let hasSelectedText = context.selectedText?.isEmpty == false
        viewModel.hasContext = hasSelectedText
        viewModel.hasSelection = hasSelectedText
        viewModel.selectedText = context.selectedText

        print("📋 PromptWindow: Context info = \(contextInfo)")

        // Enable chat mode when there's no selection (Chat Mode path)
        // This creates a conversational interface vs. the instruction-based Quick Mode
        if !hasSelectedText {
            viewModel.isChatMode = true
            viewModel.showResponse = true  // Show ResponseView which contains chat UI

            // Sync session from SessionManager if viewModel doesn't have one
            // This ensures we don't create a duplicate session when the user sends a message
            if viewModel.session == nil,
               let existingSession = SessionManager.shared.currentSession {
                viewModel.setRestoredSession(existingSession, id: SessionManager.shared.currentSessionId)
                print("📋 PromptWindow: Synced existing session from SessionManager")
            }

            print("📋 PromptWindow: No selection → Chat Mode enabled")
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
    /// Blocked if generation is in progress
    func startNewSession() async {
        // Block if generation is in progress
        if SessionManager.shared.isAnySessionGenerating {
            print("📋 PromptWindow: Cannot start new session - generation in progress")
            return
        }

        print("📋 PromptWindow: Starting new session")
        viewModel.cancelGeneration()

        // Save the current context before reset (reset clears it)
        let preservedContext = viewModel.currentContext

        viewModel.reset()

        // Restore the context - it should persist until next hotkey invocation
        viewModel.currentContext = preservedContext
        // Keep controller's currentContext as is (don't set to nil)

        await SessionManager.shared.startNewSession()
        // Badge visibility is now tied to SessionManager.hasDraftSession
        // which is automatically set to true when startNewSession() creates an empty session
    }

    /// Select and load a specific session
    /// Blocked if generation is in progress
    func selectSession(id: UUID) async {
        // Block switching if generation is in progress
        if SessionManager.shared.isAnySessionGenerating {
            print("📋 PromptWindow: Cannot switch session - generation in progress")
            return
        }

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

/// View model for the prompt window that delegates generation state to the active session
///
/// ## Architecture
/// Generation state (isGenerating, streamingContent, generationTask) is owned by `ChatSession`
/// to enable per-session isolation. This ViewModel acts as a facade, providing:
/// - Computed properties that delegate to the current session
/// - Backward compatibility for pre-session states (initial prompt entry)
/// - Coordination between UI events and session state
///
/// ## Design Rationale
/// By delegating to session:
/// - Each session owns its generation lifecycle
/// - Session switching doesn't leak state
/// - Future concurrent generation is architecturally possible
@MainActor
final class PromptViewModel: ObservableObject {
    @Published var instructionText: String = ""
    @Published var response: String = ""
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
    @Published var isChatMode: Bool = false

    // Tool execution state
    @Published var activeToolCalls: [ChatToolCall] = []
    @Published var isExecutingTools: Bool = false

    // Tool approval state (T3.13)
    @Published var pendingApprovalRequests: [ApprovalRequestDisplayModel] = []
    @Published var showApprovalView: Bool = false

    /// Callback when user approves a single tool
    var onApproveRequest: ((String, Bool) -> Void)?
    /// Callback when user denies a single tool
    var onDenyRequest: ((String) -> Void)?
    /// Callback when user approves all tools (one-time, no remember)
    var onApproveAll: (() -> Void)?

    // Persistence properties
    private(set) var sessionId: UUID?

    var currentContext: Context?  // Made internal so PromptWindowController can set it

    /// Tracks whether the next message is the first since Extremis was spawned
    /// When true, context should be attached to the next user message
    /// Set to true in prepareForNewInput(), consumed after first message is sent
    private var isFirstMessageSinceSpawn: Bool = true

    /// Cancellable for provider change subscription
    private var providerCancellable: AnyCancellable?

    /// Cancellable for Ollama state changes
    private var ollamaCancellable: AnyCancellable?

    /// Cancellable for session state observation
    private var sessionCancellables = Set<AnyCancellable>()

    // MARK: - Delegated Properties (Per-Session Isolation)

    /// Whether the current session is generating - delegates to session
    /// Returns false if no session exists (safe default for UI)
    var isGenerating: Bool {
        get { session?.isGenerating ?? false }
        set {
            session?.isGenerating = newValue
            // Trigger objectWillChange to update UI
            objectWillChange.send()
        }
    }

    /// Streaming content from the current session - delegates to session
    /// Returns empty string if no session exists (safe default for UI)
    var streamingContent: String {
        get { session?.streamingContent ?? "" }
        set {
            session?.streamingContent = newValue
            // Trigger objectWillChange to update UI
            objectWillChange.send()
        }
    }

    init() {
        // Subscribe to provider changes
        providerCancellable = LLMProviderRegistry.shared.$activeProvider
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateProviderStatus()
                self?.subscribeToOllamaChanges()
            }

        // Subscribe to Ollama state changes (model/connection updates)
        subscribeToOllamaChanges()

        // Initial update
        updateProviderStatus()
    }

    /// Subscribe to Ollama provider state changes for live updates
    private func subscribeToOllamaChanges() {
        ollamaCancellable?.cancel()

        guard let ollama = LLMProviderRegistry.shared.provider(for: .ollama) as? OllamaProvider else {
            return
        }

        // Observe both model and connection state changes
        ollamaCancellable = ollama.$currentModel
            .combineLatest(ollama.$serverConnected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateProviderStatus()
            }
    }

    func reset() {
        // Cancel any in-progress generation via session
        session?.cancelGeneration()

        instructionText = ""
        response = ""
        error = nil
        showResponse = false
        currentContext = nil
        hasContext = false
        hasSelection = false
        selectedText = nil
        isSummarizing = false
        // Reset tool state
        activeToolCalls = []
        isExecutingTools = false
        // Reset approval state (T3.13)
        pendingApprovalRequests = []
        showApprovalView = false
        // Reset chat state
        session = nil
        sessionId = nil
        chatInputText = ""
        isChatMode = false
        isFirstMessageSinceSpawn = true
        sessionCancellables.removeAll()
    }

    /// Prepare for new input without losing session state
    /// Called when hotkey is triggered to show prompt
    func prepareForNewInput() {
        // Cancel any in-progress generation via session (non-blocking)
        session?.cancelGeneration()

        // Clear input-related state but preserve session
        instructionText = ""
        error = nil
        showResponse = false  // Show input view, not response
        hasContext = false
        hasSelection = false
        selectedText = nil
        isSummarizing = false
        chatInputText = ""
        isChatMode = false  // Reset to simple mode - chat mode enables on follow-up

        // Mark that the next message should have context attached
        // This is the first message since the user spawned Extremis
        isFirstMessageSinceSpawn = true

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
        // Keep: session, sessionId, response, isChatMode, showResponse
    }

    /// Observe session state changes to trigger UI updates
    private func observeSessionState(_ session: ChatSession) {
        sessionCancellables.removeAll()

        // Forward session's isGenerating changes to trigger UI updates
        session.$isGenerating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &sessionCancellables)

        // Forward session's streamingContent changes to trigger UI updates
        session.$streamingContent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &sessionCancellables)

        // Forward session's generationError changes
        session.$generationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMsg in
                if let error = errorMsg {
                    self?.error = error
                }
                self?.objectWillChange.send()
            }
            .store(in: &sessionCancellables)
    }

    /// Ensure a session exists, creating one if needed
    /// Note: Does NOT show the new session badge - this is implicit session creation
    /// Badge is shown only for explicit user actions (New Session button, Chat Mode start)
    private func ensureSession(context: Context?, instruction: String?) {
        if session == nil {
            // Create a new session
            let sess = ChatSession(originalContext: context, initialRequest: instruction)
            session = sess
            sessionId = UUID()

            // Observe session state changes for UI reactivity
            observeSessionState(sess)

            // Register with SessionManager immediately
            SessionManager.shared.setCurrentSession(sess, id: sessionId)
            print("📋 PromptViewModel: Created new session \(sessionId!)")
        }
    }

    /// Set a restored session from persistence
    func setRestoredSession(_ sess: ChatSession, id: UUID?) {
        session = sess
        sessionId = id

        // Observe session state changes for UI reactivity
        observeSessionState(sess)

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
        // Note: Session cleanup happens automatically via ChatSession's deinit
        // which cancels any in-flight generation task
        MainActor.assumeIsolated {
            providerCancellable?.cancel()
            ollamaCancellable?.cancel()
        }
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

        // Determine the user message content and intent
        let trimmedInstruction = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSelection = context.selectedText?.isEmpty == false
        let hasInstruction = !trimmedInstruction.isEmpty

        // Determine message content and intent based on context
        let userMessageContent: String
        let intent: MessageIntent

        if hasSelection {
            if hasInstruction {
                // Selection + instruction → transform mode
                userMessageContent = trimmedInstruction
                intent = .selectionTransform
            } else {
                // Selection + no instruction → summarization mode
                userMessageContent = "Summarize this"
                intent = .summarize
            }
        } else {
            // No selection → chat mode
            userMessageContent = hasInstruction ? trimmedInstruction : "Help me with this"
            intent = .chat
        }

        // Ensure we have a session - create one if this is the first interaction
        ensureSession(context: context, instruction: userMessageContent)

        // Add user message to session with embedded context and intent
        if let sess = session {
            let message = ChatMessage.user(userMessageContent, context: context, intent: intent)
            sess.addMessage(message)

            // Explicitly mark dirty to ensure hasDraftSession clears immediately
            // This is a safety net in case the Combine observation has timing issues
            SessionManager.shared.markDirty()
        }

        // Consume the spawn flag - this message has context attached
        isFirstMessageSinceSpawn = false

        currentContext = context
        error = nil
        showResponse = true
        response = ""

        // Capture session and session ID for generation tracking
        guard let sess = session else {
            error = "No session available"
            return
        }
        let capturedSessionId = sessionId

        // Create and start the generation task via session
        let task = Task {
            // Register active generation to block session switching
            if let sid = capturedSessionId {
                SessionManager.shared.registerActiveGeneration(sessionId: sid)
            }

            guard let provider = LLMProviderRegistry.shared.activeProvider else {
                sess.completeGeneration(error: "No provider configured")
                if let sid = capturedSessionId {
                    SessionManager.shared.unregisterActiveGeneration(sessionId: sid)
                }
                return
            }

            // Use tool-enabled generation
            await self.generateWithToolSupport(
                session: sess,
                sessionId: capturedSessionId,
                provider: provider
            )
        }

        // Start generation via session (handles cancellation of any previous task)
        sess.startGeneration(task: task)
    }

    func cancelGeneration() {
        // Capture session ID before cancelling for approval dismissal
        let sessionId = session?.id
        session?.cancelGeneration()
        // Immediately clear tool UI state so user sees the stop take effect
        activeToolCalls = []
        isExecutingTools = false
        // Dismiss any pending approval UI - this completes the approval continuation
        // with "dismissed" decisions, which prevents tools from executing
        pendingApprovalRequests = []
        showApprovalView = false
        // Also notify the ToolApprovalManager to complete any pending approval request
        // This ensures the continuation in waitForUserDecisions is properly resolved
        // Pass the session ID so only this session's approval UI is dismissed
        ToolApprovalManager.shared.uiDelegate?.dismissApprovalUI(for: sessionId)
    }

    // MARK: - Summarization

    /// Summarize the given text (called from Magic Mode or Summarize button)
    /// Uses the unified session-based approach with intent injection
    func summarize(text: String, source: ContextSource, surroundingContext: Context? = nil) {
        print("📝 PromptViewModel: Starting summarization...")

        // Ensure we have a session
        ensureSession(context: surroundingContext, instruction: "Summarize this text")

        // Add summarization request as user message with embedded context and summarize intent
        // The .summarize intent triggers injection of summarization rules in formatUserMessageWithContext()
        if let sess = session {
            let message = ChatMessage.user("Summarize this text", context: surroundingContext, intent: .summarize)
            sess.addMessage(message)

            // Explicitly mark dirty to ensure hasDraftSession clears immediately
            // This is a safety net in case the Combine observation has timing issues
            SessionManager.shared.markDirty()
        }

        // Consume the spawn flag - this message has context attached
        isFirstMessageSinceSpawn = false

        isSummarizing = true
        error = nil
        showResponse = true
        response = ""

        // Capture session and session ID for generation tracking
        guard let sess = session else {
            error = "No session available"
            isSummarizing = false
            return
        }
        let capturedSessionId = sessionId

        // Create and start the generation task via session
        let task = Task {
            // Register active generation to block session switching
            if let sid = capturedSessionId {
                SessionManager.shared.registerActiveGeneration(sessionId: sid)
            }

            guard let provider = LLMProviderRegistry.shared.activeProvider else {
                sess.completeGeneration(error: "No provider configured")
                if let sid = capturedSessionId {
                    SessionManager.shared.unregisterActiveGeneration(sessionId: sid)
                }
                self.isSummarizing = false
                return
            }

            // Use tool-enabled generation with summarization cleanup
            await self.generateWithToolSupport(
                session: sess,
                sessionId: capturedSessionId,
                provider: provider,
                completionHandler: {
                    self.isSummarizing = false
                }
            )
        }

        // Start generation via session (handles cancellation of any previous task)
        sess.startGeneration(task: task)
    }

    /// Summarize using current context (selected text)
    func summarizeSelection() {
        // Determine what text to summarize
        guard let textToSummarize = selectedText, !textToSummarize.isEmpty else {
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
        if let sess = session {
            isChatMode = true
            sess.clearStreamingContent()
            print("💬 Chat mode enabled (session already exists with \(sess.messages.count) messages)")
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

        // Observe session state changes for UI reactivity
        observeSessionState(sess)

        // Register with SessionManager for persistence
        SessionManager.shared.setCurrentSession(sess, id: sessionId)

        print("💬 Chat mode enabled with \(sess.messages.count) messages")
    }

    /// Send a chat message and get a response
    func sendChatMessage() {
        let messageText = chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        // If no session exists, create one for the chat
        if session == nil {
            let sess = ChatSession(originalContext: currentContext, initialRequest: messageText)
            session = sess
            sessionId = UUID()

            // Observe session state changes for UI reactivity
            observeSessionState(sess)

            SessionManager.shared.setCurrentSession(sess, id: sessionId)
            print("💬 Created new session for chat: \(sessionId!)")
        }

        guard let sess = session else { return }

        // First message since spawning Extremis gets context attached
        // Follow-up messages within the same spawn don't need context
        let message: ChatMessage
        if isFirstMessageSinceSpawn, let ctx = currentContext {
            message = ChatMessage.user(messageText, context: ctx, intent: .chat)
            isFirstMessageSinceSpawn = false  // Consume the flag
            print("💬 First message since spawn - attaching context from \(ctx.source.applicationName)")
        } else {
            message = ChatMessage.user(messageText)
        }
        sess.addMessage(message)
        chatInputText = ""
        error = nil

        // Capture session ID for generation tracking
        let capturedSessionId = sessionId

        // Create and start the generation task via session
        let task = Task {
            // Register active generation to block session switching
            if let sid = capturedSessionId {
                SessionManager.shared.registerActiveGeneration(sessionId: sid)
            }

            guard let provider = LLMProviderRegistry.shared.activeProvider else {
                sess.completeGeneration(error: "No provider configured")
                if let sid = capturedSessionId {
                    SessionManager.shared.unregisterActiveGeneration(sessionId: sid)
                }
                return
            }

            // Use tool-enabled generation
            await self.generateWithToolSupport(
                session: sess,
                sessionId: capturedSessionId,
                provider: provider
            )
        }

        // Start generation via session (handles cancellation of any previous task)
        sess.startGeneration(task: task)
    }

    /// Retry/regenerate a specific assistant message
    /// Removes the message and all following messages, then regenerates using the same user input
    func retryMessage(id: UUID) {
        guard let sess = session else {
            print("🔄 Retry failed: No session")
            return
        }

        guard !sess.isGenerating else {
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

        // Clear error state (session handles streaming content reset)
        error = nil

        // Capture session ID for generation tracking
        let capturedSessionId = sessionId

        let task = Task {
            // Register active generation to block session switching
            if let sid = capturedSessionId {
                SessionManager.shared.registerActiveGeneration(sessionId: sid)
            }

            guard let provider = LLMProviderRegistry.shared.activeProvider else {
                sess.completeGeneration(error: "No provider configured")
                if let sid = capturedSessionId {
                    SessionManager.shared.unregisterActiveGeneration(sessionId: sid)
                }
                return
            }

            // Use tool-enabled generation
            await self.generateWithToolSupport(
                session: sess,
                sessionId: capturedSessionId,
                provider: provider
            )
        }

        // Start generation with the task (handles state setup)
        sess.startGeneration(task: task)
    }

    /// Retry after an error - finds the last user message and regenerates
    func retryError() {
        guard let sess = session else {
            print("🔄 Retry error failed: No session")
            return
        }

        guard !sess.isGenerating else {
            print("🔄 Retry error blocked: Already generating")
            return
        }

        // Find the last user message in the session
        guard let lastUserMessage = sess.messages.last(where: { $0.role == .user }) else {
            print("🔄 Retry error failed: No user message found")
            return
        }

        print("🔄 Retrying after error with user message: \(lastUserMessage.content.prefix(50))...")

        // Clear the error (session handles streaming content reset)
        error = nil

        // Capture session ID for generation tracking
        let capturedSessionId = sessionId

        let task = Task {
            // Register active generation to block session switching
            if let sid = capturedSessionId {
                SessionManager.shared.registerActiveGeneration(sessionId: sid)
            }

            guard let provider = LLMProviderRegistry.shared.activeProvider else {
                sess.completeGeneration(error: "No provider configured")
                if let sid = capturedSessionId {
                    SessionManager.shared.unregisterActiveGeneration(sessionId: sid)
                }
                return
            }

            // Use tool-enabled generation
            await self.generateWithToolSupport(
                session: sess,
                sessionId: capturedSessionId,
                provider: provider
            )
        }

        // Start generation with the task (handles state setup)
        sess.startGeneration(task: task)
    }

    // MARK: - Tool-Enabled Generation

    /// Generate a response using the tool-enabled chat service
    /// This method handles the multi-turn tool execution loop and streams content back
    private func generateWithToolSupport(
        session sess: ChatSession,
        sessionId capturedSessionId: UUID?,
        provider: LLMProvider,
        completionHandler: (() -> Void)? = nil
    ) async {
        // Track error for deferred completion
        var generationError: String?

        defer {
            // Always unregister when generation ends (success, error, or cancellation)
            if let sid = capturedSessionId {
                SessionManager.shared.unregisterActiveGeneration(sessionId: sid)
            }
            sess.completeGeneration(error: generationError)
            completionHandler?()
        }

        // Declare outside do block so catch blocks can access them
        var chunks: [String] = []
        var completedToolRounds: [ToolExecutionRoundRecord] = []

        do {
            // Clear any previous tool calls
            activeToolCalls = []
            isExecutingTools = false

            // Use tool-enabled streaming with session-isolated approval
            let stream = ToolEnabledChatService.shared.generateWithToolsStream(
                provider: provider,
                messages: sess.messagesForLLM(),
                sessionApprovalMemory: sess.approvalMemory,
                sessionId: capturedSessionId,
                onToolCallsStarted: { [weak self] toolCalls in
                    guard let self = self else { return }
                    self.activeToolCalls = toolCalls
                    self.isExecutingTools = true
                    print("🔧 Tool calls started: \(toolCalls.map { $0.toolName })")
                },
                onToolCallUpdated: { [weak self] id, state, summary, duration in
                    guard let self = self else { return }
                    if let index = self.activeToolCalls.firstIndex(where: { $0.id == id }) {
                        self.activeToolCalls[index].state = state
                        self.activeToolCalls[index].resultSummary = summary
                        self.activeToolCalls[index].duration = duration
                        if state == .failed {
                            self.activeToolCalls[index].errorMessage = summary
                        }
                    }
                    // Check if all tools are complete
                    if self.activeToolCalls.allComplete {
                        self.isExecutingTools = false
                    }
                }
            )

            for try await event in stream {
                if Task.isCancelled {
                    // Save partial content or show stopped message
                    let partialContent = chunks.joined()
                    if !partialContent.isEmpty || !completedToolRounds.isEmpty {
                        // Include any completed tool rounds in partial save
                        let toolRoundsToSave = completedToolRounds.isEmpty ? nil : completedToolRounds
                        sess.addAssistantMessage(partialContent, toolRounds: toolRoundsToSave)
                        self.response = partialContent
                        print("🔧 Generation stopped - saved partial response with \(completedToolRounds.count) tool rounds")
                    } else {
                        // No content at all - show stopped message
                        let stoppedMessage = "[Generation stopped]"
                        sess.addAssistantMessage(stoppedMessage)
                        self.response = stoppedMessage
                        print("🔧 Generation stopped - no content, showing stopped message")
                    }
                    sess.clearStreamingContent()
                    return
                }

                switch event {
                case .contentChunk(let chunk):
                    chunks.append(chunk)
                    sess.updateStreamingContent(chunks.joined())
                    self.response = chunks.joined()

                case .toolCallsStarted(let toolCalls):
                    // Already handled via callback, but update UI state
                    activeToolCalls = toolCalls
                    isExecutingTools = true

                case .toolCallUpdated(let id, let state, let summary, let duration):
                    // Already handled via callback
                    if let index = activeToolCalls.firstIndex(where: { $0.id == id }) {
                        activeToolCalls[index].state = state
                        activeToolCalls[index].resultSummary = summary
                        activeToolCalls[index].duration = duration
                        if state == .failed {
                            activeToolCalls[index].errorMessage = summary
                        }
                    }
                    if activeToolCalls.allComplete {
                        isExecutingTools = false
                    }

                case .toolResultReady(let toolCall, let result):
                    // Individual tool result - useful for incremental tracking
                    // The round completion event will handle batch persistence
                    let status = result.isSuccess ? "✅" : "❌"
                    print("🔧 Tool result ready: \(status) \(toolCall.toolName)")

                case .toolRoundCompleted(let calls, let results):
                    // A complete round is done - add to completedToolRounds immediately
                    // This ensures partial persistence even if generation is interrupted later
                    let roundRecord = ToolExecutionRoundRecord.from(toolCalls: calls, results: results)
                    completedToolRounds.append(roundRecord)
                    print("🔧 Tool round completed: \(calls.count) calls, total rounds: \(completedToolRounds.count)")

                case .generationComplete(let toolRounds):
                    // Final confirmation - use the authoritative list from the service
                    completedToolRounds = toolRounds
                    print("🔧 Generation complete event received with \(toolRounds.count) tool rounds")

                case .generationInterrupted(_, let partialRounds):
                    // Generation was interrupted but we have partial results
                    // Save them so they can be persisted in the catch block below
                    // Note: The error is propagated via continuation.finish(throwing:) in the service
                    completedToolRounds = partialRounds
                    print("🔧 Generation interrupted with \(partialRounds.count) completed tool rounds")
                }
            }

            // Add assistant response to session with tool execution history
            let finalContent = chunks.joined()

            // Check if we were cancelled - providers finish stream normally on cancellation
            // so we need to check here and show appropriate message
            if Task.isCancelled {
                if !finalContent.isEmpty || !completedToolRounds.isEmpty {
                    let toolRoundsToSave = completedToolRounds.isEmpty ? nil : completedToolRounds
                    sess.addAssistantMessage(finalContent, toolRounds: toolRoundsToSave)
                    self.response = finalContent
                    print("🔧 Generation cancelled (normal finish) - saved partial content")
                } else {
                    let stoppedMessage = "[Generation stopped]"
                    sess.addAssistantMessage(stoppedMessage)
                    self.response = stoppedMessage
                    print("🔧 Generation cancelled (normal finish) - no content, showing stopped message")
                }
                sess.clearStreamingContent()
                activeToolCalls = []
                isExecutingTools = false
                return
            }

            // Save message if we have content OR tool rounds (tools may produce no text response)
            if !finalContent.isEmpty || !completedToolRounds.isEmpty {
                let toolRoundsToSave = completedToolRounds.isEmpty ? nil : completedToolRounds

                // If no text content but we have tool rounds, show a placeholder
                let contentToSave = finalContent.isEmpty && !completedToolRounds.isEmpty
                    ? "[Tool execution completed - see results above]"
                    : finalContent

                sess.addAssistantMessage(contentToSave, toolRounds: toolRoundsToSave)
                self.response = contentToSave

                if !completedToolRounds.isEmpty {
                    let totalCalls = completedToolRounds.reduce(0) { $0 + $1.toolCalls.count }
                    print("🔧 Persisted \(completedToolRounds.count) tool rounds (\(totalCalls) calls) with assistant message")
                }
            }
            sess.clearStreamingContent()

            // Clear tool state after completion
            activeToolCalls = []
            isExecutingTools = false

            print("🔧 Generation complete - session has \(sess.messages.count) messages")
        } catch is CancellationError {
            // User cancelled - save partial content and/or tool rounds
            let partialContent = chunks.joined()

            if !partialContent.isEmpty || !completedToolRounds.isEmpty {
                // We have some content or tool results to save
                let toolRoundsToSave = completedToolRounds.isEmpty ? nil : completedToolRounds
                sess.addAssistantMessage(partialContent, toolRounds: toolRoundsToSave)
                self.response = partialContent
                print("🔧 Generation cancelled - saved partial content and \(completedToolRounds.count) tool rounds")
            } else {
                // No content at all - show a stopped message so user knows what happened
                let stoppedMessage = "[Generation stopped]"
                sess.addAssistantMessage(stoppedMessage)
                self.response = stoppedMessage
                print("🔧 Generation cancelled - no content generated, showing stopped message")
            }

            sess.clearStreamingContent()
            print("🔧 Generation cancelled")
        } catch {
            // Error during generation - still save any completed tool rounds
            if !completedToolRounds.isEmpty {
                let partialContent = chunks.joined()
                // Save partial results even on error so user can see what was completed
                sess.addAssistantMessage(
                    partialContent.isEmpty ? "[Generation interrupted - tool results below]" : partialContent,
                    toolRounds: completedToolRounds
                )
                self.response = partialContent
                print("🔧 Generation error - saved \(completedToolRounds.count) completed tool rounds")
            }
            print("🔧 Generation error: \(error)")
            generationError = error.localizedDescription
            self.error = error.localizedDescription
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
    @ObservedObject var sessionManager = SessionManager.shared
    let onInsert: (String) -> Void
    let onCancel: () -> Void
    let onGenerate: () -> Void
    let onSummarize: () -> Void
    let onSelectSession: (UUID) -> Void
    let onNewSession: () -> Void
    let onDeleteSession: (UUID) -> Void

    @State private var showContextViewer = false
    @State private var showSidebar = false
    @State private var contextForViewer: Context?  // Pre-captured for instant display

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar (session list) with smooth slide animation
            if showSidebar {
                HStack(spacing: 0) {
                    SessionListView(
                        sessionManager: SessionManager.shared,
                        onSelectSession: { id in
                            onSelectSession(id)
                        },
                        onNewSession: {
                            onNewSession()
                        },
                        onDeleteSession: { id in
                            onDeleteSession(id)
                        }
                    )

                    Divider()
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Main content
            VStack(spacing: 0) {
                // Header - ChatGPT style minimal icons
                HStack(spacing: 12) {
                    // Sidebar toggle (ChatGPT style - two rectangles)
                    Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showSidebar.toggle() } }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(showSidebar ? "Hide sidebar" : "Show sidebar")

                    // New chat button (pencil/compose icon)
                    Button(action: {
                        if !sessionManager.isAnySessionGenerating {
                            onNewSession()
                        }
                    }) {
                        Image(systemName: sessionManager.isAnySessionGenerating ? "square.and.pencil.circle" : "square.and.pencil")
                            .font(.system(size: 16))
                            .foregroundColor(sessionManager.isAnySessionGenerating ? .secondary.opacity(0.4) : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(sessionManager.isAnySessionGenerating ? "Generation in progress - wait or cancel to start new session" : "New session")

                    // New session indicator badge - tied to draft session state
                    // Shows when session exists but has no messages yet
                    NewSessionBadge(isVisible: .constant(sessionManager.hasDraftSession))

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
                        onViewContext: viewModel.currentContext != nil ? {
                            // Pre-capture context before showing to avoid lookup during animation
                            contextForViewer = viewModel.currentContext
                            showContextViewer = true
                        } : nil,
                        isChatMode: viewModel.isChatMode,
                        session: viewModel.session,
                        streamingContent: viewModel.streamingContent,
                        chatInputText: $viewModel.chatInputText,
                        onSendChat: { viewModel.sendChatMessage() },
                        onEnableChat: { viewModel.enableChatMode() },
                        onRetryMessage: { messageId in viewModel.retryMessage(id: messageId) },
                        onRetryError: { viewModel.retryError() },
                        activeToolCalls: viewModel.activeToolCalls,
                        isExecutingTools: viewModel.isExecutingTools,
                        showApprovalView: viewModel.showApprovalView,
                        pendingApprovalRequests: viewModel.pendingApprovalRequests,
                        onApproveRequest: viewModel.onApproveRequest,
                        onDenyRequest: viewModel.onDenyRequest,
                        onApproveAll: viewModel.onApproveAll
                    )
                    .id(sessionManager.currentSessionId)  // Force view recreation on session switch to reset scroll state
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
                        onViewContext: viewModel.currentContext != nil ? {
                            contextForViewer = viewModel.currentContext
                            showContextViewer = true
                        } : nil
                    )
                }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 350, idealHeight: 450)
        .overlay {
            // Context viewer overlay (faster than sheet)
            if showContextViewer, let context = contextForViewer {
                ZStack {
                    // Dimmed background
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showContextViewer = false
                            contextForViewer = nil
                        }

                    // Context viewer
                    ContextViewerSheet(
                        context: context,
                        onDismiss: {
                            showContextViewer = false
                            contextForViewer = nil
                        }
                    )
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                    .padding(20)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.85), value: showContextViewer)
    }
}

// MARK: - Tool Approval UI Delegate (T3.14)

extension PromptWindowController: ToolApprovalUIDelegate {

    func showApprovalUI(
        for requests: [ToolApprovalRequest],
        sessionId: UUID?,
        completion: @escaping (ApprovalUIResult) -> Void
    ) {
        let batch = PendingApprovalBatch(requests: requests, sessionId: sessionId, completion: completion)

        // If there's an active batch, queue this one for later
        // Note: In the future with concurrent sessions, we might want to allow multiple active batches
        // if they belong to different sessions. For now, we queue all overlapping requests.
        if currentApprovalBatch != nil {
            print("🔄 Queuing approval batch (\(requests.count) tools, session: \(sessionId?.uuidString.prefix(8) ?? "none")) - another batch is active")
            approvalQueue.append(batch)
            return
        }

        // Start processing this batch
        startApprovalBatch(batch)
    }

    func dismissApprovalUI(for sessionId: UUID?) {
        // If sessionId is provided, only dismiss if it matches the current batch
        // If sessionId is nil, dismiss everything (legacy behavior)
        if let targetSessionId = sessionId {
            // Only dismiss if the current batch belongs to this session
            if let batch = currentApprovalBatch, batch.sessionId == targetSessionId {
                var decisions: [String: ApprovalDecision] = accumulatedDecisions
                for request in batch.requests where decisions[request.id] == nil {
                    decisions[request.id] = ApprovalDecision(
                        request: request,
                        action: .dismissed,
                        reason: "Approval dismissed"
                    )
                }
                completeCurrentBatch(decisions: decisions, allowAllOnce: false)
            }

            // Also dismiss any queued batches for this session
            let batchesToDismiss = approvalQueue.filter { $0.sessionId == targetSessionId }
            approvalQueue.removeAll { $0.sessionId == targetSessionId }

            for queuedBatch in batchesToDismiss {
                var queuedDecisions: [String: ApprovalDecision] = [:]
                for request in queuedBatch.requests {
                    queuedDecisions[request.id] = ApprovalDecision(
                        request: request,
                        action: .dismissed,
                        reason: "Approval dismissed (session cancelled)"
                    )
                }
                print("📋 Dismissing queued batch for session \(targetSessionId.uuidString.prefix(8)) with \(queuedBatch.requests.count) tools")
                queuedBatch.completion(ApprovalUIResult(decisions: queuedDecisions, allowAllOnce: false))
            }
        } else {
            // No sessionId specified - dismiss everything (legacy behavior)
            // Complete current batch with denials (for timeout/cancellation scenarios)
            if let batch = currentApprovalBatch {
                var decisions: [String: ApprovalDecision] = accumulatedDecisions
                for request in batch.requests where decisions[request.id] == nil {
                    decisions[request.id] = ApprovalDecision(
                        request: request,
                        action: .dismissed,
                        reason: "Approval dismissed"
                    )
                }
                // Note: completeCurrentBatch clears UI state, so don't duplicate below
                completeCurrentBatch(decisions: decisions, allowAllOnce: false)
            }

            // Also complete any queued batches with dismissals
            // This prevents zombie batches that would start processing unexpectedly later
            while !approvalQueue.isEmpty {
                let queuedBatch = approvalQueue.removeFirst()
                var queuedDecisions: [String: ApprovalDecision] = [:]
                for request in queuedBatch.requests {
                    queuedDecisions[request.id] = ApprovalDecision(
                        request: request,
                        action: .dismissed,
                        reason: "Approval dismissed (queued)"
                    )
                }
                print("📋 Dismissing queued batch with \(queuedBatch.requests.count) tools")
                queuedBatch.completion(ApprovalUIResult(decisions: queuedDecisions, allowAllOnce: false))
            }

            // Clear UI state (in case no batch was active)
            viewModel.showApprovalView = false
            viewModel.pendingApprovalRequests = []
        }
    }

    func updateApprovalState(requestId: String, state: ApprovalState) {
        if let index = viewModel.pendingApprovalRequests.firstIndex(where: { $0.id == requestId }) {
            viewModel.pendingApprovalRequests[index] = ApprovalRequestDisplayModel(
                id: viewModel.pendingApprovalRequests[index].id,
                toolName: viewModel.pendingApprovalRequests[index].toolName,
                connectorId: viewModel.pendingApprovalRequests[index].connectorId,
                argumentsSummary: viewModel.pendingApprovalRequests[index].argumentsSummary,
                state: state,
                rememberForSession: viewModel.pendingApprovalRequests[index].rememberForSession
            )
        }
    }

    // MARK: - Private Batch Management

    /// Start processing an approval batch
    private func startApprovalBatch(_ batch: PendingApprovalBatch) {
        currentApprovalBatch = batch
        accumulatedDecisions = [:]
        pendingRequestIds = Set(batch.requests.map(\.id))

        // Convert to display models and update UI
        let displayModels = batch.requests.map { ApprovalRequestDisplayModel.from($0) }
        viewModel.pendingApprovalRequests = displayModels
        viewModel.showApprovalView = true

        // Set up callbacks (only once per controller, but safe to reassign)
        viewModel.onApproveRequest = { [weak self] requestId, remember in
            self?.handleApprove(requestId: requestId, remember: remember)
        }
        viewModel.onDenyRequest = { [weak self] requestId in
            self?.handleDeny(requestId: requestId)
        }
        viewModel.onApproveAll = { [weak self] in
            print("📋 onApproveAll callback triggered")
            self?.handleApproveAll()
        }

        print("📋 Started approval batch with \(batch.requests.count) tools (session: \(batch.sessionId?.uuidString.prefix(8) ?? "none"))")
    }

    /// Complete the current batch and process next queued batch if any
    /// - Parameters:
    ///   - decisions: The approval decisions for each tool
    ///   - allowAllOnce: Whether "Allow All Once" was used - skip approval for rest of this generation
    private func completeCurrentBatch(decisions: [String: ApprovalDecision], allowAllOnce: Bool) {
        guard let batch = currentApprovalBatch else {
            print("⚠️ completeCurrentBatch called with no active batch")
            return
        }

        // Clear current batch state first (before calling completion to prevent re-entry issues)
        currentApprovalBatch = nil
        accumulatedDecisions = [:]
        pendingRequestIds = []

        // Dismiss UI
        viewModel.showApprovalView = false
        viewModel.pendingApprovalRequests = []

        // Call completion handler with the result
        let result = ApprovalUIResult(decisions: decisions, allowAllOnce: allowAllOnce)
        print("✅ Completed approval batch with \(decisions.count) decisions, allowAllOnce=\(allowAllOnce)")
        batch.completion(result)

        // Process next batch in queue if any
        if !approvalQueue.isEmpty {
            let nextBatch = approvalQueue.removeFirst()
            print("📋 Processing next queued batch (\(nextBatch.requests.count) tools)")
            startApprovalBatch(nextBatch)
        }
    }

    // MARK: - Private Handlers

    private func handleApprove(requestId: String, remember: Bool) {
        guard let batch = currentApprovalBatch,
              let request = batch.requests.first(where: { $0.id == requestId }) else {
            print("⚠️ handleApprove: request \(requestId) not found in current batch")
            return
        }

        var mutableRequest = request
        mutableRequest.rememberForSession = remember

        let decision = ApprovalDecision(request: mutableRequest, action: .approved)
        resolveRequest(requestId: requestId, decision: decision)
    }

    private func handleDeny(requestId: String) {
        guard let batch = currentApprovalBatch,
              let request = batch.requests.first(where: { $0.id == requestId }) else {
            print("⚠️ handleDeny: request \(requestId) not found in current batch")
            return
        }

        let decision = ApprovalDecision(request: request, action: .denied, reason: "User denied")
        resolveRequest(requestId: requestId, decision: decision)
    }

    private func handleApproveAll() {
        print("📋 handleApproveAll called")
        guard let batch = currentApprovalBatch else {
            print("⚠️ handleApproveAll: no active batch")
            return
        }

        print("📋 handleApproveAll: processing \(batch.requests.count) requests, \(pendingRequestIds.count) pending")

        var decisions: [String: ApprovalDecision] = accumulatedDecisions

        // Allow All is one-time only - no remember for individual tools
        // But we set allowAllOnce=true to skip approval for entire generation
        for request in batch.requests where pendingRequestIds.contains(request.id) {
            decisions[request.id] = ApprovalDecision(request: request, action: .approved)
            print("📋 handleApproveAll: approved \(request.id)")
        }

        print("📋 handleApproveAll: completing batch with \(decisions.count) decisions, allowAllOnce=true")
        completeCurrentBatch(decisions: decisions, allowAllOnce: true)
    }

    private func resolveRequest(requestId: String, decision: ApprovalDecision) {
        // Validate request belongs to current batch
        guard pendingRequestIds.contains(requestId) else {
            print("⚠️ resolveRequest: request \(requestId) not in pending set")
            return
        }

        // Accumulate this decision
        accumulatedDecisions[requestId] = decision

        // Remove from pending
        pendingRequestIds.remove(requestId)

        // Update UI
        viewModel.pendingApprovalRequests.removeAll { $0.id == requestId }

        // Check if all resolved
        if pendingRequestIds.isEmpty {
            // Individual approvals don't set allowAllOnce - only "Allow All Once" button does
            completeCurrentBatch(decisions: accumulatedDecisions, allowAllOnce: false)
        }
        // Note: We intentionally don't hide the UI if viewModel.pendingApprovalRequests is empty
        // but pendingRequestIds is not. This shouldn't happen since they're kept in sync,
        // but if it does, the timeout will eventually trigger and complete the batch.
    }
}

