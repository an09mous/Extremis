// MARK: - Speech Recognition Service
// Wraps AVCaptureSession + SFSpeechRecognizer for on-device speech-to-text

import Foundation
import Speech
import AVFoundation
import CoreMedia
import CoreAudio

/// Provides on-device speech recognition via Apple's Speech framework
@MainActor
final class SpeechRecognitionService: NSObject, SFSpeechRecognizerDelegate {

    // MARK: - Properties

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isEngineRunning = false

    // AVCaptureSession-based audio capture (bypasses AVAudioEngine aggregate device bugs on macOS 26)
    private var captureSession: AVCaptureSession?
    private var audioCaptureDelegate: AudioCaptureDelegate?

    /// Whether on-device recognition is available
    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    /// Whether on-device recognition is supported (requires Siri enabled)
    var supportsOnDevice: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }

    // MARK: - Initialization

    override init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        speechRecognizer?.delegate = self
    }

    // MARK: - Authorization

    /// Current speech recognition authorization status
    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    /// Request speech recognition authorization
    nonisolated static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Transcription

    /// Start transcribing speech from the microphone.
    /// Returns an AsyncThrowingStream of TranscriptionUpdate values.
    func startTranscription() throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        stopTranscription()

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        self.recognitionRequest = request

        // AVCaptureSession is preferred (avoids AVAudioEngine aggregate device bugs on macOS 26).
        // Falls back to AVAudioEngine if capture session setup fails.
        let usedCaptureSession = try setupAudioCapture(request: request)

        if !usedCaptureSession {
            audioEngine.prepare()
            try audioEngine.start()
            isEngineRunning = true
        }

        return AsyncThrowingStream { continuation in
            self.recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                if let result {
                    let bestTranscription = result.bestTranscription
                    let confidence: Double? = bestTranscription.segments.last.map { Double($0.confidence) }

                    continuation.yield(TranscriptionUpdate(
                        text: bestTranscription.formattedString,
                        isFinal: result.isFinal,
                        confidence: confidence
                    ))

                    if result.isFinal {
                        continuation.finish()
                        Task { @MainActor in self?.cleanupAudioCapture() }
                    }
                }

                if let error {
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // Recognition was cancelled
                        continuation.finish()
                    } else if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        continuation.finish(throwing: SpeechRecognitionError.siriDisabled)
                    } else {
                        continuation.finish(throwing: SpeechRecognitionError.recognitionFailed(error.localizedDescription))
                    }
                    Task { @MainActor in self?.cleanupAudioCapture() }
                }
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.stopTranscription() }
            }
        }
    }

    /// Stop transcription and clean up all resources
    func stopTranscription() {
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.finish()
        recognitionTask = nil

        cleanupAudioCapture()
    }

    // MARK: - Private

    /// Sets up audio capture using AVCaptureSession (preferred) or AVAudioEngine (fallback).
    /// Returns true if AVCaptureSession is being used.
    private func setupAudioCapture(request: SFSpeechAudioBufferRecognitionRequest) throws -> Bool {
        // AVCaptureSession bypasses the broken aggregate device path in AVAudioEngine
        // on macOS 26 that causes CoreAudio -10877 errors and zero buffer delivery.
        do {
            let session = AVCaptureSession()

            guard let microphone = AVCaptureDevice.default(for: .audio) else {
                throw SpeechRecognitionError.audioEngineFailure("No microphone")
            }

            let audioInput = try AVCaptureDeviceInput(device: microphone)
            guard session.canAddInput(audioInput) else {
                throw SpeechRecognitionError.audioEngineFailure("Cannot add audio input")
            }
            session.addInput(audioInput)

            let audioOutput = AVCaptureAudioDataOutput()
            guard session.canAddOutput(audioOutput) else {
                throw SpeechRecognitionError.audioEngineFailure("Cannot add audio output")
            }
            session.addOutput(audioOutput)

            let delegate = AudioCaptureDelegate(request: request)
            let captureQueue = DispatchQueue(label: "com.extremis.audiocapture", qos: .userInteractive)
            audioOutput.setSampleBufferDelegate(delegate, queue: captureQueue)

            session.startRunning()

            self.captureSession = session
            self.audioCaptureDelegate = delegate
            return true
        } catch {
            // Fall through to AVAudioEngine
        }

        // Fallback: AVAudioEngine with explicit mono format
        let inputNode = audioEngine.inputNode

        if #available(macOS 14.0, *) {
            try? inputNode.setVoiceProcessingEnabled(true)
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 else {
            throw SpeechRecognitionError.audioEngineFailure("No audio input available")
        }

        // Explicit mono format avoids multi-channel formats from voice processing
        let tapFormat = AVAudioFormat(standardFormatWithSampleRate: recordingFormat.sampleRate, channels: 1)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            request.append(buffer)
        }

        return false
    }

    private func cleanupAudioCapture() {
        if let session = captureSession {
            session.stopRunning()
            captureSession = nil
            audioCaptureDelegate = nil
        }

        if isEngineRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            isEngineRunning = false
        }
    }

    // MARK: - SFSpeechRecognizerDelegate

    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available {
                self.stopTranscription()
            }
        }
    }
}

// MARK: - Audio Capture Delegate

/// Bridges AVCaptureSession audio output to SFSpeechAudioBufferRecognitionRequest.
/// This bypasses AVAudioEngine entirely, avoiding the aggregate device bugs on macOS 26.
final class AudioCaptureDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let request: SFSpeechAudioBufferRecognitionRequest

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
        super.init()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pcmBuffer = sampleBuffer.toAudioPCMBuffer() else { return }
        request.append(pcmBuffer)
    }
}

// MARK: - CMSampleBuffer → AVAudioPCMBuffer Conversion

extension CMSampleBuffer {
    /// Converts an audio CMSampleBuffer to an AVAudioPCMBuffer suitable for SFSpeechRecognitionRequest.
    func toAudioPCMBuffer() -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let isInterleaved = streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0

        guard let avFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: streamDescription.pointee.mSampleRate,
            channels: AVAudioChannelCount(streamDescription.pointee.mChannelsPerFrame),
            interleaved: isInterleaved
        ) else {
            return nil
        }

        let frameCount = CMSampleBufferGetNumSamples(self)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        guard let blockBuffer = CMSampleBufferGetDataBuffer(self) else { return nil }

        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0,
            lengthAtOffsetOut: nil, totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == noErr, let srcData = dataPointer, totalLength > 0 else { return nil }

        guard let channelData = pcmBuffer.floatChannelData else { return nil }

        let channels = Int(streamDescription.pointee.mChannelsPerFrame)
        let bytesPerFrame = Int(streamDescription.pointee.mBytesPerFrame)

        if channels == 1 || !isInterleaved {
            let bytesPerChannel = frameCount * Int(streamDescription.pointee.mBitsPerChannel / 8)
            for ch in 0..<channels {
                let copySize = min(bytesPerChannel, totalLength - ch * bytesPerChannel)
                guard copySize > 0 else { continue }
                memcpy(channelData[ch], srcData.advanced(by: ch * bytesPerChannel), copySize)
            }
        } else {
            let copySize = min(totalLength, frameCount * bytesPerFrame)
            memcpy(channelData[0], srcData, copySize)
        }

        return pcmBuffer
    }
}

// MARK: - Speech Recognition Errors

enum SpeechRecognitionError: LocalizedError, Sendable {
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
