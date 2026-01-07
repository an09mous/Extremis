// MARK: - Storage Error
// Error types for persistence operations

import Foundation

/// Errors that can occur during storage operations
enum StorageError: LocalizedError {
    case directoryCreationFailed(path: String, underlying: Error)
    case fileWriteFailed(path: String, underlying: Error)
    case fileReadFailed(path: String, underlying: Error)
    case fileDeleteFailed(path: String, underlying: Error)
    case encodingFailed(type: String, underlying: Error)
    case decodingFailed(type: String, underlying: Error)
    case migrationFailed(fromVersion: Int, toVersion: Int)
    case conversationNotFound(id: UUID)
    case indexCorrupted(underlying: Error)
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path, let underlying):
            return "Failed to create directory at \(path): \(underlying.localizedDescription)"
        case .fileWriteFailed(let path, let underlying):
            return "Failed to write file at \(path): \(underlying.localizedDescription)"
        case .fileReadFailed(let path, let underlying):
            return "Failed to read file at \(path): \(underlying.localizedDescription)"
        case .fileDeleteFailed(let path, let underlying):
            return "Failed to delete file at \(path): \(underlying.localizedDescription)"
        case .encodingFailed(let type, let underlying):
            return "Failed to encode \(type): \(underlying.localizedDescription)"
        case .decodingFailed(let type, let underlying):
            return "Failed to decode \(type): \(underlying.localizedDescription)"
        case .migrationFailed(let fromVersion, let toVersion):
            return "Failed to migrate from version \(fromVersion) to \(toVersion)"
        case .conversationNotFound(let id):
            return "Conversation not found: \(id)"
        case .indexCorrupted(let underlying):
            return "Conversation index is corrupted: \(underlying.localizedDescription)"
        case .storageUnavailable:
            return "Storage is unavailable"
        }
    }
}
