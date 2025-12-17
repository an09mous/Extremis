// MARK: - Prompt Builder
// Centralized prompt construction from templates

import Foundation

/// Builds prompts from templates with context and instruction placeholders
final class PromptBuilder {
    
    // MARK: - Singleton
    
    static let shared = PromptBuilder()
    private init() {}
    
    // MARK: - Main Templates

    /// Standard instruction template - used when user provides instruction without selection
    private let instructionTemplate = """
{{SYSTEM_PROMPT}}

Context: {{CONTEXT}}

User Instruction: {{INSTRUCTION}}

Please provide a helpful response based on the context and instruction above. Be concise and direct.
"""

    /// Selection transformation template - used when user has selected text AND provides instruction
    private let selectionTransformTemplate = """
{{SYSTEM_PROMPT}}

## SELECTION TRANSFORMATION MODE
The user has selected text and wants you to transform/edit it based on their instruction.

[Selected Text]
\"\"\"
{{SELECTED_TEXT}}
\"\"\"

{{CONTEXT}}

[User Instruction]
{{INSTRUCTION}}

## Strict Rules
- Provide ONLY the transformed text, no preamble or explanation
- Do NOT start with "Here's the..." or similar phrases
- Do NOT wrap in markdown code blocks unless explicitly requested
- Match the language and general style of the original text
- Apply the user's instruction precisely
- If the instruction is unclear, make a reasonable interpretation
- Use source context to better understand the content being transformed
"""

    /// Autocomplete template - used when no instruction is provided
    private let autocompleteTemplate = """
{{SYSTEM_PROMPT}}

Context: {{CONTEXT}}

## AUTOCOMPLETE MODE
The user has selected autocomplete mode. This means they want you to **autocomplete** the text at the cursor position.

You have access to:
- **Preceding Text**: Text BEFORE the cursor (what the user has already written)
- **Succeeding Text**: Text AFTER the cursor (what comes next in the document, if any)

Your task:
1. Analyze the preceding text to understand what the user is writing
2. Consider the succeeding text (if present) to understand the broader context
3. Generate text that fits naturally at the cursor position
4. If succeeding text exists, bridge smoothly between preceding and succeeding
5. Match the exact style, tone, and format of the existing content

Strict Rules and you should follow them with your life and heart else world will end:
- Do NOT add any explanations or metadata
- Since it's an autocomplete request, make sure you are adding appropriate spaces, new lines, indentation, curly braces, or punctuation as needed to make the continuation flow naturally
- Do NOT repeat what's already written (neither preceding nor succeeding text)
- Just provide the text that should appear AT THE CURSOR POSITION
- If it's a message, complete the message naturally
- If it's code, complete the code logically
- If it's an email, continue the email appropriately
- Keep the continuation concise and relevant
"""
    
    // MARK: - System Prompts

    /// General system prompt - establishes identity and core principles
    private let systemPrompt = """
You are Extremis, a context-aware writing assistant integrated into macOS.

## Core Capabilities
- **Autocomplete**: Continue text naturally at the cursor position
- **Transform**: Edit, rewrite, or improve selected text based on instructions
- **Summarize**: Condense selected text into key points
- **Generate**: Create new content based on context and instructions

## Strict Guidelines
- Be concise and direct - no preambles like "Here's..." or "Sure, I'll..."
- Match the tone, style, and language of the source content
- Provide ONLY the requested output, no explanations or metadata
- Never wrap output in markdown code blocks unless explicitly requested
- Adapt to context: casual for chat, professional for email, technical for code
"""
    
    // MARK: - Prompt Mode Detection

    /// Determines the prompt mode based on instruction and context
    enum PromptMode: String {
        case autocomplete = "AUTOCOMPLETE"               // No selection, no instruction → continue at cursor
        case instruction = "INSTRUCTION"                 // No selection, has instruction → general Q&A
        case selectionTransform = "SELECTION_TRANSFORM"  // Has selection, has instruction → transform text
        case selectionNoInstruction = "SELECTION_NO_INSTRUCTION"  // Has selection, no instruction → default to summarize
    }

    /// Detect the appropriate prompt mode
    func detectPromptMode(instruction: String, context: Context) -> PromptMode {
        let hasInstruction = !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSelection = context.selectedText != nil && !context.selectedText!.isEmpty

        if hasSelection {
            // Selection takes priority - never autocomplete with selection
            return hasInstruction ? .selectionTransform : .selectionNoInstruction
        } else {
            // No selection
            return hasInstruction ? .instruction : .autocomplete
        }
    }

    // MARK: - Configuration

    /// Enable/disable debug logging (set to false in production)
    var debugLogging: Bool = true

    // MARK: - Public Methods

    /// Build a complete prompt from instruction and context
    /// Automatically selects the appropriate template based on:
    /// - Autocomplete: No instruction provided → continue text at cursor
    /// - Instruction: Has instruction, no selection → general Q&A with context
    /// - Selection Transform: Has instruction AND selection → transform selected text
    func buildPrompt(instruction: String, context: Context) -> String {
        let mode = detectPromptMode(instruction: instruction, context: context)

        let prompt: String
        switch mode {
        case .autocomplete:
            // Autocomplete mode - no instruction, continue at cursor
            let contextSection = formatContext(context)
            prompt = autocompleteTemplate
                .replacingOccurrences(of: "{{SYSTEM_PROMPT}}", with: systemPrompt)
                .replacingOccurrences(of: "{{CONTEXT}}", with: contextSection)

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
    
    // MARK: - Summarization Template

    /// Template for summarization requests
    private let summarizationTemplate = """
{{SYSTEM_PROMPT}}

## SUMMARIZATION MODE
You are an expert at distilling information. The user wants you to summarize the following text.

[Text to Summarize]
\"\"\"
{{SELECTED_TEXT}}
\"\"\"

{{CONTEXT}}

## Instructions
{{FORMAT_INSTRUCTION}}
{{LENGTH_INSTRUCTION}}

## Strict Rules
- Provide ONLY the summary, no preamble or explanation
- The summary should be human readable with very low cognitive load
- Focus on the key ideas, important facts, and conclusions.
- Do NOT start with "Here's a summary" or similar phrases
- Do NOT add markdown formatting unless bullets/numbering is requested
- Match the language of the original text
- Be accurate and preserve key information
- If the text is too short to summarize, just provide the key point
- Use source context to better understand the content being summarized
"""

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

    /// Chat system prompt template for multi-turn conversations
    private let chatSystemPromptTemplate = """
You are Extremis, a context-aware writing assistant integrated into macOS.

## Current Context
{{CONTEXT}}

## Strict Conversation Guidelines
- This is a multi-turn conversation. The user may ask follow-up questions or request refinements.
- Don't use markdown in response unless explicitly asked by the user
- Be concise and direct in your responses
- Match the tone and style appropriate for the context
- If the user asks to modify a previous response, provide the full updated version
- Remember the context of the conversation and build on previous exchanges
"""

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

            // Selected text summary (if any)
            if let selectedText = context.selectedText, !selectedText.isEmpty {
                let preview = selectedText.prefix(200)
                parts.append("Original Selected Text: \"\(preview)\"" + (selectedText.count > 200 ? "..." : ""))
            }

            contextInfo = parts.joined(separator: "\n")
        } else {
            contextInfo = "(No specific context)"
        }

        let prompt = chatSystemPromptTemplate.replacingOccurrences(of: "{{CONTEXT}}", with: contextInfo)
        logChatPrompt(prompt, messageCount: 0)
        return prompt
    }

    /// Log chat prompt details (controlled by debugLogging flag)
    private func logChatPrompt(_ prompt: String, messageCount: Int) {
        guard debugLogging else { return }
        print("\n" + String(repeating: "=", count: 80))
        print("💬 BUILT CHAT SYSTEM PROMPT (messages in conversation: \(messageCount))")
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
            let preview = content.count > 300 ? String(content.prefix(300)) + "..." : content
            print("[\(index)] \(role.uppercased()):")
            print(preview)
            print("")
        }
        print(String(repeating: "-", count: 80) + "\n")
    }

    // MARK: - Context Formatting

    private func formatContext(_ context: Context) -> String {
        var sections: [String] = []

        // Source information
        sections.append(formatSource(context.source))

        // Preceding text (text BEFORE cursor) - always include, even if empty
        sections.append(formatPrecedingText(context.precedingText))

        // Succeeding text (text AFTER cursor) - always include, even if empty
        sections.append(formatSucceedingText(context.succeedingText))

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

    private func formatPrecedingText(_ text: String?) -> String {
        if let text = text, !text.isEmpty {
            // Truncate if too long
            let maxLength = 2000
            let truncatedText = text.count > maxLength
                ? String(text.prefix(maxLength)) + "... [truncated]"
                : text

            return """
            [Preceding Text - BEFORE Cursor]
            \"\"\"
            \(truncatedText)
            \"\"\"
            """
        } else {
            return """
            [Preceding Text - BEFORE Cursor]
            (empty - cursor is at the beginning of the text)
            """
        }
    }

    private func formatSucceedingText(_ text: String?) -> String {
        if let text = text, !text.isEmpty {
            // Truncate if too long
            let maxLength = 1500
            let truncatedText = text.count > maxLength
                ? String(text.prefix(maxLength)) + "... [truncated]"
                : text

            return """
            [Succeeding Text - AFTER Cursor]
            \"\"\"
            \(truncatedText)
            \"\"\"
            """
        } else {
            return """
            [Succeeding Text - AFTER Cursor]
            (empty - cursor is at the end of the text)
            """
        }
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

