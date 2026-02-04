// MARK: - Sound Notification Service
// Plays audio notifications when Extremis is in the background

import AppKit

@MainActor
final class SoundNotificationService {
    static let shared = SoundNotificationService()

    // MARK: - Notification Types

    enum NotificationType {
        case approvalNeeded   // Tool requires human approval
        case responseComplete // LLM finished generating
        case error            // Error or timeout occurred
    }

    // MARK: - Private Properties

    /// Sound used for all notification types
    private let notificationSound = "Funk"

    private init() {}

    // MARK: - Public Interface

    var isEnabled: Bool {
        UserDefaults.standard.soundNotificationsEnabled
    }

    /// Check if user is currently focused on another app
    /// For menu bar apps with non-activating panels, we check if another app is frontmost
    private var isInBackground: Bool {
        // Check if another application is the frontmost (user is focused elsewhere)
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return true // No frontmost app, assume background
        }

        // For menu bar apps with non-activating panels, we're "in background" if
        // another app is the frontmost application (has focus)
        let isExtremisInFront = frontmostApp.bundleIdentifier == Bundle.main.bundleIdentifier
        return !isExtremisInFront
    }

    /// Play a notification sound if enabled and app is in background
    func notify(_ type: NotificationType) {
        guard isEnabled else { return }
        guard isInBackground else { return }

        if let sound = NSSound(named: NSSound.Name(notificationSound)) {
            sound.play()
        }
    }
}
