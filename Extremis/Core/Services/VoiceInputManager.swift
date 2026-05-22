// MARK: - Voice Input Manager
// Coordinates voice recording, transcription, and state management

import Foundation
import Speech
import AVFoundation
import AppKit

/// Central coordinator for voice input functionality
@MainActor
final class VoiceInputManager: ObservableObject {

    // MARK: - Singleton

    static let shared = VoiceInputManager()

    // MARK: - Published Properties

    /// Current state of the voice input system
    @Published private(set) var state: VoiceInputState = .idle

    /// Live partial transcription text (updated in real-time while recording)
    @Published private(set) var partialTranscription: String = ""

    // MARK: - Private Properties

    private let speechService = SpeechRecognitionService()
    private var configuration = VoiceInputConfiguration()
    private var transcriptionTask: Task<Void, Never>?
    private var silenceTimer: Timer?
    private var maxDurationTimer: Timer?
    private var lastPartialUpdateTime: Date?
    private var errorDismissTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.state.isRecording == true {
                    self?.stopRecording()
                }
            }
        }
    }

    // MARK: - Public Methods

    /// Toggle recording on/off
    func toggleRecording() {
        if state.isRecording {
            stopRecording()
        } else if state.isIdle {
            startRecording()
        }
    }

    /// Start voice recording and transcription
    func startRecording() {
        guard state.isIdle else { return }

        Task {
            let permissionStatus = await checkPermissions()
            switch permissionStatus {
            case .authorized:
                beginTranscription()
            case .notDetermined:
                state = .requesting
                let granted = await requestPermissions()
                if granted {
                    beginTranscription()
                } else {
                    if Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") == nil {
                        setError("Voice input requires running Extremis as an app bundle. Use the built .app or scripts/build.sh.")
                    } else {
                        setError("Microphone or speech recognition permission was denied.")
                    }
                }
            case .microphoneDenied:
                setError("Microphone access denied. Open System Settings > Privacy & Security > Microphone.")
            case .speechRecognitionDenied:
                setError("Speech recognition denied. Open System Settings > Privacy & Security > Speech Recognition.")
            case .siriDisabled:
                setError("Enable Dictation in System Settings → Keyboard → Dictation for voice input.")
            }
        }
    }

    /// Stop recording and finalize transcription
    func stopRecording() {
        guard state.isRecording else { return }

        invalidateTimers()
        speechService.stopTranscription()
        transcriptionTask?.cancel()
        transcriptionTask = nil

        state = .idle
    }

    /// Get the current transcription and reset for next session
    func consumeTranscription() -> String {
        let text = partialTranscription
        partialTranscription = ""
        return text
    }

    // MARK: - Permission Checking

    /// Check combined voice input permission status
    func checkPermissions() async -> VoicePermissionStatus {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .denied, .restricted:
            return .microphoneDenied
        case .notDetermined:
            return .notDetermined
        case .authorized:
            break
        @unknown default:
            return .notDetermined
        }

        let speechStatus = SpeechRecognitionService.authorizationStatus
        switch speechStatus {
        case .denied, .restricted:
            return .speechRecognitionDenied
        case .notDetermined:
            return .notDetermined
        case .authorized:
            break
        @unknown default:
            return .notDetermined
        }

        if !speechService.supportsOnDevice && !speechService.isAvailable {
            return .siriDisabled
        }

        return .authorized
    }

    /// Request all required permissions.
    func requestPermissions() async -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            return false
        }
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else {
            return false
        }

        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard micGranted else { return false }

        let speechStatus = await SpeechRecognitionService.requestAuthorization()
        return speechStatus == .authorized
    }

    // MARK: - Private Methods

    private func beginTranscription() {
        do {
            let stream = try speechService.startTranscription()
            state = .recording
            lastPartialUpdateTime = Date()
            startTimers()

            transcriptionTask = Task { [weak self] in
                do {
                    for try await update in stream {
                        guard !Task.isCancelled else { break }
                        await MainActor.run {
                            self?.handleTranscriptionUpdate(update)
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self?.handleTranscriptionError(error)
                    }
                }
            }
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func handleTranscriptionUpdate(_ update: TranscriptionUpdate) {
        partialTranscription = update.text
        lastPartialUpdateTime = Date()

        resetSilenceTimer()

        if update.isFinal {
            invalidateTimers()
            state = .idle
        }
    }

    private func handleTranscriptionError(_ error: Error) {
        invalidateTimers()
        setError(error.localizedDescription)
    }

    private func setError(_ message: String) {
        state = .error(message)

        errorDismissTask?.cancel()
        errorDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.state.isError == true {
                    self?.state = .idle
                }
            }
        }
    }

    // MARK: - Timer Management

    private func startTimers() {
        resetSilenceTimer()

        maxDurationTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.maxDurationSeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.silenceTimeoutSeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
    }

    private func invalidateTimers() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
    }
}
