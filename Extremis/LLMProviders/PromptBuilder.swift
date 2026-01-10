// MARK: - Prompt Builder
// Centralized prompt construction from templates

import Foundation

// NOTE: Context text truncation is now handled at capture time in Context.swift
// See kContextMax*Length constants there. This ensures storage efficiency and
// prevents duplicate truncation logic.

/// Builds prompts from templates with context and instruction placeholders
final class PromptBuilder {

    // MARK: - Singleton

    static let shared = PromptBuilder()

    // MARK: - Dependencies

    private let templateLoader: PromptTemplateLoader

    // MARK: - Initialization

    init(templateLoader: PromptTemplateLoader = .shared) {
        self.templateLoader = templateLoader
    }

    // MARK: - Template Properties

    /// System prompt loaded from template
    private var systemPrompt: String {
        try! templateLoader.load(.system)
    }

    /// Instruction template loaded from file
    private var instructionTemplate: String {
        try! templateLoader.load(.instruction)
    }

    /// Selection transform template loaded from file
    private var selectionTransformTemplate: String {
        try! templateLoader.load(.selectionTransform)
    }

    /// Summarization template loaded from file
    private var summarizationTemplate: String {
        try! templateLoader.load(.summarization)
    }

    /// Chat system prompt template loaded from file
    private var chatSystemPromptTemplate: String {
        try! templateLoader.load(.chatSystem)
    }

    // MARK: - Prompt Mode Detection

    /// Determines the prompt mode based on instruction and context
    enum PromptMode: String {
        case instruction = "INSTRUCTION"                 // No selection, has instruction → general Q&A
        case selectionTransform = "SELECTION_TRANSFORM"  // Has selection, has instruction → transform text
        case selectionNoInstruction = "SELECTION_NO_INSTRUCTION"  // Has selection, no instruction → default to summarize
    }

    /// Detect the appropriate prompt mode
    func detectPromptMode(instruction: String, context: Context) -> PromptMode {
        let hasInstruction = !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSelection = context.selectedText != nil && !context.selectedText!.isEmpty

        if hasSelection {
            return hasInstruction ? .selectionTransform : .selectionNoInstruction
        } else {
            // No selection - instruction mode (Chat Mode handles the empty instruction case)
            return .instruction
        }
    }

    // MARK: - Configuration

    /// Enable/disable debug logging (set to false in production)
    var debugLogging: Bool = true

    // MARK: - Public Methods

    /// Build a complete prompt from instruction and context
    /// Automatically selects the appropriate template based on:
    /// - Instruction: Has instruction, no selection → general Q&A with context
    /// - Selection Transform: Has instruction AND selection → transform selected text
    func buildPrompt(instruction: String, context: Context) -> String {
        let mode = detectPromptMode(instruction: instruction, context: context)

        let prompt: String
        switch mode {
        case .selectionTransform:
            // Selection transform mode - has instruction AND selection
            prompt = buildSelectionPrompt(context: context, instruction: instruction)

        case .instruction:
            // Standard instruction mode - has instruction, no selection
            let contextSection = formatContext(context)
            prompt = instructionTemplate
                .replacingOccurrences(of: "{{SYSTEM_PROMPT}}", with: systemPrompt)
                .replacingOccurrences(of: "{{CONTEXT}}", with: contextSection)
                .replacingOccurrences(of: "{{INSTRUCTION}}", with: instruction)

        case .selectionNoInstruction:
            // Has selection but no instruction - default to summarization behavior
            prompt = buildSelectionPrompt(context: context, instruction: "Summarize this text concisely")
        }

        logPrompt(prompt, mode: mode)
        return prompt
    }

    /// Build prompt for selection-based modes (transform or no-instruction)
    /// Uses the same context formatting as summarization (source info + metadata, no preceding/succeeding text)
    private func buildSelectionPrompt(context: Context, instruction: String) -> String {
        // Build context section similar to summarization - includes source info and metadata
        let contextSection = formatContextForSummarization(context.source, context: context)

        return selectionTransformTemplate
            .replacingOccurrences(of: "{{SYSTEM_PROMPT}}", with: systemPrompt)
            .replacingOccurrences(of: "{{SELECTED_TEXT}}", with: context.selectedText ?? "")
            .replacingOccurrences(of: "{{CONTEXT}}", with: contextSection)
            .replacingOccurrences(of: "{{INSTRUCTION}}", with: instruction)
    }

    /// Log prompt details (controlled by debugLogging flag)
    private func logPrompt(_ prompt: String, mode: PromptMode) {
        guard debugLogging else { return }
        print("\n" + String(repeating: "=", count: 80))
        print("📝 BUILT PROMPT (mode: \(mode.rawValue))")
        print(String(repeating: "=", count: 80))
        print(prompt)
        print(String(repeating: "=", count: 80) + "\n")
    }
    
    // MARK: - Summarization Methods

    /// Build a prompt for summarization
    /// - Parameters:
    ///   - request: The summary request containing text and options
    /// - Returns: Formatted prompt string
    func buildSummarizationPrompt(request: SummaryRequest) -> String {
        // Build context section (source info + metadata, NO preceding/succeeding text, NO selected text)
        let contextSection = formatContextForSummarization(request.source, context: request.surroundingContext)

        let prompt = summarizationTemplate
            .replacingOccurrences(of: "{{SYSTEM_PROMPT}}", with: systemPrompt)
            .replacingOccurrences(of: "{{SELECTED_TEXT}}", with: request.text)
            .replacingOccurrences(of: "{{CONTEXT}}", with: contextSection)
            .replacingOccurrences(of: "{{FORMAT_INSTRUCTION}}", with: request.format.promptInstruction)
            .replacingOccurrences(of: "{{LENGTH_INSTRUCTION}}", with: request.length.promptInstruction)

        logSummarizationPrompt(prompt, format: request.format, length: request.length)
        return prompt
    }

    /// Format context for summarization - includes source info and metadata, but NOT preceding/succeeding text
    private func formatContextForSummarization(_ source: ContextSource, context: Context?) -> String {
        var sections: [String] = []

        // Source information (app name, window title, URL)
        let sourceToUse = context?.source ?? source
        sections.append(formatSource(sourceToUse))

        // App-specific metadata (if available)
        if let context = context {
            let metadataSection = formatMetadata(context.metadata)
            if !metadataSection.isEmpty {
                sections.append(metadataSection)
            }
        }

        return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Log summarization prompt details (controlled by debugLogging flag)
    private func logSummarizationPrompt(_ prompt: String, format: SummaryFormat, length: SummaryLength) {
        guard debugLogging else { return }
        print("\n" + String(repeating: "=", count: 80))
        print("📝 BUILT SUMMARIZATION PROMPT (format: \(format.rawValue), length: \(length.rawValue))")
        print(String(repeating: "=", count: 80))
        print(prompt)
        print(String(repeating: "=", count: 80) + "\n")
    }

    // MARK: - Chat Support

    /// Build a system prompt for chat mode
    /// - Parameter context: Optional context to include in system prompt
    /// - Returns: Formatted system prompt for chat
    func buildChatSystemPrompt(context: Context?) -> String {
        var contextInfo = ""

        if let context = context {
            var parts: [String] = []

            // Source info
            parts.append("Application: \(context.source.applicationName)")
            if let windowTitle = context.source.windowTitle, !windowTitle.isEmpty {
                parts.append("Window: \(windowTitle)")
            }
            if let url = context.source.url {
                parts.append("URL: \(url.absoluteString)")
            }

            // Selected text (already truncated at capture time in Context.swift)
            if let selectedText = context.selectedText, !selectedText.isEmpty {
                parts.append("Original Selected Text: \"\(selectedText)\"")
            }

            contextInfo = parts.joined(separator: "\n")
        } else {
            contextInfo = "(No specific context)"
        }

        let prompt = chatSystemPromptTemplate.replacingOccurrences(of: "{{CONTEXT}}", with: contextInfo)
        logChatSystemPrompt(prompt)
        return prompt
    }

    /// Log chat system prompt (controlled by debugLogging flag)
    private func logChatSystemPrompt(_ prompt: String) {
        guard debugLogging else { return }
        print("\n" + String(repeating: "=", count: 80))
        print("💬 BUILT CHAT SYSTEM PROMPT")
        print(String(repeating: "=", count: 80))
        print(prompt)
        print(String(repeating: "=", count: 80) + "\n")
    }

    /// Format chat messages for provider API
    /// - Parameters:
    ///   - messages: Array of chat messages
    ///   - context: Optional context for system prompt
    /// - Returns: Array of message dictionaries formatted for API
    func formatChatMessages(messages: [ChatMessage], context: Context?) -> [[String: String]] {
        var result: [[String: String]] = []

        // Add system message with context
        let systemPrompt = buildChatSystemPrompt(context: context)
        result.append(["role": "system", "content": systemPrompt])

        // Add conversation messages
        for message in messages {
            result.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        logChatMessages(result)
        return result
    }

    /// Log full chat messages being sent (controlled by debugLogging flag)
    private func logChatMessages(_ messages: [[String: String]]) {
        guard debugLogging else { return }
        print("\n" + String(repeating: "-", count: 80))
        print("💬 CHAT MESSAGES (\(messages.count) total):")
        print(String(repeating: "-", count: 80))
        for (index, message) in messages.enumerated() {
            let role = message["role"] ?? "unknown"
            let content = message["content"] ?? ""
            print("[\(index)] \(role.uppercased()):")
            print(content)
            print("")
        }
        print(String(repeating: "-", count: 80) + "\n")
    }

    // MARK: - Context Formatting

    private func formatContext(_ context: Context) -> String {
        var sections: [String] = []

        // Source information
        sections.append(formatSource(context.source))

        // Preceding/succeeding text (only include if present - typically nil since clipboard capture was removed)
        if let preceding = context.precedingText, !preceding.isEmpty {
            sections.append(formatPrecedingText(preceding))
        }
        if let succeeding = context.succeedingText, !succeeding.isEmpty {
            sections.append(formatSucceedingText(succeeding))
        }

        // App-specific metadata
        sections.append(formatMetadata(context.metadata))

        return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func formatSource(_ source: ContextSource) -> String {
        var lines = ["[Source Information]"]
        lines.append("Application: \(source.applicationName)")

        if let windowTitle = source.windowTitle, !windowTitle.isEmpty {
            lines.append("Window: \(windowTitle)")
        }

        if let url = source.url {
            lines.append("URL: \(url.absoluteString)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatPrecedingText(_ text: String) -> String {
        // Note: text is already truncated at capture time in Context.swift
        return """
        [Preceding Text - BEFORE Cursor]
        \"\"\"
        \(text)
        \"\"\"
        """
    }

    private func formatSucceedingText(_ text: String) -> String {
        // Note: text is already truncated at capture time in Context.swift
        return """
        [Succeeding Text - AFTER Cursor]
        \"\"\"
        \(text)
        \"\"\"
        """
    }

    // MARK: - Metadata Formatting
    
    private func formatMetadata(_ metadata: ContextMetadata) -> String {
        switch metadata {
        case .slack(let slackMeta):
            return formatSlackMetadata(slackMeta)
        case .gmail(let gmailMeta):
            return formatGmailMetadata(gmailMeta)
        case .github(let githubMeta):
            return formatGitHubMetadata(githubMeta)
        case .generic(let genericMeta):
            return formatGenericMetadata(genericMeta)
        }
    }
    
    private func formatSlackMetadata(_ meta: SlackMetadata) -> String {
        var lines = ["[Slack Context]"]
        
        if let channel = meta.channelName {
            lines.append("Channel: \(channel) (\(meta.channelType.rawValue))")
        }
        
        if !meta.participants.isEmpty {
            lines.append("Participants: \(meta.participants.joined(separator: ", "))")
        }
        
        if meta.threadId != nil {
            lines.append("In thread reply")
        }
        
        if !meta.recentMessages.isEmpty {
            lines.append("\nRecent Messages:")
            for msg in meta.recentMessages.suffix(5) {
                lines.append("  \(msg.sender): \(msg.content)")
            }
        }
        
        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }
    
    private func formatGmailMetadata(_ meta: GmailMetadata) -> String {
        var lines = ["[Email Context]"]
        
        if let subject = meta.subject {
            lines.append("Subject: \(subject)")
        }
        
        if !meta.recipients.isEmpty {
            lines.append("To: \(meta.recipients.joined(separator: ", "))")
        }
        
        if !meta.ccRecipients.isEmpty {
            lines.append("CC: \(meta.ccRecipients.joined(separator: ", "))")
        }
        
        if let sender = meta.originalSender {
            lines.append("From: \(sender)")
        }
        
        if meta.isComposing {
            lines.append("Status: Composing new email")
        }
        
        if let draft = meta.draftContent, !draft.isEmpty {
            lines.append("\nDraft Content:\n\"\"\"\n\(draft)\n\"\"\"")
        }
        
        if !meta.threadMessages.isEmpty {
            lines.append("\nEmail Thread:")
            for msg in meta.threadMessages.suffix(3) {
                lines.append("  From \(msg.sender): \(msg.content.prefix(200))...")
            }
        }

        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    private func formatGitHubMetadata(_ meta: GitHubMetadata) -> String {
        var lines = ["[GitHub Context]"]

        if let repo = meta.repoName {
            lines.append("Repository: \(repo)")
        }

        if let prNum = meta.prNumber, let prTitle = meta.prTitle {
            lines.append("PR #\(prNum): \(prTitle)")
        }

        if let base = meta.baseBranch, let head = meta.headBranch {
            lines.append("Branches: \(head) → \(base)")
        }

        if let desc = meta.prDescription, !desc.isEmpty {
            lines.append("\nPR Description:\n\"\"\"\n\(desc.prefix(500))\n\"\"\"")
        }

        if !meta.changedFiles.isEmpty {
            lines.append("\nChanged Files: \(meta.changedFiles.prefix(10).joined(separator: ", "))")
        }

        if !meta.comments.isEmpty {
            lines.append("\nRecent Comments:")
            for comment in meta.comments.suffix(3) {
                lines.append("  @\(comment.author): \(comment.body.prefix(150))...")
            }
        }

        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }
    
    private func formatGenericMetadata(_ meta: GenericMetadata) -> String {
        var lines: [String] = []
        
        if let role = meta.focusedElementRole {
            lines.append("Focused Element: \(role)")
        }
        
        if let label = meta.focusedElementLabel, !label.isEmpty {
            lines.append("Element Label: \(label)")
        }
        
        return lines.isEmpty ? "" : "[UI Context]\n" + lines.joined(separator: "\n")
    }
}

