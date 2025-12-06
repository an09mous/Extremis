// MARK: - Prompt Builder
// Centralized prompt construction from templates

import Foundation

/// Builds prompts from templates with context and instruction placeholders
final class PromptBuilder {
    
    // MARK: - Singleton
    
    static let shared = PromptBuilder()
    private init() {}
    
    // MARK: - Main Template

    /// The main prompt template with placeholders:
    /// - {{SYSTEM_PROMPT}} - System instructions for the LLM
    /// - {{CONTEXT}} - Formatted context information
    /// - {{INSTRUCTION}} - User's instruction
    private let mainTemplate = """
{{SYSTEM_PROMPT}}

Context: {{CONTEXT}}

User Instruction: {{INSTRUCTION}}

Please provide a helpful response based on the context and instruction above. Be concise and direct.
"""

    /// Autocomplete template - used when no instruction is provided
    private let autocompleteTemplate = """
{{SYSTEM_PROMPT}}

Context: {{CONTEXT}}

## AUTOCOMPLETE MODE
The user has pressed Enter without providing any instruction. This means they want you to **autocomplete** or **continue** whatever text is in the surrounding context.

Your task:
1. Analyze the surrounding context carefully
2. Determine what the user is likely trying to write next
3. Generate a natural continuation of the text
4. Match the exact style, tone, and format of the existing content

Rules:
- Do NOT add any explanations or metadata
- Since it's an autocomplete request, make sure you are adding appropriate spaces, new lines or punctuation as needed to make the continuation flow naturally
- Do NOT repeat what's already written
- Just provide the next logical text that should follow
- If it's a message, complete the message naturally
- If it's code, complete the code logically
- If it's an email, continue the email appropriately
- Keep the continuation concise and relevant
"""
    
    // MARK: - System Prompts

    private let systemPrompt = """
You are Extremis, a context-aware writing assistant integrated into macOS. Your role is to help users write, edit, and improve text based on the context of what they're working on.

## How Context is Captured
When the user activates Extremis, it captures context differently based on the application:

### For Browsers (Chrome, Safari, Arc, Comet, etc.)
1. **Surrounding Text**: Captured via clipboard - the text before the cursor where the user is typing (using Cmd+Shift+Up to select, then Cmd+C to copy)
2. **Page Content**: Extracted via macOS Accessibility APIs from the browser's AXWebArea - includes headings, paragraphs, links, buttons, and form inputs visible on the page
3. **Window Title**: Usually contains the page title
4. **Focused Element**: The input field or text area where the user is typing

### For Desktop Apps (Slack, etc.)
1. **Surrounding Text**: Captured via clipboard from the focused text area
2. **App-Specific Metadata**: Channel names, participants, recent messages, etc.

### For Other Apps
1. **Visible Content**: Captured using Cmd+Shift+Up, Cmd+C (select text before cursor, copy)
2. **Focused Element**: Information about the UI element being edited

The "Surrounding Context" contains the text the user was writing when they activated Extremis. If available, "[Page Content]" section contains additional context from the visible page.

## Strict Guidelines
- Be concise and direct in your responses
- Match the tone and style of the surrounding context when appropriate
- Use the surrounding context and page content to understand what the user is working on
- Provide only the requested content without extra explanations or metadata. Just the text to be inserted.
- When generating text to be inserted, provide just the text without markdown formatting or code blocks
- If the context is from a messaging app (Slack, WhatsApp, Gmail, etc.), match the conversational tone
- If the context is from an email or professional site, match professional conventions
- If the context is code or a technical site (GitHub, Stack Overflow), maintain technical accuracy
- If page content includes form fields or inputs, understand the user may be filling out a form
"""
    
    // MARK: - Public Methods

    /// Check if instruction is empty (autocomplete mode)
    func isAutocompleteMode(instruction: String) -> Bool {
        return instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Build a complete prompt from instruction and context
    /// If instruction is empty, uses autocomplete mode
    func buildPrompt(instruction: String, context: Context) -> String {
        let contextSection = formatContext(context)
        let isAutocomplete = isAutocompleteMode(instruction: instruction)
        print("📋 PromptBuilder: context = \(context)")

        if isAutocomplete {
            // Autocomplete mode - no instruction provided
            return autocompleteTemplate
                .replacingOccurrences(of: "{{SYSTEM_PROMPT}}", with: systemPrompt)
                .replacingOccurrences(of: "{{CONTEXT}}", with: contextSection)
        } else {
            // Standard mode - instruction provided
            return mainTemplate
                .replacingOccurrences(of: "{{SYSTEM_PROMPT}}", with: systemPrompt)
                .replacingOccurrences(of: "{{CONTEXT}}", with: contextSection)
                .replacingOccurrences(of: "{{INSTRUCTION}}", with: instruction)
        }
    }
    
    // MARK: - Context Formatting
    
    private func formatContext(_ context: Context) -> String {
        var sections: [String] = []

        // Source information
        sections.append(formatSource(context.source))

        // Surrounding text (captured via Cmd+A, Cmd+C)
        if let surroundingText = context.surroundingText, !surroundingText.isEmpty {
            sections.append(formatSurroundingText(surroundingText))
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

    private func formatSurroundingText(_ text: String) -> String {
        // Truncate if too long
        let maxLength = 2000
        let truncatedText = text.count > maxLength 
            ? String(text.prefix(maxLength)) + "... [truncated]"
            : text
        
        return """
        [Surrounding Context]
        \"\"\"
        \(truncatedText)
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

