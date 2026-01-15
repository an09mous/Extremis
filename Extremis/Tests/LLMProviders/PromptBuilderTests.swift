// MARK: - PromptBuilder Unit Tests
// Tests for intent-based prompt injection framework
// Run: swiftc -parse-as-library -o /tmp/PromptBuilderTests PromptBuilderTests.swift && /tmp/PromptBuilderTests

import Foundation

// MARK: - Test Runner

/// Simple test framework for running without XCTest
struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ testName: String, file: String = #file, line: Int = #line) {
        if actual == expected {
            passedCount += 1
            print("✅ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected '\(expected)' but got '\(actual)'"
            failedTests.append((testName, message))
            print("❌ \(testName): \(message)")
        }
    }

    static func assertNil<T>(_ value: T?, _ testName: String, file: String = #file, line: Int = #line) {
        if value == nil {
            passedCount += 1
            print("✅ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected nil but got '\(value!)'"
            failedTests.append((testName, message))
            print("❌ \(testName): \(message)")
        }
    }

    static func assertTrue(_ condition: Bool, _ testName: String, file: String = #file, line: Int = #line) {
        if condition {
            passedCount += 1
            print("✅ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected true but got false"
            failedTests.append((testName, message))
            print("❌ \(testName): \(message)")
        }
    }

    static func assertFalse(_ condition: Bool, _ testName: String, file: String = #file, line: Int = #line) {
        assertTrue(!condition, testName, file: file, line: line)
    }

    static func printSummary() {
        print("\n" + String(repeating: "=", count: 50))
        print("TEST SUMMARY")
        print(String(repeating: "=", count: 50))
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")

        if !failedTests.isEmpty {
            print("\nFailed Tests:")
            for (name, message) in failedTests {
                print("  • \(name): \(message)")
            }
        }
        print(String(repeating: "=", count: 50))
    }

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
    }
}

// MARK: - Type Stubs for Testing
// Minimal type definitions that mirror the actual types for testing

enum ChatRole: String, Codable, Equatable {
    case system
    case user
    case assistant
}

enum MessageIntent: String, Codable, Equatable {
    case chat
    case selectionTransform
    case summarize
    case followUp
}

struct ContextSource: Codable, Equatable {
    let applicationName: String
    let bundleIdentifier: String
    var windowTitle: String?
    var url: URL?

    init(applicationName: String, bundleIdentifier: String, windowTitle: String? = nil, url: URL? = nil) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.url = url
    }
}

enum SlackChannelType: String, Codable {
    case channel
    case directMessage
    case group
}

struct SlackMessage: Codable, Equatable {
    let sender: String
    let content: String
}

struct SlackMetadata: Codable, Equatable {
    var channelName: String?
    var channelType: SlackChannelType
    var participants: [String]
    var threadId: String?
    var recentMessages: [SlackMessage]

    init(channelName: String? = nil, channelType: SlackChannelType = .channel,
         participants: [String] = [], threadId: String? = nil, recentMessages: [SlackMessage] = []) {
        self.channelName = channelName
        self.channelType = channelType
        self.participants = participants
        self.threadId = threadId
        self.recentMessages = recentMessages
    }
}

struct GmailMessage: Codable, Equatable {
    let sender: String
    let content: String
}

struct GmailMetadata: Codable, Equatable {
    var subject: String?
    var recipients: [String]
    var ccRecipients: [String]
    var originalSender: String?
    var isComposing: Bool
    var draftContent: String?
    var threadMessages: [GmailMessage]

    init(subject: String? = nil, recipients: [String] = [], ccRecipients: [String] = [],
         originalSender: String? = nil, isComposing: Bool = false, draftContent: String? = nil, threadMessages: [GmailMessage] = []) {
        self.subject = subject
        self.recipients = recipients
        self.ccRecipients = ccRecipients
        self.originalSender = originalSender
        self.isComposing = isComposing
        self.draftContent = draftContent
        self.threadMessages = threadMessages
    }
}

struct GitHubComment: Codable, Equatable {
    let author: String
    let body: String
}

struct GitHubMetadata: Codable, Equatable {
    var repoName: String?
    var prNumber: Int?
    var prTitle: String?
    var baseBranch: String?
    var headBranch: String?
    var prDescription: String?
    var changedFiles: [String]
    var comments: [GitHubComment]
}

struct GenericMetadata: Codable, Equatable {
    var focusedElementRole: String?
    var focusedElementLabel: String?
}

enum ContextMetadata: Codable, Equatable {
    case slack(SlackMetadata)
    case gmail(GmailMetadata)
    case github(GitHubMetadata)
    case generic(GenericMetadata)
}

struct Context: Codable, Equatable {
    let source: ContextSource
    let selectedText: String?
    var metadata: ContextMetadata

    init(source: ContextSource, selectedText: String?, metadata: ContextMetadata = .generic(GenericMetadata())) {
        self.source = source
        self.selectedText = selectedText
        self.metadata = metadata
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    let context: Context?
    let intent: MessageIntent?

    init(id: UUID = UUID(), role: ChatRole, content: String, timestamp: Date = Date(),
         context: Context? = nil, intent: MessageIntent? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.context = context
        self.intent = intent
    }

    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content, intent: .followUp)
    }

    static func user(_ content: String, context: Context?, intent: MessageIntent = .chat) -> ChatMessage {
        ChatMessage(role: .user, content: content, context: context, intent: intent)
    }

    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }

    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }
}

// MARK: - Template Loading Stubs

enum PromptTemplate: String, CaseIterable {
    case system = "system"
    case intentInstruct = "intent_instruct"
    case intentSummarize = "intent_summarize"
    case intentChat = "intent_chat"
    case sessionSummarizationInitial = "session_summarization_initial"
    case sessionSummarizationUpdate = "session_summarization_update"

    var filename: String { rawValue }
}

enum PromptTemplateError: Error {
    case templateNotFound(PromptTemplate)
}

/// Mock template loader for testing
class PromptTemplateLoader {
    static let shared = PromptTemplateLoader()

    private var mockTemplates: [PromptTemplate: String] = [
        .intentChat: "[User Message]\n{{CONTENT}}\n",
        .intentInstruct: "[Instruction]\n{{CONTENT}}\n\n## Rules\n- Focus on the selected text when responding\n",
        .intentSummarize: "[Request]\nSummarize the selected text.\n\n## Rules\n- Provide ONLY the summary as output\n",
        .system: "You are a helpful assistant."
    ]

    func load(_ template: PromptTemplate) throws -> String {
        if let content = mockTemplates[template] {
            return content
        }
        throw PromptTemplateError.templateNotFound(template)
    }
}

// MARK: - PromptBuilder (Minimal Implementation for Testing)

final class PromptBuilder {
    static let shared = PromptBuilder()
    private let templateLoader: PromptTemplateLoader
    var debugLogging: Bool = false

    init(templateLoader: PromptTemplateLoader = .shared) {
        self.templateLoader = templateLoader
    }

    private var systemPromptTemplate: String {
        try! templateLoader.load(.system)
    }

    func buildSystemPrompt() -> String {
        return systemPromptTemplate
    }

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

    private func getIntentTemplate(_ template: PromptTemplate, content: String) -> String {
        do {
            let templateContent = try templateLoader.load(template)
            return templateContent.replacingOccurrences(of: "{{CONTENT}}", with: content)
        } catch {
            return content
        }
    }

    func formatChatMessages(messages: [ChatMessage]) -> [[String: String]] {
        var result: [[String: String]] = []

        let systemPrompt = buildSystemPrompt()
        result.append(["role": "system", "content": systemPrompt])

        for message in messages {
            if message.role == .user {
                let formattedContent = formatUserMessageWithContext(
                    message.content,
                    context: message.context,
                    intent: message.intent
                )
                result.append([
                    "role": message.role.rawValue,
                    "content": formattedContent
                ])
            } else {
                result.append([
                    "role": message.role.rawValue,
                    "content": message.content
                ])
            }
        }

        return result
    }

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

// MARK: - Test Suites

/// Tests for MessageIntent enum
struct MessageIntentTests {
    static func runAll() {
        print("\n📦 MessageIntent Tests")
        print(String(repeating: "-", count: 40))

        testEnumCases()
        testCodable()
        testEquatable()
    }

    static func testEnumCases() {
        let chat = MessageIntent.chat
        let transform = MessageIntent.selectionTransform
        let summarize = MessageIntent.summarize
        let followUp = MessageIntent.followUp

        TestRunner.assertEqual(chat.rawValue, "chat", "MessageIntent: chat rawValue")
        TestRunner.assertEqual(transform.rawValue, "selectionTransform", "MessageIntent: selectionTransform rawValue")
        TestRunner.assertEqual(summarize.rawValue, "summarize", "MessageIntent: summarize rawValue")
        TestRunner.assertEqual(followUp.rawValue, "followUp", "MessageIntent: followUp rawValue")
    }

    static func testCodable() {
        let intent = MessageIntent.selectionTransform
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        do {
            let data = try encoder.encode(intent)
            let decoded = try decoder.decode(MessageIntent.self, from: data)
            TestRunner.assertEqual(decoded, intent, "MessageIntent: Codable roundtrip")
        } catch {
            TestRunner.assertTrue(false, "MessageIntent: Codable roundtrip - encoding failed: \(error)")
        }
    }

    static func testEquatable() {
        TestRunner.assertTrue(MessageIntent.chat == MessageIntent.chat, "MessageIntent: Equatable same")
        TestRunner.assertFalse(MessageIntent.chat == MessageIntent.summarize, "MessageIntent: Equatable different")
    }
}

/// Tests for ChatMessage factory methods with intent
struct ChatMessageIntentTests {
    static func runAll() {
        print("\n📦 ChatMessage Intent Tests")
        print(String(repeating: "-", count: 40))

        testUserMessageWithFollowUpIntent()
        testUserMessageWithContext()
        testUserMessageWithContextAndIntent()
        testAssistantMessageHasNoIntent()
        testSystemMessageHasNoIntent()
    }

    static func testUserMessageWithFollowUpIntent() {
        let message = ChatMessage.user("Hello")
        TestRunner.assertEqual(message.role, .user, "ChatMessage.user: role is user")
        TestRunner.assertEqual(message.content, "Hello", "ChatMessage.user: content correct")
        TestRunner.assertEqual(message.intent, .followUp, "ChatMessage.user: default intent is followUp")
        TestRunner.assertNil(message.context, "ChatMessage.user: no context")
    }

    static func testUserMessageWithContext() {
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "Selected text"
        )
        let message = ChatMessage.user("Transform this", context: context)
        TestRunner.assertEqual(message.role, .user, "ChatMessage.user with context: role")
        TestRunner.assertEqual(message.intent, .chat, "ChatMessage.user with context: default intent is chat")
        TestRunner.assertTrue(message.context != nil, "ChatMessage.user with context: has context")
    }

    static func testUserMessageWithContextAndIntent() {
        let context = Context(
            source: ContextSource(applicationName: "Safari", bundleIdentifier: "com.apple.Safari"),
            selectedText: "Text to summarize"
        )
        let message = ChatMessage.user("Summarize", context: context, intent: .summarize)
        TestRunner.assertEqual(message.intent, .summarize, "ChatMessage.user with intent: intent correct")
        TestRunner.assertTrue(message.context != nil, "ChatMessage.user with intent: has context")
    }

    static func testAssistantMessageHasNoIntent() {
        let message = ChatMessage.assistant("Response")
        TestRunner.assertEqual(message.role, .assistant, "ChatMessage.assistant: role")
        TestRunner.assertNil(message.intent, "ChatMessage.assistant: no intent")
        TestRunner.assertNil(message.context, "ChatMessage.assistant: no context")
    }

    static func testSystemMessageHasNoIntent() {
        let message = ChatMessage.system("System prompt")
        TestRunner.assertEqual(message.role, .system, "ChatMessage.system: role")
        TestRunner.assertNil(message.intent, "ChatMessage.system: no intent")
        TestRunner.assertNil(message.context, "ChatMessage.system: no context")
    }
}

/// Tests for PromptBuilder intent-based formatting
struct PromptBuilderIntentTests {
    private let builder = PromptBuilder()

    init() {
        builder.debugLogging = false
    }

    func runAll() {
        print("\n📦 PromptBuilder Intent Tests")
        print(String(repeating: "-", count: 40))

        testFormatUserMessageWithContext_NoContext()
        testFormatUserMessageWithContext_WithContext()
        testFormatUserMessageWithContext_ChatIntent()
        testFormatUserMessageWithContext_TransformIntent()
        testFormatUserMessageWithContext_SummarizeIntent()
        testFormatUserMessageWithContext_FollowUpIntent()
        testFormatUserMessageWithContext_NilIntent()
    }

    func testFormatUserMessageWithContext_NoContext() {
        let result = builder.formatUserMessageWithContext("Hello", context: nil, intent: .chat)
        TestRunner.assertEqual(result, "Hello", "formatUserMessage: no context returns content")
    }

    func testFormatUserMessageWithContext_WithContext() {
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: nil
        )
        let result = builder.formatUserMessageWithContext("Hello", context: context, intent: .chat)
        TestRunner.assertTrue(result.contains("[Context]"), "formatUserMessage: has context block")
        TestRunner.assertTrue(result.contains("Application: Notes"), "formatUserMessage: has app name")
        TestRunner.assertTrue(result.contains("[User Message]"), "formatUserMessage: has chat intent header")
        TestRunner.assertTrue(result.contains("Hello"), "formatUserMessage: has content")
    }

    func testFormatUserMessageWithContext_ChatIntent() {
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: nil
        )
        let result = builder.formatUserMessageWithContext("What is this?", context: context, intent: .chat)
        TestRunner.assertTrue(result.contains("[User Message]"), "formatUserMessage chat: has [User Message]")
        TestRunner.assertTrue(result.contains("What is this?"), "formatUserMessage chat: has content")
    }

    func testFormatUserMessageWithContext_TransformIntent() {
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "Text to transform"
        )
        let result = builder.formatUserMessageWithContext("Make formal", context: context, intent: .selectionTransform)
        TestRunner.assertTrue(result.contains("[Instruction]"), "formatUserMessage transform: has [Instruction]")
        TestRunner.assertTrue(result.contains("Make formal"), "formatUserMessage transform: has instruction")
        TestRunner.assertTrue(result.contains("## Rules"), "formatUserMessage transform: has rules")
        TestRunner.assertTrue(result.contains("Focus on the selected text"), "formatUserMessage transform: has focus rule")
        TestRunner.assertTrue(result.contains("Selected Text:"), "formatUserMessage transform: has selected text label")
        TestRunner.assertTrue(result.contains("Text to transform"), "formatUserMessage transform: has selected text")
    }

    func testFormatUserMessageWithContext_SummarizeIntent() {
        let context = Context(
            source: ContextSource(applicationName: "Safari", bundleIdentifier: "com.apple.Safari"),
            selectedText: "Long article content here"
        )
        let result = builder.formatUserMessageWithContext("Summarize", context: context, intent: .summarize)
        TestRunner.assertTrue(result.contains("[Request]"), "formatUserMessage summarize: has [Request]")
        TestRunner.assertTrue(result.contains("Summarize the selected text"), "formatUserMessage summarize: has summarize request")
        TestRunner.assertTrue(result.contains("## Rules"), "formatUserMessage summarize: has rules")
        TestRunner.assertTrue(result.contains("Long article content here"), "formatUserMessage summarize: has selected text")
    }

    func testFormatUserMessageWithContext_FollowUpIntent() {
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: nil
        )
        let result = builder.formatUserMessageWithContext("What else?", context: context, intent: .followUp)
        TestRunner.assertTrue(result.contains("[User Message]"), "formatUserMessage followUp: has [User Message]")
        TestRunner.assertTrue(result.contains("What else?"), "formatUserMessage followUp: has content")
    }

    func testFormatUserMessageWithContext_NilIntent() {
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: nil
        )
        let result = builder.formatUserMessageWithContext("Hello", context: context, intent: nil)
        TestRunner.assertTrue(result.contains("[User Message]"), "formatUserMessage nil intent: defaults to chat")
    }
}

/// Tests for formatChatMessages output structure
struct FormatChatMessagesTests {
    private let builder = PromptBuilder()

    init() {
        builder.debugLogging = false
    }

    func runAll() {
        print("\n📦 formatChatMessages Tests")
        print(String(repeating: "-", count: 40))

        testEmptyMessages()
        testSingleUserMessage()
        testConversation()
        testUserMessageWithContext()
        testAssistantMessagePassthrough()
        testSystemPromptFirst()
    }

    func testEmptyMessages() {
        let result = builder.formatChatMessages(messages: [])
        TestRunner.assertEqual(result.count, 1, "formatChatMessages empty: has system message")
        TestRunner.assertEqual(result[0]["role"], "system", "formatChatMessages empty: first is system")
    }

    func testSingleUserMessage() {
        let messages = [ChatMessage.user("Hello")]
        let result = builder.formatChatMessages(messages: messages)
        TestRunner.assertEqual(result.count, 2, "formatChatMessages single: system + user")
        TestRunner.assertEqual(result[0]["role"], "system", "formatChatMessages single: first is system")
        TestRunner.assertEqual(result[1]["role"], "user", "formatChatMessages single: second is user")
    }

    func testConversation() {
        let messages = [
            ChatMessage.user("Hello"),
            ChatMessage.assistant("Hi there!"),
            ChatMessage.user("How are you?")
        ]
        let result = builder.formatChatMessages(messages: messages)
        TestRunner.assertEqual(result.count, 4, "formatChatMessages conversation: 1 system + 3 messages")
        TestRunner.assertEqual(result[0]["role"], "system", "formatChatMessages conversation: system first")
        TestRunner.assertEqual(result[1]["role"], "user", "formatChatMessages conversation: user second")
        TestRunner.assertEqual(result[2]["role"], "assistant", "formatChatMessages conversation: assistant third")
        TestRunner.assertEqual(result[3]["role"], "user", "formatChatMessages conversation: user fourth")
    }

    func testUserMessageWithContext() {
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "Selected"
        )
        let messages = [ChatMessage.user("Transform", context: context, intent: .selectionTransform)]
        let result = builder.formatChatMessages(messages: messages)

        let userContent = result[1]["content"] ?? ""
        TestRunner.assertTrue(userContent.contains("[Context]"), "formatChatMessages with context: has context block")
        TestRunner.assertTrue(userContent.contains("[Instruction]"), "formatChatMessages with context: has transform intent")
    }

    func testAssistantMessagePassthrough() {
        let messages = [
            ChatMessage.user("Hello"),
            ChatMessage.assistant("Complex response with **markdown** and `code`")
        ]
        let result = builder.formatChatMessages(messages: messages)
        let assistantContent = result[2]["content"] ?? ""
        TestRunner.assertEqual(assistantContent, "Complex response with **markdown** and `code`", "formatChatMessages: assistant passthrough")
    }

    func testSystemPromptFirst() {
        let messages = [ChatMessage.user("Test")]
        let result = builder.formatChatMessages(messages: messages)
        let systemContent = result[0]["content"] ?? ""
        TestRunner.assertTrue(!systemContent.isEmpty, "formatChatMessages: system prompt not empty")
    }
}

/// Tests for context formatting in user messages
struct ContextFormattingTests {
    private let builder = PromptBuilder()

    init() {
        builder.debugLogging = false
    }

    func runAll() {
        print("\n📦 Context Formatting Tests")
        print(String(repeating: "-", count: 40))

        testContextWithWindowTitle()
        testContextWithURL()
        testContextWithSelectedText()
        testContextWithAllFields()
        testContextWithSlackMetadata()
        testContextWithGmailMetadata()
    }

    func testContextWithWindowTitle() {
        let context = Context(
            source: ContextSource(
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                windowTitle: "My Document"
            ),
            selectedText: nil
        )
        let result = builder.formatUserMessageWithContext("Hello", context: context, intent: .chat)
        TestRunner.assertTrue(result.contains("Window: My Document"), "Context: window title included")
    }

    func testContextWithURL() {
        let context = Context(
            source: ContextSource(
                applicationName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                url: URL(string: "https://example.com/page")
            ),
            selectedText: nil
        )
        let result = builder.formatUserMessageWithContext("Hello", context: context, intent: .chat)
        TestRunner.assertTrue(result.contains("URL: https://example.com/page"), "Context: URL included")
    }

    func testContextWithSelectedText() {
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: "This is selected"
        )
        let result = builder.formatUserMessageWithContext("Hello", context: context, intent: .chat)
        TestRunner.assertTrue(result.contains("Selected Text:"), "Context: selected text label")
        TestRunner.assertTrue(result.contains("This is selected"), "Context: selected text content")
        TestRunner.assertTrue(result.contains("\"\"\""), "Context: triple quote delimiters")
    }

    func testContextWithAllFields() {
        let context = Context(
            source: ContextSource(
                applicationName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                windowTitle: "GitHub - Pull Request",
                url: URL(string: "https://github.com/org/repo/pull/123")
            ),
            selectedText: "Code to review"
        )
        let result = builder.formatUserMessageWithContext("Review", context: context, intent: .chat)
        TestRunner.assertTrue(result.contains("Application: Safari"), "Context all: app")
        TestRunner.assertTrue(result.contains("Window: GitHub - Pull Request"), "Context all: window")
        TestRunner.assertTrue(result.contains("URL: https://github.com"), "Context all: URL")
        TestRunner.assertTrue(result.contains("Code to review"), "Context all: selected text")
    }

    func testContextWithSlackMetadata() {
        let slackMeta = SlackMetadata(
            channelName: "general",
            channelType: .channel,
            participants: ["Alice", "Bob"],
            threadId: nil,
            recentMessages: []
        )
        let context = Context(
            source: ContextSource(applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap"),
            selectedText: nil,
            metadata: .slack(slackMeta)
        )
        let result = builder.formatUserMessageWithContext("Reply", context: context, intent: .chat)
        TestRunner.assertTrue(result.contains("[Slack Context]"), "Context Slack: has metadata block")
        TestRunner.assertTrue(result.contains("Channel: general"), "Context Slack: channel name")
        TestRunner.assertTrue(result.contains("Alice"), "Context Slack: participants")
    }

    func testContextWithGmailMetadata() {
        let gmailMeta = GmailMetadata(
            subject: "Meeting Tomorrow",
            recipients: ["team@example.com"],
            ccRecipients: [],
            originalSender: "boss@example.com",
            isComposing: false,
            draftContent: nil,
            threadMessages: []
        )
        let context = Context(
            source: ContextSource(applicationName: "Gmail", bundleIdentifier: "com.google.Chrome"),
            selectedText: nil,
            metadata: .gmail(gmailMeta)
        )
        let result = builder.formatUserMessageWithContext("Reply", context: context, intent: .chat)
        TestRunner.assertTrue(result.contains("[Email Context]"), "Context Gmail: has metadata block")
        TestRunner.assertTrue(result.contains("Subject: Meeting Tomorrow"), "Context Gmail: subject")
        TestRunner.assertTrue(result.contains("From: boss@example.com"), "Context Gmail: sender")
    }
}

/// Tests for edge cases and error handling
struct EdgeCaseTests {
    private let builder = PromptBuilder()

    init() {
        builder.debugLogging = false
    }

    func runAll() {
        print("\n📦 Edge Case Tests")
        print(String(repeating: "-", count: 40))

        testEmptyContent()
        testWhitespaceContent()
        testSpecialCharactersInContent()
        testUnicodeContent()
        testNewlinesInContent()
        testLongContent()
        testEmptySelectedText()
    }

    func testEmptyContent() {
        let result = builder.formatUserMessageWithContext("", context: nil, intent: .chat)
        TestRunner.assertEqual(result, "", "Edge: empty content returns empty")
    }

    func testWhitespaceContent() {
        let result = builder.formatUserMessageWithContext("   \n\t", context: nil, intent: .chat)
        TestRunner.assertEqual(result, "   \n\t", "Edge: whitespace content preserved")
    }

    func testSpecialCharactersInContent() {
        let content = "Code: `func test() { print(\"Hello\") }` and <html> & €£¥"
        let result = builder.formatUserMessageWithContext(content, context: nil, intent: .chat)
        TestRunner.assertTrue(result.contains(content), "Edge: special chars preserved")
    }

    func testUnicodeContent() {
        let content = "翻译成中文 🇨🇳 日本語"
        let result = builder.formatUserMessageWithContext(content, context: nil, intent: .chat)
        TestRunner.assertTrue(result.contains("翻译成中文"), "Edge: unicode Chinese")
        TestRunner.assertTrue(result.contains("🇨🇳"), "Edge: unicode emoji")
        TestRunner.assertTrue(result.contains("日本語"), "Edge: unicode Japanese")
    }

    func testNewlinesInContent() {
        let content = "Line 1\nLine 2\r\nLine 3"
        let result = builder.formatUserMessageWithContext(content, context: nil, intent: .chat)
        TestRunner.assertTrue(result.contains("Line 1"), "Edge: newline line 1")
        TestRunner.assertTrue(result.contains("Line 2"), "Edge: newline line 2")
        TestRunner.assertTrue(result.contains("Line 3"), "Edge: newline line 3")
    }

    func testLongContent() {
        let content = String(repeating: "A", count: 10000)
        let result = builder.formatUserMessageWithContext(content, context: nil, intent: .chat)
        TestRunner.assertTrue(result.contains(content), "Edge: long content preserved")
    }

    func testEmptySelectedText() {
        let context = Context(
            source: ContextSource(applicationName: "Notes", bundleIdentifier: "com.apple.Notes"),
            selectedText: ""
        )
        let result = builder.formatUserMessageWithContext("Hello", context: context, intent: .chat)
        TestRunner.assertFalse(result.contains("Selected Text:"), "Edge: empty selected text not shown")
    }
}

/// Tests for template-to-intent mapping
struct TemplateForIntentTests {
    static func runAll() {
        print("\n📦 Template For Intent Tests")
        print(String(repeating: "-", count: 40))

        testChatMapsToIntentChat()
        testFollowUpMapsToIntentChat()
        testNilMapsToIntentChat()
        testTransformMapsToIntentTransform()
        testSummarizeMapsToIntentSummarize()
    }

    static func testChatMapsToIntentChat() {
        let builder = PromptBuilder()
        let context = Context(
            source: ContextSource(applicationName: "Test", bundleIdentifier: "test"),
            selectedText: nil
        )
        let result = builder.formatUserMessageWithContext("test", context: context, intent: .chat)
        TestRunner.assertTrue(result.contains("[User Message]"), "templateForIntent: chat -> intentChat")
    }

    static func testFollowUpMapsToIntentChat() {
        let builder = PromptBuilder()
        let context = Context(
            source: ContextSource(applicationName: "Test", bundleIdentifier: "test"),
            selectedText: nil
        )
        let result = builder.formatUserMessageWithContext("test", context: context, intent: .followUp)
        TestRunner.assertTrue(result.contains("[User Message]"), "templateForIntent: followUp -> intentChat")
    }

    static func testNilMapsToIntentChat() {
        let builder = PromptBuilder()
        let context = Context(
            source: ContextSource(applicationName: "Test", bundleIdentifier: "test"),
            selectedText: nil
        )
        let result = builder.formatUserMessageWithContext("test", context: context, intent: nil)
        TestRunner.assertTrue(result.contains("[User Message]"), "templateForIntent: nil -> intentChat")
    }

    static func testTransformMapsToIntentTransform() {
        let builder = PromptBuilder()
        let context = Context(
            source: ContextSource(applicationName: "Test", bundleIdentifier: "test"),
            selectedText: "text"
        )
        let result = builder.formatUserMessageWithContext("transform", context: context, intent: .selectionTransform)
        TestRunner.assertTrue(result.contains("[Instruction]"), "templateForIntent: selectionTransform -> intentInstruct")
    }

    static func testSummarizeMapsToIntentSummarize() {
        let builder = PromptBuilder()
        let context = Context(
            source: ContextSource(applicationName: "Test", bundleIdentifier: "test"),
            selectedText: "text"
        )
        let result = builder.formatUserMessageWithContext("summarize", context: context, intent: .summarize)
        TestRunner.assertTrue(result.contains("[Request]"), "templateForIntent: summarize -> intentSummarize")
    }
}

// MARK: - Main Entry Point

@main
struct TestMain {
    static func main() {
        print("🧪 Running PromptBuilder Intent Tests...")
        print("")

        TestRunner.reset()

        MessageIntentTests.runAll()
        ChatMessageIntentTests.runAll()

        let intentTests = PromptBuilderIntentTests()
        intentTests.runAll()

        let formatTests = FormatChatMessagesTests()
        formatTests.runAll()

        let contextTests = ContextFormattingTests()
        contextTests.runAll()

        let edgeTests = EdgeCaseTests()
        edgeTests.runAll()

        TemplateForIntentTests.runAll()

        TestRunner.printSummary()

        if TestRunner.failedCount > 0 {
            exit(1)
        }
    }
}
