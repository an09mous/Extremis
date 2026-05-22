// MARK: - Speech Recognition Service Unit Tests
// Tests for AudioCaptureDelegate, CMSampleBuffer conversion, and error classification

import Foundation
import AVFoundation
import CoreMedia
import CoreAudio

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

// MARK: - Embedded CMSampleBuffer Extension (mirrors main module for standalone testing)

extension CMSampleBuffer {
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

// MARK: - Test Helpers

/// Creates a CMSampleBuffer with audio data for testing
func createTestAudioSampleBuffer(
    sampleRate: Float64 = 48000,
    channels: UInt32 = 1,
    frameCount: Int = 1024,
    interleaved: Bool = true
) -> CMSampleBuffer? {
    let bytesPerSample: UInt32 = 4 // Float32
    let bytesPerFrame = bytesPerSample * channels
    let totalBytes = frameCount * Int(bytesPerFrame)

    // Create audio format description
    var asbd = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | (interleaved ? 0 : kAudioFormatFlagIsNonInterleaved),
        mBytesPerPacket: bytesPerFrame,
        mFramesPerPacket: 1,
        mBytesPerFrame: bytesPerFrame,
        mChannelsPerFrame: channels,
        mBitsPerChannel: bytesPerSample * 8,
        mReserved: 0
    )

    var formatDescription: CMAudioFormatDescription?
    let formatStatus = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &asbd,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDescription
    )
    guard formatStatus == noErr, let formatDesc = formatDescription else { return nil }

    // Allocate memory and fill with sine wave data
    let memory = UnsafeMutablePointer<Int8>.allocate(capacity: totalBytes)
    let floatPtr = UnsafeMutableRawPointer(memory).bindMemory(to: Float32.self, capacity: frameCount * Int(channels))
    for i in 0..<(frameCount * Int(channels)) {
        floatPtr[i] = sin(Float32(i) * 0.1) * 0.5
    }

    // Create block buffer backed by the allocated memory
    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: memory,
        blockLength: totalBytes,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: totalBytes,
        flags: 0,
        blockBufferOut: &blockBuffer
    )
    guard blockStatus == noErr, let block = blockBuffer else {
        memory.deallocate()
        return nil
    }

    // Create sample buffer
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: kCFAllocatorDefault,
        dataBuffer: block,
        formatDescription: formatDesc,
        sampleCount: frameCount,
        presentationTimeStamp: CMTime(value: 0, timescale: CMTimeScale(sampleRate)),
        packetDescriptions: nil,
        sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr else { return nil }

    return sampleBuffer
}

// MARK: - CMSampleBuffer → AVAudioPCMBuffer Conversion Tests

func testMonoConversion() {
    TestRunner.suite("CMSampleBuffer → PCMBuffer: Mono")

    guard let sampleBuffer = createTestAudioSampleBuffer(sampleRate: 48000, channels: 1, frameCount: 1024) else {
        TestRunner.assertTrue(false, "Failed to create test sample buffer")
        return
    }

    let pcmBuffer = sampleBuffer.toAudioPCMBuffer()
    TestRunner.assertNotNil(pcmBuffer, "mono conversion succeeds")

    if let buf = pcmBuffer {
        TestRunner.assertEqual(Int(buf.frameLength), 1024, "frame count matches")
        TestRunner.assertEqual(buf.format.sampleRate, 48000, "sample rate matches")
        TestRunner.assertEqual(Int(buf.format.channelCount), 1, "channel count is 1")
        TestRunner.assertNotNil(buf.floatChannelData, "has float channel data")
    }
}

func testStereoConversion() {
    TestRunner.suite("CMSampleBuffer → PCMBuffer: Stereo")

    guard let sampleBuffer = createTestAudioSampleBuffer(sampleRate: 44100, channels: 2, frameCount: 512) else {
        TestRunner.assertTrue(false, "Failed to create stereo sample buffer")
        return
    }

    let pcmBuffer = sampleBuffer.toAudioPCMBuffer()
    TestRunner.assertNotNil(pcmBuffer, "stereo conversion succeeds")

    if let buf = pcmBuffer {
        TestRunner.assertEqual(Int(buf.frameLength), 512, "frame count matches")
        TestRunner.assertEqual(buf.format.sampleRate, 44100, "sample rate matches")
        TestRunner.assertEqual(Int(buf.format.channelCount), 2, "channel count is 2")
    }
}

func testDifferentSampleRates() {
    TestRunner.suite("CMSampleBuffer → PCMBuffer: Sample Rates")

    let sampleRates: [Float64] = [8000, 16000, 22050, 44100, 48000, 96000]
    for rate in sampleRates {
        guard let sampleBuffer = createTestAudioSampleBuffer(sampleRate: rate, channels: 1, frameCount: 256) else {
            TestRunner.assertTrue(false, "Failed to create buffer at \(rate)Hz")
            continue
        }

        let pcmBuffer = sampleBuffer.toAudioPCMBuffer()
        TestRunner.assertNotNil(pcmBuffer, "conversion at \(rate)Hz succeeds")

        if let buf = pcmBuffer {
            TestRunner.assertEqual(buf.format.sampleRate, rate, "sample rate \(rate) preserved")
        }
    }
}

func testSmallFrameCount() {
    TestRunner.suite("CMSampleBuffer → PCMBuffer: Small Frames")

    guard let sampleBuffer = createTestAudioSampleBuffer(sampleRate: 48000, channels: 1, frameCount: 1) else {
        TestRunner.assertTrue(false, "Failed to create 1-frame buffer")
        return
    }

    let pcmBuffer = sampleBuffer.toAudioPCMBuffer()
    TestRunner.assertNotNil(pcmBuffer, "1-frame conversion succeeds")

    if let buf = pcmBuffer {
        TestRunner.assertEqual(Int(buf.frameLength), 1, "frame count is 1")
    }
}

func testLargeFrameCount() {
    TestRunner.suite("CMSampleBuffer → PCMBuffer: Large Frames")

    guard let sampleBuffer = createTestAudioSampleBuffer(sampleRate: 48000, channels: 1, frameCount: 48000) else {
        TestRunner.assertTrue(false, "Failed to create large buffer")
        return
    }

    let pcmBuffer = sampleBuffer.toAudioPCMBuffer()
    TestRunner.assertNotNil(pcmBuffer, "large frame conversion succeeds")

    if let buf = pcmBuffer {
        TestRunner.assertEqual(Int(buf.frameLength), 48000, "large frame count matches")
    }
}

func testDataIntegrity() {
    TestRunner.suite("CMSampleBuffer → PCMBuffer: Data Integrity")

    guard let sampleBuffer = createTestAudioSampleBuffer(sampleRate: 48000, channels: 1, frameCount: 256) else {
        TestRunner.assertTrue(false, "Failed to create buffer for data integrity test")
        return
    }

    let pcmBuffer = sampleBuffer.toAudioPCMBuffer()
    TestRunner.assertNotNil(pcmBuffer, "conversion succeeds")

    if let buf = pcmBuffer, let channelData = buf.floatChannelData {
        // Verify first sample matches our sine wave generation
        let firstSample = channelData[0][0]
        let expectedFirstSample = sin(Float32(0) * 0.1) * 0.5
        TestRunner.assertEqual(firstSample, expectedFirstSample, "first sample matches source data")

        // Verify a mid-buffer sample
        let midSample = channelData[0][128]
        let expectedMidSample = sin(Float32(128) * 0.1) * 0.5
        TestRunner.assertEqual(midSample, expectedMidSample, "mid-buffer sample matches source data")

        // Verify not all zeros
        var hasNonZero = false
        for i in 0..<Int(buf.frameLength) {
            if channelData[0][i] != 0 {
                hasNonZero = true
                break
            }
        }
        TestRunner.assertTrue(hasNonZero, "buffer contains non-zero audio data")
    }
}

func testMultiChannelConversion() {
    TestRunner.suite("CMSampleBuffer → PCMBuffer: Multi-Channel")

    // Mono and stereo work with interleaved format (standard microphone configurations)
    for channels: UInt32 in [1, 2] {
        guard let sampleBuffer = createTestAudioSampleBuffer(
            sampleRate: 48000, channels: channels, frameCount: 128, interleaved: true
        ) else {
            TestRunner.assertTrue(false, "Failed to create \(channels)-channel buffer")
            continue
        }

        let pcmBuffer = sampleBuffer.toAudioPCMBuffer()
        TestRunner.assertNotNil(pcmBuffer, "\(channels)-channel conversion succeeds")

        if let buf = pcmBuffer {
            TestRunner.assertEqual(Int(buf.format.channelCount), Int(channels), "\(channels)-channel count preserved")
        }
    }

    // Stereo non-interleaved
    guard let stereoNI = createTestAudioSampleBuffer(
        sampleRate: 48000, channels: 2, frameCount: 128, interleaved: false
    ) else {
        TestRunner.assertTrue(false, "Failed to create stereo non-interleaved buffer")
        return
    }
    let stereoNIBuf = stereoNI.toAudioPCMBuffer()
    TestRunner.assertNotNil(stereoNIBuf, "stereo non-interleaved conversion succeeds")
}

// MARK: - SpeechRecognitionError Classification Tests

// Embedded error type for standalone testing
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

/// Classifies kAFAssistantErrorDomain errors the same way SpeechRecognitionService does
func classifyRecognitionError(domain: String, code: Int, description: String) -> SpeechRecognitionError? {
    if domain == "kAFAssistantErrorDomain" && code == 216 {
        return nil // Cancellation — not an error
    } else if domain == "kAFAssistantErrorDomain" && code == 1110 {
        return .siriDisabled
    } else {
        return .recognitionFailed(description)
    }
}

func testErrorClassification() {
    TestRunner.suite("Recognition Error Classification")

    // Code 216 = cancellation, should return nil (not an error)
    let cancelled = classifyRecognitionError(domain: "kAFAssistantErrorDomain", code: 216, description: "cancelled")
    TestRunner.assertNil(cancelled, "code 216 is treated as cancellation (nil)")

    // Code 1110 = Siri/Dictation disabled
    let siriOff = classifyRecognitionError(domain: "kAFAssistantErrorDomain", code: 1110, description: "not enabled")
    TestRunner.assertNotNil(siriOff, "code 1110 returns an error")
    if let err = siriOff {
        if case .siriDisabled = err {
            TestRunner.assertTrue(true, "code 1110 maps to siriDisabled")
        } else {
            TestRunner.assertTrue(false, "code 1110 should map to siriDisabled")
        }
    }

    // Other codes = generic recognition failure
    let otherError = classifyRecognitionError(domain: "kAFAssistantErrorDomain", code: 999, description: "Unknown error")
    TestRunner.assertNotNil(otherError, "other codes return an error")
    if let err = otherError {
        if case .recognitionFailed(let desc) = err {
            TestRunner.assertEqual(desc, "Unknown error", "description preserved in recognitionFailed")
        } else {
            TestRunner.assertTrue(false, "other codes should map to recognitionFailed")
        }
    }

    // Non-kAFAssistant domain
    let otherDomain = classifyRecognitionError(domain: "NSCocoaErrorDomain", code: 216, description: "different domain")
    TestRunner.assertNotNil(otherDomain, "different domain returns error even with code 216")
}

func testErrorDescriptionsAreUserFriendly() {
    TestRunner.suite("Error Descriptions Are User-Friendly")

    let errors: [SpeechRecognitionError] = [
        .recognizerUnavailable,
        .audioEngineFailure("test detail"),
        .recognitionFailed("test detail"),
        .microphoneAccessDenied,
        .speechRecognitionDenied,
        .siriDisabled
    ]

    for error in errors {
        let desc = error.errorDescription ?? ""
        TestRunner.assertFalse(desc.isEmpty, "\(error) has non-empty description")
        // Descriptions should not contain code-level details
        TestRunner.assertFalse(desc.contains("kAFAssistant"), "\(error) description doesn't expose internal domain")
        TestRunner.assertFalse(desc.contains("NSError"), "\(error) description doesn't expose NSError")
    }
}

// MARK: - Entry Point

@main
struct SpeechRecognitionServiceTests {
    static func main() {
        print("🧪 Speech Recognition Service Tests")
        print("==================================================")

        // CMSampleBuffer conversion tests
        testMonoConversion()
        testStereoConversion()
        testDifferentSampleRates()
        testSmallFrameCount()
        testLargeFrameCount()
        testDataIntegrity()
        testMultiChannelConversion()

        // Error classification tests
        testErrorClassification()
        testErrorDescriptionsAreUserFriendly()

        TestRunner.printSummary()
        if TestRunner.failedCount > 0 { exit(1) }
    }
}
