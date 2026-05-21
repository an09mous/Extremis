// MARK: - CLI Stream Parser
// Parses JSONL output from Claude Code CLI's --output-format stream-json

import Foundation

// MARK: - Stream Event Types

/// Parsed representation of a single JSONL line from Claude Code CLI
struct CLIStreamEvent: Decodable {
    let type: String
    let subtype: String?
    let sessionId: String?
    let totalCostUsd: Double?
    let event: StreamEventPayload?
    let tools: [String]?
    let message: CLIAssistantMessage?
    let error: String?
    let durationMs: Int?
    let rateLimitInfo: CLIRateLimitInfo?

    enum CodingKeys: String, CodingKey {
        case type, subtype, event, tools, message, error
        case sessionId = "session_id"
        case totalCostUsd = "total_cost_usd"
        case durationMs = "duration_ms"
        case rateLimitInfo = "rate_limit_info"
    }
}

/// Payload for stream_event type
struct StreamEventPayload: Decodable {
    let type: String
    let index: Int?
    let contentBlock: ContentBlock?
    let delta: ContentDelta?
    let message: CLIMessageInfo?

    enum CodingKeys: String, CodingKey {
        case type, index, delta, message
        case contentBlock = "content_block"
    }
}

/// Content block in stream events (for content_block_start)
struct ContentBlock: Decodable {
    let type: String
    let id: String?
    let name: String?
    let toolUseId: String?
    let content: String?

    enum CodingKeys: String, CodingKey {
        case type, id, name, content
        case toolUseId = "tool_use_id"
    }
}

/// Delta in stream events (for content_block_delta)
struct ContentDelta: Decodable {
    let type: String
    let text: String?
    let partialJson: String?
    let thinking: String?

    enum CodingKeys: String, CodingKey {
        case type, text, thinking
        case partialJson = "partial_json"
    }
}

/// Message info in message_start events
struct CLIMessageInfo: Decodable {
    let model: String?
    let role: String?
}

/// Full assistant message (from "assistant" type events)
struct CLIAssistantMessage: Decodable {
    let model: String?
    let role: String?
    let content: [CLIAssistantContentBlock]?
}

/// Content block within an assistant message
struct CLIAssistantContentBlock: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: AnyCodable]?
}

/// Rate limit info from rate_limit_event
struct CLIRateLimitInfo: Decodable {
    let status: String?
    let resetsAt: Int?
    let rateLimitType: String?

    enum CodingKeys: String, CodingKey {
        case status, resetsAt, rateLimitType
    }
}

/// Type-erased Codable wrapper for JSON values
struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = ""
        }
    }
}

// MARK: - Parsed Events (High-level)

/// High-level parsed event for consumer use
enum ParsedCLIEvent {
    /// Process initialized with session info and available tools
    case initialized(sessionId: String?, tools: [String])
    /// Text content delta
    case textDelta(String)
    /// Thinking/reasoning delta
    case thinkingDelta(String)
    /// Tool use started
    case toolUseStart(id: String, name: String)
    /// Tool use input JSON delta
    case toolInputDelta(index: Int, partialJson: String)
    /// Tool result content
    case toolResult(toolUseId: String, content: String)
    /// Content block finished
    case contentBlockStop(index: Int)
    /// Message completed
    case messageStop
    /// Generation completed successfully
    case resultSuccess(sessionId: String?, costUsd: Double?, durationMs: Int?)
    /// Generation failed
    case resultError(error: String)
    /// Rate limit event
    case rateLimit(status: String?, resetsAt: Int?, type: String?)
    /// Full assistant message (from --include-partial-messages)
    case assistantMessage(content: String)
}

// MARK: - CLIStreamParser

/// Parses JSONL lines from Claude Code CLI stream-json output into high-level events
final class CLIStreamParser {

    private let decoder = JSONDecoder()

    /// Parse a single JSONL line into a high-level event
    /// Returns nil for unparseable lines, empty lines, or irrelevant events
    func parseLine(_ line: String) -> ParsedCLIEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8) else { return nil }

        guard let event = try? decoder.decode(CLIStreamEvent.self, from: data) else {
            return nil
        }

        return mapEvent(event)
    }

    /// Map a decoded CLIStreamEvent to a high-level ParsedCLIEvent
    private func mapEvent(_ event: CLIStreamEvent) -> ParsedCLIEvent? {
        switch event.type {
        case "system":
            return mapSystemEvent(event)
        case "stream_event":
            return mapStreamEvent(event)
        case "assistant":
            return mapAssistantEvent(event)
        case "result":
            return mapResultEvent(event)
        case "rate_limit_event":
            return ParsedCLIEvent.rateLimit(
                status: event.rateLimitInfo?.status,
                resetsAt: event.rateLimitInfo?.resetsAt,
                type: event.rateLimitInfo?.rateLimitType
            )
        default:
            return nil
        }
    }

    private func mapSystemEvent(_ event: CLIStreamEvent) -> ParsedCLIEvent? {
        guard event.subtype == "init" else { return nil }
        return .initialized(sessionId: event.sessionId, tools: event.tools ?? [])
    }

    private func mapStreamEvent(_ event: CLIStreamEvent) -> ParsedCLIEvent? {
        guard let payload = event.event else { return nil }

        switch payload.type {
        case "content_block_start":
            guard let block = payload.contentBlock else { return nil }
            if block.type == "tool_use", let id = block.id, let name = block.name {
                return .toolUseStart(id: id, name: name)
            }
            if block.type == "tool_result", let toolUseId = block.toolUseId {
                return .toolResult(toolUseId: toolUseId, content: block.content ?? "")
            }
            return nil

        case "content_block_delta":
            guard let delta = payload.delta else { return nil }
            switch delta.type {
            case "text_delta":
                if let text = delta.text {
                    return .textDelta(text)
                }
            case "thinking_delta":
                if let thinking = delta.thinking {
                    return .thinkingDelta(thinking)
                }
            case "input_json_delta":
                if let json = delta.partialJson, let index = payload.index {
                    return .toolInputDelta(index: index, partialJson: json)
                }
            default:
                break
            }
            return nil

        case "content_block_stop":
            return .contentBlockStop(index: payload.index ?? 0)

        case "message_stop":
            return .messageStop

        default:
            return nil
        }
    }

    private func mapAssistantEvent(_ event: CLIStreamEvent) -> ParsedCLIEvent? {
        guard let message = event.message else { return nil }
        // Extract text content from content blocks
        let textContent = message.content?
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined(separator: "") ?? ""
        guard !textContent.isEmpty else { return nil }
        return .assistantMessage(content: textContent)
    }

    private func mapResultEvent(_ event: CLIStreamEvent) -> ParsedCLIEvent? {
        switch event.subtype {
        case "success":
            return .resultSuccess(
                sessionId: event.sessionId,
                costUsd: event.totalCostUsd,
                durationMs: event.durationMs
            )
        case "error":
            return .resultError(error: event.error ?? "Unknown error")
        default:
            return nil
        }
    }
}
