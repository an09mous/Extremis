// MARK: - Voice Input Models
// Data structures for voice input state, transcription updates, and configuration

import Foundation

// MARK: - Voice Input State

/// Represents the current state of the voice input system
enum VoiceInputState: Equatable {
    case idle
    case requesting
    case recording
    case error(String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}

// MARK: - Transcription Update

/// A value emitted by the speech recognition stream for each partial or final result
struct TranscriptionUpdate: Equatable {
    /// The current best transcription (replaces previous partial)
    let text: String
    /// Whether this is the final, definitive result
    let isFinal: Bool
    /// Optional confidence score (0.0–1.0) from recognizer
    let confidence: Double?

    init(text: String, isFinal: Bool, confidence: Double? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
    }
}

// MARK: - Voice Input Configuration

/// UserDefaults-backed settings for voice input behavior
struct VoiceInputConfiguration {

    // MARK: - Constants

    static let defaultSilenceTimeout: Double = 3.0
    static let defaultMaxDuration: Double = 60.0

    // MARK: - Properties

    /// Seconds of silence before auto-stop
    var silenceTimeoutSeconds: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "voiceInput.silenceTimeout")
            return val > 0 ? val : Self.defaultSilenceTimeout
        }
        set { UserDefaults.standard.set(newValue, forKey: "voiceInput.silenceTimeout") }
    }

    /// Maximum recording duration in seconds
    var maxDurationSeconds: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "voiceInput.maxDuration")
            return val > 0 ? val : Self.defaultMaxDuration
        }
        set { UserDefaults.standard.set(newValue, forKey: "voiceInput.maxDuration") }
    }

    /// Whether to show animated waveform indicator during recording
    var showWaveformIndicator: Bool {
        get {
            if UserDefaults.standard.object(forKey: "voiceInput.showWaveform") == nil { return true }
            return UserDefaults.standard.bool(forKey: "voiceInput.showWaveform")
        }
        set { UserDefaults.standard.set(newValue, forKey: "voiceInput.showWaveform") }
    }
}

// MARK: - Voice Permission Status

/// Combined permission status for voice input
enum VoicePermissionStatus: Equatable {
    case authorized
    case microphoneDenied
    case speechRecognitionDenied
    case notDetermined
    case siriDisabled
}
