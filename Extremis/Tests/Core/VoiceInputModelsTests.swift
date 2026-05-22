// MARK: - Voice Input Models Unit Tests
// Tests for VoiceInputState, TranscriptionUpdate, VoiceInputConfiguration, and SpeechRecognitionError

import Foundation

// MARK: - Test Runner Framework

struct TestRunner {
    static var passedCount = 0
    static var failedCount = 0
    static var failedTests: [(name: String, message: String)] = []
    static var currentGroup = ""

    static func reset() {
        passedCount = 0
        failedCount = 0
        failedTests = []
        currentGroup = ""
    }

    static func suite(_ name: String) {
        currentGroup = name
        print("")
        print("📦 \(name)")
        print("----------------------------------------")
    }

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ testName: String) {
        if actual == expected {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            let message = "Expected '\(expected)' but got '\(actual)'"
            failedTests.append((testName, message))
            print("  ✗ \(testName): \(message)")
        }
    }

    static func assertTrue(_ condition: Bool, _ testName: String) {
        if condition {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected true but got false"))
            print("  ✗ \(testName): Expected true but got false")
        }
    }

    static func assertFalse(_ condition: Bool, _ testName: String) {
        assertTrue(!condition, testName)
    }

    static func assertNil<T>(_ value: T?, _ testName: String) {
        if value == nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected nil but got value"))
            print("  ✗ \(testName): Expected nil but got value")
        }
    }

    static func assertNotNil<T>(_ value: T?, _ testName: String) {
        if value != nil {
            passedCount += 1
            print("  ✓ \(testName)")
        } else {
            failedCount += 1
            failedTests.append((testName, "Expected non-nil but got nil"))
            print("  ✗ \(testName): Expected non-nil but got nil")
        }
    }

    static func printSummary() {
        print("")
        print("==================================================")
        print("TEST SUMMARY")
        print("==================================================")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")
        print("Total:  \(passedCount + failedCount)")
        if !failedTests.isEmpty {
            print("")
            print("Failed tests:")
            for (name, message) in failedTests {
                print("  - \(name): \(message)")
            }
        }
        print("==================================================")
    }
}

// MARK: - Embedded Type Definitions (standalone test — cannot import main module)

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

struct TranscriptionUpdate: Equatable {
    let text: String
    let isFinal: Bool
    let confidence: Double?

    init(text: String, isFinal: Bool, confidence: Double? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
    }
}

struct VoiceInputConfiguration {
    static let defaultSilenceTimeout: Double = 3.0
    static let defaultMaxDuration: Double = 60.0

    var silenceTimeoutSeconds: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "voiceInput.silenceTimeout")
            return val > 0 ? val : Self.defaultSilenceTimeout
        }
        set { UserDefaults.standard.set(newValue, forKey: "voiceInput.silenceTimeout") }
    }

    var maxDurationSeconds: Double {
        get {
            let val = UserDefaults.standard.double(forKey: "voiceInput.maxDuration")
            return val > 0 ? val : Self.defaultMaxDuration
        }
        set { UserDefaults.standard.set(newValue, forKey: "voiceInput.maxDuration") }
    }

    var showWaveformIndicator: Bool {
        get {
            if UserDefaults.standard.object(forKey: "voiceInput.showWaveform") == nil { return true }
            return UserDefaults.standard.bool(forKey: "voiceInput.showWaveform")
        }
        set { UserDefaults.standard.set(newValue, forKey: "voiceInput.showWaveform") }
    }
}

enum VoicePermissionStatus: Equatable {
    case authorized
    case microphoneDenied
    case speechRecognitionDenied
    case notDetermined
    case siriDisabled
}

enum SpeechRecognitionError: LocalizedError {
    case recognizerUnavailable
    case audioEngineFailure(String)
    case recognitionFailed(String)
    case microphoneAccessDenied
    case speechRecognitionDenied
    case siriDisabled

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is unavailable. Enable Dictation in System Settings → Keyboard → Dictation."
        case .audioEngineFailure(let detail):
            return "Audio engine error: \(detail)"
        case .recognitionFailed(let detail):
            return "Recognition failed: \(detail)"
        case .microphoneAccessDenied:
            return "Microphone access denied. Open System Settings > Privacy > Microphone to grant access."
        case .speechRecognitionDenied:
            return "Speech recognition denied. Open System Settings > Privacy > Speech Recognition to grant access."
        case .siriDisabled:
            return "Enable Dictation in System Settings → Keyboard → Dictation for voice input."
        }
    }
}

// MARK: - VoiceInputState Tests

func testVoiceInputStateProperties() {
    TestRunner.suite("VoiceInputState Properties")

    // idle
    let idle = VoiceInputState.idle
    TestRunner.assertTrue(idle.isIdle, "idle state isIdle")
    TestRunner.assertFalse(idle.isRecording, "idle state is not recording")
    TestRunner.assertFalse(idle.isError, "idle state is not error")
    TestRunner.assertNil(idle.errorMessage, "idle state has no error message")

    // recording
    let recording = VoiceInputState.recording
    TestRunner.assertTrue(recording.isRecording, "recording state isRecording")
    TestRunner.assertFalse(recording.isIdle, "recording state is not idle")
    TestRunner.assertFalse(recording.isError, "recording state is not error")
    TestRunner.assertNil(recording.errorMessage, "recording state has no error message")

    // requesting
    let requesting = VoiceInputState.requesting
    TestRunner.assertFalse(requesting.isIdle, "requesting state is not idle")
    TestRunner.assertFalse(requesting.isRecording, "requesting state is not recording")
    TestRunner.assertFalse(requesting.isError, "requesting state is not error")

    // error
    let error = VoiceInputState.error("Test error")
    TestRunner.assertTrue(error.isError, "error state isError")
    TestRunner.assertFalse(error.isIdle, "error state is not idle")
    TestRunner.assertFalse(error.isRecording, "error state is not recording")
    TestRunner.assertEqual(error.errorMessage, "Test error", "error message matches")
}

func testVoiceInputStateEquality() {
    TestRunner.suite("VoiceInputState Equality")

    TestRunner.assertTrue(VoiceInputState.idle == VoiceInputState.idle, "idle equals idle")
    TestRunner.assertTrue(VoiceInputState.recording == VoiceInputState.recording, "recording equals recording")
    TestRunner.assertTrue(VoiceInputState.requesting == VoiceInputState.requesting, "requesting equals requesting")
    TestRunner.assertTrue(
        VoiceInputState.error("msg") == VoiceInputState.error("msg"),
        "error with same message equals"
    )
    TestRunner.assertFalse(
        VoiceInputState.error("a") == VoiceInputState.error("b"),
        "error with different messages not equal"
    )
    TestRunner.assertFalse(VoiceInputState.idle == VoiceInputState.recording, "idle not equal to recording")
    TestRunner.assertFalse(VoiceInputState.recording == VoiceInputState.error("x"), "recording not equal to error")
}

// MARK: - TranscriptionUpdate Tests

func testTranscriptionUpdate() {
    TestRunner.suite("TranscriptionUpdate")

    let partial = TranscriptionUpdate(text: "Hello", isFinal: false)
    TestRunner.assertEqual(partial.text, "Hello", "partial text matches")
    TestRunner.assertFalse(partial.isFinal, "partial is not final")
    TestRunner.assertNil(partial.confidence, "partial has no confidence by default")

    let final = TranscriptionUpdate(text: "Hello world", isFinal: true, confidence: 0.95)
    TestRunner.assertEqual(final.text, "Hello world", "final text matches")
    TestRunner.assertTrue(final.isFinal, "final is final")
    TestRunner.assertNotNil(final.confidence, "final has confidence")
    TestRunner.assertEqual(final.confidence, 0.95, "final confidence matches")
}

func testTranscriptionUpdateEquality() {
    TestRunner.suite("TranscriptionUpdate Equality")

    let a = TranscriptionUpdate(text: "Hello", isFinal: false)
    let b = TranscriptionUpdate(text: "Hello", isFinal: false)
    let c = TranscriptionUpdate(text: "World", isFinal: false)
    let d = TranscriptionUpdate(text: "Hello", isFinal: true)

    TestRunner.assertTrue(a == b, "same text and isFinal are equal")
    TestRunner.assertFalse(a == c, "different text not equal")
    TestRunner.assertFalse(a == d, "different isFinal not equal")
}

func testTranscriptionUpdateEdgeCases() {
    TestRunner.suite("TranscriptionUpdate Edge Cases")

    let empty = TranscriptionUpdate(text: "", isFinal: false)
    TestRunner.assertEqual(empty.text, "", "empty text is empty string")

    let whitespace = TranscriptionUpdate(text: "   ", isFinal: false)
    TestRunner.assertEqual(whitespace.text, "   ", "whitespace-only text preserved")

    let zeroConfidence = TranscriptionUpdate(text: "test", isFinal: true, confidence: 0.0)
    TestRunner.assertEqual(zeroConfidence.confidence, 0.0, "zero confidence is valid")

    let maxConfidence = TranscriptionUpdate(text: "test", isFinal: true, confidence: 1.0)
    TestRunner.assertEqual(maxConfidence.confidence, 1.0, "max confidence is valid")

    let longText = TranscriptionUpdate(text: String(repeating: "word ", count: 1000), isFinal: true)
    TestRunner.assertEqual(longText.text.count, 5000, "long text preserved")
}

func testTranscriptionUpdateConfidenceEquality() {
    TestRunner.suite("TranscriptionUpdate Confidence Equality")

    let withConfidence = TranscriptionUpdate(text: "hi", isFinal: false, confidence: 0.5)
    let withoutConfidence = TranscriptionUpdate(text: "hi", isFinal: false)
    TestRunner.assertFalse(withConfidence == withoutConfidence, "nil vs non-nil confidence not equal")

    let sameConfidence1 = TranscriptionUpdate(text: "hi", isFinal: false, confidence: 0.8)
    let sameConfidence2 = TranscriptionUpdate(text: "hi", isFinal: false, confidence: 0.8)
    TestRunner.assertTrue(sameConfidence1 == sameConfidence2, "same confidence values equal")
}

// MARK: - VoiceInputConfiguration Tests

func testVoiceInputConfigurationDefaults() {
    TestRunner.suite("VoiceInputConfiguration Defaults")

    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "voiceInput.silenceTimeout")
    defaults.removeObject(forKey: "voiceInput.maxDuration")
    defaults.removeObject(forKey: "voiceInput.showWaveform")

    let config = VoiceInputConfiguration()

    TestRunner.assertEqual(config.silenceTimeoutSeconds, 3.0, "default silence timeout is 3.0s")
    TestRunner.assertEqual(config.maxDurationSeconds, 60.0, "default max duration is 60.0s")
    TestRunner.assertTrue(config.showWaveformIndicator, "default showWaveform is true")
}

func testVoiceInputConfigurationCustomValues() {
    TestRunner.suite("VoiceInputConfiguration Custom Values")

    var config = VoiceInputConfiguration()

    config.silenceTimeoutSeconds = 5.0
    TestRunner.assertEqual(config.silenceTimeoutSeconds, 5.0, "custom silence timeout persists")

    config.maxDurationSeconds = 30.0
    TestRunner.assertEqual(config.maxDurationSeconds, 30.0, "custom max duration persists")

    config.showWaveformIndicator = false
    TestRunner.assertFalse(config.showWaveformIndicator, "custom showWaveform persists")

    // Clean up
    UserDefaults.standard.removeObject(forKey: "voiceInput.silenceTimeout")
    UserDefaults.standard.removeObject(forKey: "voiceInput.maxDuration")
    UserDefaults.standard.removeObject(forKey: "voiceInput.showWaveform")
}

func testVoiceInputConfigurationConstants() {
    TestRunner.suite("VoiceInputConfiguration Constants")

    TestRunner.assertEqual(VoiceInputConfiguration.defaultSilenceTimeout, 3.0, "defaultSilenceTimeout constant is 3.0")
    TestRunner.assertEqual(VoiceInputConfiguration.defaultMaxDuration, 60.0, "defaultMaxDuration constant is 60.0")
}

func testVoiceInputConfigurationBoundaryValues() {
    TestRunner.suite("VoiceInputConfiguration Boundary Values")

    var config = VoiceInputConfiguration()

    // Very small values
    config.silenceTimeoutSeconds = 0.1
    TestRunner.assertEqual(config.silenceTimeoutSeconds, 0.1, "very small silence timeout works")

    // Very large values
    config.maxDurationSeconds = 3600.0
    TestRunner.assertEqual(config.maxDurationSeconds, 3600.0, "large max duration works")

    // Clean up
    UserDefaults.standard.removeObject(forKey: "voiceInput.silenceTimeout")
    UserDefaults.standard.removeObject(forKey: "voiceInput.maxDuration")
}

// MARK: - VoicePermissionStatus Tests

func testVoicePermissionStatus() {
    TestRunner.suite("VoicePermissionStatus Equality")

    TestRunner.assertTrue(VoicePermissionStatus.authorized == VoicePermissionStatus.authorized, "authorized equals authorized")
    TestRunner.assertTrue(VoicePermissionStatus.microphoneDenied == VoicePermissionStatus.microphoneDenied, "microphoneDenied equals")
    TestRunner.assertTrue(VoicePermissionStatus.speechRecognitionDenied == VoicePermissionStatus.speechRecognitionDenied, "speechRecognitionDenied equals")
    TestRunner.assertTrue(VoicePermissionStatus.notDetermined == VoicePermissionStatus.notDetermined, "notDetermined equals")
    TestRunner.assertTrue(VoicePermissionStatus.siriDisabled == VoicePermissionStatus.siriDisabled, "siriDisabled equals")
    TestRunner.assertFalse(VoicePermissionStatus.authorized == VoicePermissionStatus.microphoneDenied, "different statuses not equal")
}

func testVoicePermissionStatusAllCombinations() {
    TestRunner.suite("VoicePermissionStatus All Inequality Pairs")

    let allStatuses: [VoicePermissionStatus] = [.authorized, .microphoneDenied, .speechRecognitionDenied, .notDetermined, .siriDisabled]

    for i in 0..<allStatuses.count {
        for j in 0..<allStatuses.count {
            if i == j {
                TestRunner.assertTrue(allStatuses[i] == allStatuses[j], "status[\(i)] equals itself")
            } else {
                TestRunner.assertFalse(allStatuses[i] == allStatuses[j], "status[\(i)] != status[\(j)]")
            }
        }
    }
}

// MARK: - SpeechRecognitionError Tests

func testSpeechRecognitionErrors() {
    TestRunner.suite("SpeechRecognitionError Descriptions")

    let unavailable = SpeechRecognitionError.recognizerUnavailable
    TestRunner.assertNotNil(unavailable.errorDescription, "recognizerUnavailable has description")
    TestRunner.assertTrue(
        unavailable.errorDescription!.contains("Dictation"),
        "recognizerUnavailable mentions Dictation"
    )

    let audioFail = SpeechRecognitionError.audioEngineFailure("No mic")
    TestRunner.assertTrue(
        audioFail.errorDescription!.contains("No mic"),
        "audioEngineFailure includes detail"
    )

    let recFail = SpeechRecognitionError.recognitionFailed("Timeout")
    TestRunner.assertTrue(
        recFail.errorDescription!.contains("Timeout"),
        "recognitionFailed includes detail"
    )

    let micDenied = SpeechRecognitionError.microphoneAccessDenied
    TestRunner.assertTrue(
        micDenied.errorDescription!.contains("Microphone"),
        "microphoneAccessDenied mentions Microphone"
    )

    let speechDenied = SpeechRecognitionError.speechRecognitionDenied
    TestRunner.assertTrue(
        speechDenied.errorDescription!.contains("Speech Recognition"),
        "speechRecognitionDenied mentions Speech Recognition"
    )

    let siriDisabled = SpeechRecognitionError.siriDisabled
    TestRunner.assertNotNil(siriDisabled.errorDescription, "siriDisabled has description")
    TestRunner.assertTrue(
        siriDisabled.errorDescription!.contains("Dictation"),
        "siriDisabled mentions Dictation"
    )
}

func testSpeechRecognitionErrorLocalizedError() {
    TestRunner.suite("SpeechRecognitionError LocalizedError Conformance")

    // All cases should provide non-nil errorDescription
    let allCases: [SpeechRecognitionError] = [
        .recognizerUnavailable,
        .audioEngineFailure("test"),
        .recognitionFailed("test"),
        .microphoneAccessDenied,
        .speechRecognitionDenied,
        .siriDisabled
    ]

    for error in allCases {
        TestRunner.assertNotNil(error.errorDescription, "\(error) has errorDescription")
    }
}

func testSpeechRecognitionErrorDetailPreservation() {
    TestRunner.suite("SpeechRecognitionError Detail Preservation")

    let details = ["short", String(repeating: "x", count: 500), "special chars: éàü & <tag>"]
    for detail in details {
        let audioErr = SpeechRecognitionError.audioEngineFailure(detail)
        TestRunner.assertTrue(
            audioErr.errorDescription!.contains(detail),
            "audioEngineFailure preserves detail: '\(detail.prefix(20))...'"
        )

        let recErr = SpeechRecognitionError.recognitionFailed(detail)
        TestRunner.assertTrue(
            recErr.errorDescription!.contains(detail),
            "recognitionFailed preserves detail: '\(detail.prefix(20))...'"
        )
    }
}

// MARK: - Entry Point

@main
struct VoiceInputModelsTests {
    static func main() {
        print("🧪 Voice Input Models Tests")
        print("==================================================")

        testVoiceInputStateProperties()
        testVoiceInputStateEquality()
        testTranscriptionUpdate()
        testTranscriptionUpdateEquality()
        testTranscriptionUpdateEdgeCases()
        testTranscriptionUpdateConfidenceEquality()
        testVoiceInputConfigurationDefaults()
        testVoiceInputConfigurationCustomValues()
        testVoiceInputConfigurationConstants()
        testVoiceInputConfigurationBoundaryValues()
        testVoicePermissionStatus()
        testVoicePermissionStatusAllCombinations()
        testSpeechRecognitionErrors()
        testSpeechRecognitionErrorLocalizedError()
        testSpeechRecognitionErrorDetailPreservation()

        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
