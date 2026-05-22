// MARK: - Voice Input Indicator
// Mic button component with recording state visualization

import SwiftUI

/// Mic button that reflects VoiceInputManager state with visual feedback
struct VoiceInputIndicator: View {
    @ObservedObject var voiceInput = VoiceInputManager.shared
    @ObservedObject var stealth = StealthManager.shared

    private var isDisabled: Bool {
        voiceInput.state == .requesting || stealth.isStealthActive
    }

    var body: some View {
        Button(action: { voiceInput.toggleRecording() }) {
            micIcon
                .font(.system(size: 16))
                .foregroundColor(iconColor)
                .scaleEffect(voiceInput.state.isRecording ? 1.15 : 1.0)
                .animation(
                    voiceInput.state.isRecording
                        ? DS.Animation.expandCollapse.repeatForever(autoreverses: true)
                        : .default,
                    value: voiceInput.state.isRecording
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(helpText)
    }

    // MARK: - Visual State

    private var micIcon: Image {
        if stealth.isStealthActive {
            return Image(systemName: "mic.slash")
        }
        switch voiceInput.state {
        case .idle, .requesting:
            return Image(systemName: "mic")
        case .recording:
            return Image(systemName: "mic.fill")
        case .error:
            return Image(systemName: "mic.slash")
        }
    }

    private var iconColor: Color {
        if stealth.isStealthActive {
            return .secondary.opacity(0.3)
        }
        switch voiceInput.state {
        case .idle:
            return .secondary
        case .requesting:
            return .secondary.opacity(0.5)
        case .recording:
            return .red
        case .error:
            return .secondary
        }
    }

    private var helpText: String {
        if stealth.isStealthActive {
            return "Voice input disabled in stealth mode"
        }
        switch voiceInput.state {
        case .idle:
            return "Voice input (Option+D)"
        case .requesting:
            return "Requesting permission..."
        case .recording:
            return "Recording... tap to stop"
        case .error(let message):
            return message
        }
    }
}
