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
            onReprompt: { [weak self] in
                self?.viewModel.goBackToPrompt()
            }
        ))
        window?.contentView = contentView
    }

    // MARK: - Public Methods

    /// Show the prompt window with context
    func showPrompt(with context: Context) {
        print("📋 PromptWindow: Showing with NEW context from \(context.source.applicationName)")

        // Always set new context first
        currentContext = context

        // Reset the view model completely
        viewModel.reset()

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
        print("📋 PromptWindow: Context info = \(contextInfo)")

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

    private var generationTask: Task<Void, Never>?
    private var currentContext: Context?

    func reset() {
        instructionText = ""
        response = ""
        isGenerating = false
        error = nil
        showResponse = false
        currentContext = nil
        updateProviderStatus()
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

                // Use retry helper for resilient generation
                let generation = try await RetryHelper.withRetry(
                    configuration: .default
                ) {
                    try await provider.generate(
                        instruction: self.instructionText,
                        context: context
                    )
                }

                // Check if cancelled
                guard !Task.isCancelled else { return }
                response = generation.content
            } catch is CancellationError {
                // User cancelled, don't show error
            } catch {
                self.error = error.localizedDescription
            }
            isGenerating = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        isGenerating = false
    }

    func regenerate(with context: Context) {
        response = ""
        error = nil
        generate(with: context)
    }

    /// Go back to prompt input view to enter a new instruction
    func goBackToPrompt() {
        generationTask?.cancel()
        isGenerating = false
        response = ""
        error = nil
        showResponse = false
        // Keep instructionText so user can edit it, or clear it for fresh start
        // instructionText = ""  // Uncomment to clear instruction
    }
}


// MARK: - Prompt Container View

struct PromptContainerView: View {
    @ObservedObject var viewModel: PromptViewModel
    let onInsert: (String) -> Void
    let onCancel: () -> Void
    let onGenerate: () -> Void
    let onReprompt: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header with provider status
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                Text("Extremis")
                    .font(.headline)

                // Provider status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.providerConfigured ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(viewModel.providerName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if viewModel.showResponse {
                // Response view
                ResponseView(
                    response: viewModel.response,
                    isGenerating: viewModel.isGenerating,
                    error: viewModel.error,
                    onInsert: { onInsert(viewModel.response) },
                    onCopy: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.response, forType: .string)
                    },
                    onReprompt: onReprompt,
                    onCancel: onCancel
                )
            } else {
                // Input view
                PromptInputView(
                    instructionText: $viewModel.instructionText,
                    isGenerating: $viewModel.isGenerating,
                    contextInfo: viewModel.contextInfo,
                    onSubmit: onGenerate,
                    onCancel: onCancel
                )
            }
        }
        .frame(minWidth: 550, minHeight: 400)
    }
}

