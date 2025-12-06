// MARK: - Instruction Model
// Represents the user's natural language request

import Foundation

/// The user's instruction for what they want the AI to do
struct Instruction: Codable, Equatable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date
    let contextId: UUID
    
    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        contextId: UUID
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.contextId = contextId
    }
}

// MARK: - Validation

extension Instruction {
    /// Maximum allowed instruction length (in characters)
    static let maxLength = 4000
    
    /// Validates the instruction text
    var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        text.count <= Self.maxLength
    }
    
    /// Returns a trimmed version of the instruction
    var trimmed: Instruction {
        Instruction(
            id: id,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: createdAt,
            contextId: contextId
        )
    }
}

