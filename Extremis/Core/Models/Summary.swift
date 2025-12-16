// MARK: - Summary Models
// Types for text summarization feature

import Foundation

// MARK: - Summary Format

/// Available formats for generated summaries
enum SummaryFormat: String, Codable, CaseIterable {
    case paragraph = "paragraph"    // Default prose paragraph
    case bullets = "bullets"        // Bullet point list
    case keyPoints = "key_points"   // Numbered key points
    case actionItems = "actions"    // Action items/tasks
    case oneLiner = "one_liner"     // Single sentence TLDR
    
    var displayName: String {
        switch self {
        case .paragraph: return "Paragraph"
        case .bullets: return "Bullet Points"
        case .keyPoints: return "Key Points"
        case .actionItems: return "Action Items"
        case .oneLiner: return "One-Liner"
        }
    }
    
    var icon: String {
        switch self {
        case .paragraph: return "text.alignleft"
        case .bullets: return "list.bullet"
        case .keyPoints: return "list.number"
        case .actionItems: return "checklist"
        case .oneLiner: return "text.quote"
        }
    }
    
    var promptInstruction: String {
        switch self {
        case .paragraph:
            return "Provide a concise summary in paragraphs. Use bullet points if needed"
        case .bullets:
            return "Provide a summary as bullet points."
        case .keyPoints:
            return "Extract and number the key points."
        case .actionItems:
            return "Extract action items and tasks from the text."
        case .oneLiner:
            return "Provide a single sentence TLDR."
        }
    }
}

// MARK: - Summary Length

/// Desired length of the summary
enum SummaryLength: String, Codable, CaseIterable {
    case shorter = "shorter"   // Very concise
    case normal = "normal"     // Default balanced
    case longer = "longer"     // More detailed
    
    var displayName: String {
        switch self {
        case .shorter: return "Shorter"
        case .normal: return "Normal"
        case .longer: return "Longer"
        }
    }
    
    var promptInstruction: String {
        switch self {
        case .shorter:
            return "Keep it very brief and concise."
        case .normal:
            return "Use a balanced level of detail."
        case .longer:
            return "Provide more detail and context."
        }
    }
}

// MARK: - Summary Request

/// Request to generate a summary
struct SummaryRequest {
    /// The text to summarize
    let text: String
    /// Source application context
    let source: ContextSource
    /// Desired format (default: paragraph)
    let format: SummaryFormat
    /// Desired length (default: normal)
    let length: SummaryLength
    /// Optional surrounding context (preceding/succeeding text, window title)
    let surroundingContext: Context?

    init(
        text: String,
        source: ContextSource,
        format: SummaryFormat = .paragraph,
        length: SummaryLength = .normal,
        surroundingContext: Context? = nil
    ) {
        self.text = text
        self.source = source
        self.format = format
        self.length = length
        self.surroundingContext = surroundingContext
    }
}

// MARK: - Summary Result

/// Result of a summarization operation
struct SummaryResult: Identifiable {
    let id: UUID
    /// The generated summary text
    let summary: String
    /// Original text that was summarized
    let originalText: String
    /// Format used for this summary
    let format: SummaryFormat
    /// Length setting used
    let length: SummaryLength
    /// When the summary was generated
    let generatedAt: Date
    /// Source application
    let source: ContextSource
    
    init(
        id: UUID = UUID(),
        summary: String,
        originalText: String,
        format: SummaryFormat,
        length: SummaryLength,
        generatedAt: Date = Date(),
        source: ContextSource
    ) {
        self.id = id
        self.summary = summary
        self.originalText = originalText
        self.format = format
        self.length = length
        self.generatedAt = generatedAt
        self.source = source
    }
}

