// MARK: - Context Model
// Represents the captured state when Extremis is activated

import Foundation

// MARK: - Core Context

/// The main context captured when Extremis is activated
struct Context: Codable, Equatable, Identifiable {
    let id: UUID
    let capturedAt: Date
    let source: ContextSource
    let selectedText: String?
    let surroundingText: String?
    let metadata: ContextMetadata
    
    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        source: ContextSource,
        selectedText: String? = nil,
        surroundingText: String? = nil,
        metadata: ContextMetadata = .generic(GenericMetadata())
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.source = source
        self.selectedText = selectedText
        self.surroundingText = surroundingText
        self.metadata = metadata
    }
}

// MARK: - Context Source

/// Information about the source application
struct ContextSource: Codable, Equatable {
    let applicationName: String      // e.g., "Slack", "Google Chrome"
    let bundleIdentifier: String     // e.g., "com.tinyspeck.slackmacgap"
    let windowTitle: String?         // e.g., "#general - Slack"
    let url: URL?                    // For browser-based apps
    
    init(
        applicationName: String,
        bundleIdentifier: String,
        windowTitle: String? = nil,
        url: URL? = nil
    ) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.url = url
    }
}

// MARK: - Context Metadata (Discriminated Union)

/// App-specific metadata captured from the context
enum ContextMetadata: Codable, Equatable {
    case slack(SlackMetadata)
    case gmail(GmailMetadata)
    case github(GitHubMetadata)
    case generic(GenericMetadata)
}

// MARK: - Slack Metadata

struct SlackMetadata: Codable, Equatable {
    let channelName: String?
    let channelType: SlackChannelType
    let participants: [String]
    let recentMessages: [SlackMessage]
    let threadId: String?
    
    init(
        channelName: String? = nil,
        channelType: SlackChannelType = .channel,
        participants: [String] = [],
        recentMessages: [SlackMessage] = [],
        threadId: String? = nil
    ) {
        self.channelName = channelName
        self.channelType = channelType
        self.participants = participants
        self.recentMessages = recentMessages
        self.threadId = threadId
    }
}

enum SlackChannelType: String, Codable, Equatable {
    case channel
    case directMessage
    case groupDM
    case thread
}

struct SlackMessage: Codable, Equatable {
    let sender: String
    let content: String
    let timestamp: Date?
}

// MARK: - Gmail Metadata

struct GmailMetadata: Codable, Equatable {
    let subject: String?
    let recipients: [String]
    let ccRecipients: [String]
    let threadMessages: [GmailMessage]
    let draftContent: String?
    let isComposing: Bool
    let originalSender: String?

    init(
        subject: String? = nil,
        recipients: [String] = [],
        ccRecipients: [String] = [],
        threadMessages: [GmailMessage] = [],
        draftContent: String? = nil,
        isComposing: Bool = false,
        originalSender: String? = nil
    ) {
        self.subject = subject
        self.recipients = recipients
        self.ccRecipients = ccRecipients
        self.threadMessages = threadMessages
        self.draftContent = draftContent
        self.isComposing = isComposing
        self.originalSender = originalSender
    }
}

struct GmailMessage: Codable, Equatable {
    let sender: String
    let content: String
    let timestamp: Date?
}

// MARK: - GitHub Metadata

struct GitHubMetadata: Codable, Equatable {
    let repoName: String?
    let prNumber: Int?
    let prTitle: String?
    let prDescription: String?
    let baseBranch: String?
    let headBranch: String?
    let changedFiles: [String]
    let comments: [GitHubComment]

    init(
        repoName: String? = nil,
        prNumber: Int? = nil,
        prTitle: String? = nil,
        prDescription: String? = nil,
        baseBranch: String? = nil,
        headBranch: String? = nil,
        changedFiles: [String] = [],
        comments: [GitHubComment] = []
    ) {
        self.repoName = repoName
        self.prNumber = prNumber
        self.prTitle = prTitle
        self.prDescription = prDescription
        self.baseBranch = baseBranch
        self.headBranch = headBranch
        self.changedFiles = changedFiles
        self.comments = comments
    }
}

struct GitHubComment: Codable, Equatable {
    let author: String
    let body: String
    let timestamp: Date?
}

// MARK: - Generic Metadata

struct GenericMetadata: Codable, Equatable {
    let focusedElementRole: String?
    let focusedElementLabel: String?
    
    init(
        focusedElementRole: String? = nil,
        focusedElementLabel: String? = nil
    ) {
        self.focusedElementRole = focusedElementRole
        self.focusedElementLabel = focusedElementLabel
    }
}

