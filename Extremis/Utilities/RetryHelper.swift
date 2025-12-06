// MARK: - Retry Helper
// Exponential backoff retry logic for network operations

import Foundation

/// Configuration for retry behavior
struct RetryConfiguration {
    let maxAttempts: Int
    let initialDelay: TimeInterval
    let maxDelay: TimeInterval
    let multiplier: Double
    
    static let `default` = RetryConfiguration(
        maxAttempts: 3,
        initialDelay: 1.0,
        maxDelay: 30.0,
        multiplier: 2.0
    )
    
    static let aggressive = RetryConfiguration(
        maxAttempts: 5,
        initialDelay: 0.5,
        maxDelay: 60.0,
        multiplier: 2.0
    )
}

/// Errors that can be retried
enum RetryableError: Error {
    case networkError(underlying: Error)
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case timeout
    
    var isRetryable: Bool {
        switch self {
        case .networkError, .rateLimited, .serverError, .timeout:
            return true
        }
    }
}

/// Helper for executing operations with retry logic
struct RetryHelper {
    
    /// Execute an async operation with exponential backoff retry
    static func withRetry<T>(
        configuration: RetryConfiguration = .default,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var currentDelay = configuration.initialDelay
        
        for attempt in 1...configuration.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Check if error is retryable
                guard shouldRetry(error: error, attempt: attempt, maxAttempts: configuration.maxAttempts) else {
                    throw error
                }
                
                // Handle rate limiting with specific delay
                if let retryAfter = extractRetryAfter(from: error) {
                    currentDelay = retryAfter
                }
                
                print("⚠️ Attempt \(attempt) failed, retrying in \(currentDelay)s...")
                
                // Wait before retry
                try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                
                // Calculate next delay with exponential backoff
                currentDelay = min(currentDelay * configuration.multiplier, configuration.maxDelay)
            }
        }
        
        throw lastError ?? RetryableError.networkError(underlying: NSError(domain: "RetryHelper", code: -1))
    }
    
    /// Determine if an error should be retried
    private static func shouldRetry(error: Error, attempt: Int, maxAttempts: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        
        // Check for retryable error types
        if let retryable = error as? RetryableError {
            return retryable.isRetryable
        }
        
        // Check for URL errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        
        // Check for HTTP status codes in response
        if let httpError = error as? LLMProviderError {
            switch httpError {
            case .rateLimitExceeded:
                return true
            case .networkError:
                return true
            default:
                return false
            }
        }
        
        return false
    }
    
    /// Extract retry-after header value from error
    private static func extractRetryAfter(from error: Error) -> TimeInterval? {
        if case let RetryableError.rateLimited(retryAfter) = error {
            return retryAfter
        }
        return nil
    }
}

// MARK: - Debounce Helper

/// Debounce rapid activations
actor Debouncer {
    private var task: Task<Void, Never>?
    private let delay: TimeInterval
    
    init(delay: TimeInterval = 0.3) {
        self.delay = delay
    }
    
    func debounce(action: @escaping () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await action()
        }
    }
    
    func cancel() {
        task?.cancel()
        task = nil
    }
}

