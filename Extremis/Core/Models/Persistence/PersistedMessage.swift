// MARK: - Persisted Message Model
// Message model for persistence with per-message context, tool execution, and attachment support

import Foundation

/// A single message in a persisted conversation
/// Uses contextData for compact JSON storage while ChatMessage uses Context directly
/// For assistant messages, also stores tool execution history (toolRoundsData)
/// For user messages with attachments, stores lightweight refs (attachmentRefsData)
/// — actual image data lives in separate files via ImageStorageManager
struct PersistedMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    let contextData: Data?  // Encoded Context (optional, for user messages)
    let toolRoundsData: Data?  // Encoded [ToolExecutionRoundRecord] (optional, for assistant messages)
    let attachmentRefsData: Data?  // Encoded [PersistedAttachmentRef] (optional, for user messages)

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        contextData: Data? = nil,
        toolRoundsData: Data? = nil,
        attachmentRefsData: Data? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.contextData = contextData
        self.toolRoundsData = toolRoundsData
        self.attachmentRefsData = attachmentRefsData
    }

    // MARK: - Convenience Initializers

    /// Create from existing ChatMessage (context, tool rounds, and attachments are embedded in message)
    /// NOTE: This does NOT save image files to disk — the caller must do that via ImageStorageManager
    /// before creating the PersistedMessage, or use the async variant
    init(from message: ChatMessage) {
        self.id = message.id
        self.role = message.role
        self.content = message.content
        self.timestamp = message.timestamp
        self.contextData = Self.encodeContext(message.context)
        self.toolRoundsData = Self.encodeToolRounds(message.toolRounds)
        self.attachmentRefsData = Self.encodeAttachmentRefs(message.attachments)
    }

    /// Convert to ChatMessage (restores embedded context, tool rounds, and loads attachments from disk)
    func toChatMessage() -> ChatMessage {
        // Load attachments synchronously from refs
        // In practice this is fast since it's just reading files from local disk
        var loadedAttachments: [MessageAttachment]? = nil
        if let refs = decodeAttachmentRefs(), !refs.isEmpty {
            // We need to load from ImageStorageManager, but it's an actor
            // For now, reconstruct without base64 data — the caller should use
            // toChatMessageAsync() for full attachment loading
            // This fallback returns empty attachments so the UI knows they exist
            loadedAttachments = refs.compactMap { ref -> MessageAttachment? in
                guard ref.type == "image", let mediaType = ImageMediaType(rawValue: ref.mediaType) else {
                    return nil
                }
                return .image(ImageAttachment(
                    id: ref.id,
                    mediaType: mediaType,
                    base64Data: "",  // Placeholder — use toChatMessageAsync for full data
                    width: ref.width,
                    height: ref.height,
                    fileSizeBytes: ref.fileSizeBytes,
                    sourceFileName: ref.sourceFileName
                ))
            }
        }

        return ChatMessage(
            id: id,
            role: role,
            content: content,
            timestamp: timestamp,
            context: decodeContext(),
            intent: nil,
            toolRounds: decodeToolRounds(),
            attachments: loadedAttachments
        )
    }

    /// Convert to ChatMessage with full attachment data loaded from disk
    func toChatMessageAsync() async -> ChatMessage {
        var loadedAttachments: [MessageAttachment]? = nil
        if let refs = decodeAttachmentRefs(), !refs.isEmpty {
            let loaded = await ImageStorageManager.shared.loadAttachments(refs: refs)
            if !loaded.isEmpty {
                loadedAttachments = loaded
            }
        }

        return ChatMessage(
            id: id,
            role: role,
            content: content,
            timestamp: timestamp,
            context: decodeContext(),
            intent: nil,
            toolRounds: decodeToolRounds(),
            attachments: loadedAttachments
        )
    }

    // MARK: - Context Helpers

    /// Decode context if present
    func decodeContext() -> Context? {
        guard let data = contextData else { return nil }
        return try? JSONDecoder().decode(Context.self, from: data)
    }

    /// Encode context to Data
    static func encodeContext(_ context: Context?) -> Data? {
        guard let context = context else { return nil }
        return try? JSONEncoder().encode(context)
    }

    /// Check if message has context attached
    var hasContext: Bool {
        contextData != nil
    }

    // MARK: - Tool Rounds Helpers

    /// Decode tool execution rounds if present
    func decodeToolRounds() -> [ToolExecutionRoundRecord]? {
        guard let data = toolRoundsData else { return nil }
        return try? JSONDecoder().decode([ToolExecutionRoundRecord].self, from: data)
    }

    /// Encode tool execution rounds to Data
    static func encodeToolRounds(_ toolRounds: [ToolExecutionRoundRecord]?) -> Data? {
        guard let toolRounds = toolRounds, !toolRounds.isEmpty else { return nil }
        return try? JSONEncoder().encode(toolRounds)
    }

    /// Check if message has tool execution history
    var hasToolExecutions: Bool {
        toolRoundsData != nil
    }

    // MARK: - Attachment Refs Helpers

    /// Decode attachment references if present
    func decodeAttachmentRefs() -> [PersistedAttachmentRef]? {
        guard let data = attachmentRefsData else { return nil }
        return try? JSONDecoder().decode([PersistedAttachmentRef].self, from: data)
    }

    /// Encode attachment references from MessageAttachments
    static func encodeAttachmentRefs(_ attachments: [MessageAttachment]?) -> Data? {
        guard let attachments = attachments, !attachments.isEmpty else { return nil }
        let refs = attachments.map { PersistedAttachmentRef.fromAttachment($0) }
        return try? JSONEncoder().encode(refs)
    }

    /// Check if message has attachments
    var hasAttachments: Bool {
        attachmentRefsData != nil
    }
}
