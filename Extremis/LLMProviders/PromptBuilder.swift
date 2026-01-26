// MARK: - Prompt Builder
// Centralized prompt construction from templates

import Foundation

// NOTE: Context text truncation is now handled at capture time in Context.swift
// See kContextMax*Length constants there. This ensures storage efficiency and
// prevents duplicate truncation logic.

/// Builds prompts from templates with context and instruction placeholders
@MainActor
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

    /// System prompt template loaded from file
    private var systemPromptTemplate: String {
        try! templateLoader.load(.system)
    }

    // MARK: - Configuration

    /// Enable/disable debug logging (set to false in production)
    var debugLogging: Bool = true

    // MARK: - System Prompt

    /// Build the system prompt (context is now per-message, not in system prompt)
    /// - Returns: Formatted system prompt
    func buildSystemPrompt() -> String {
        let prompt = systemPromptTemplate
        logSystemPrompt(prompt)
        return prompt
    }

    /// Log system prompt (controlled by debugLogging flag)
    private func logSystemPrompt(_ prompt: String) {
        guard debugLogging else { return }
        print("\n" + String(repeating: "=", count: 80))
        print("💬 BUILT SYSTEM PROMPT")
        print(String(repeating: "=", count: 80))
        print(prompt)
        print(String(repeating: "=", count: 80) + "\n")
    }

    /// Format a user message with inline context block and intent-based prompt injection
    /// - Parameters:
    ///   - content: The user's message content
    ///   - context: Optional context to include inline
    ///   - intent: Optional message intent for prompt injection (transforms, summarization, etc.)
    /// - Returns: Formatted message content with context and injected rules
    func formatUserMessageWithContext(_ content: String, context: Context?, intent: MessageIntent? = nil) -> String {
        guard let context = context else {
            return content
        }

        var parts: [String] = []

        // Build context block
        var contextLines: [String] = ["[Context]"]
        contextLines.append("Application: \(context.source.applicationName)")

        if let windowTitle = context.source.windowTitle, !windowTitle.isEmpty {
            contextLines.append("Window: \(windowTitle)")
        }

        if let url = context.source.url {
            contextLines.append("URL: \(url.absoluteString)")
        }

        // Add metadata if present
        let metadataSection = formatMetadata(context.metadata)
        if !metadataSection.isEmpty {
            contextLines.append(metadataSection)
        }

        // Add selected text if present
        if let selectedText = context.selectedText, !selectedText.isEmpty {
            contextLines.append("")
            contextLines.append("Selected Text:")
            contextLines.append("\"\"\"")
            contextLines.append(selectedText)
            contextLines.append("\"\"\"")
        }

        parts.append(contextLines.joined(separator: "\n"))

        // Add the user message/instruction with appropriate intent template
        parts.append("")
        let template = templateForIntent(intent)
        parts.append(getIntentTemplate(template, content: content))

        return parts.joined(separator: "\n")
    }

    /// Map MessageIntent to the corresponding PromptTemplate
    private func templateForIntent(_ intent: MessageIntent?) -> PromptTemplate {
        switch intent {
        case .selectionTransform:
            return .intentInstruct
        case .summarize:
            return .intentSummarize
        case .chat, .followUp, .none:
            return .intentChat
        }
    }

    /// Get the intent template with content placeholder replaced
    private func getIntentTemplate(_ template: PromptTemplate, content: String) -> String {
        do {
            let templateContent = try templateLoader.load(template)
            return templateContent.replacingOccurrences(of: "{{CONTENT}}", with: content)
        } catch {
            print("⚠️ Failed to load intent template \(template): \(error)")
            return content  // Fallback to just the content
        }
    }

    /// Format chat messages for provider API with per-message context
    /// - Parameters:
    ///   - messages: Array of chat messages (each may have embedded context)
    /// - Returns: Array of message dictionaries formatted for API
    ///
    /// Note: This returns simple string-based messages. Assistant messages with toolRounds
    /// are included with their text content only. The provider's tool request builder
    /// must handle expanding toolRounds inline for each assistant message that has them.
    func formatChatMessages(messages: [ChatMessage]) -> [[String: String]] {
        var result: [[String: String]] = []

        // Add system message (context is now per-message, not in system prompt)
        let systemPrompt = buildSystemPrompt()
        result.append(["role": "system", "content": systemPrompt])

        // Add conversation messages with inline context and intent injection for user messages
        for message in messages {
            if message.role == .user {
                // Use context and intent embedded in the message for prompt injection
                let formattedContent = formatUserMessageWithContext(
                    message.content,
                    context: message.context,
                    intent: message.intent
                )
                result.append([
                    "role": message.role.rawValue,
                    "content": formattedContent
                ])
            } else if message.role == .assistant {
                // All assistant messages included - providers handle toolRounds expansion
                result.append([
                    "role": message.role.rawValue,
                    "content": message.content
                ])
            } else {
                // System messages pass through unchanged
                result.append([
                    "role": message.role.rawValue,
                    "content": message.content
                ])
            }
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
