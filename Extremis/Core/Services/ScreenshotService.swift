// MARK: - Screenshot Service
// Captures the screen content behind the Extremis window

import AppKit
import CoreGraphics

/// Service for capturing screenshots of content behind the Extremis floating panel
@MainActor
final class ScreenshotService {

    static let shared = ScreenshotService()

    private init() {}

    // MARK: - Public API

    /// Capture the screen content visible behind the Extremis panel
    /// Uses CGWindowListCreateImage to grab everything below the panel's window level
    /// - Returns: PNG image data of the captured screen, or nil on failure
    func captureScreenBehindPanel() -> Data? {
        // Find the Extremis panel window ID
        guard let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.level == .floating && $0.isVisible }),
              let screenFrame = panel.screen?.frame ?? NSScreen.main?.frame else {
            // Fallback: capture the entire main screen
            return captureFullScreen()
        }

        let windowNumber = CGWindowID(panel.windowNumber)

        // Capture everything on screen below the Extremis panel
        // .optionOnScreenBelowWindow excludes the specified window and everything above it
        guard let cgImage = CGWindowListCreateImage(
            screenFrame,
            .optionOnScreenBelowWindow,
            windowNumber,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return captureFullScreen()
        }

        return pngData(from: cgImage)
    }

    // MARK: - Private Helpers

    /// Fallback: capture the entire main display
    private func captureFullScreen() -> Data? {
        guard let screen = NSScreen.main else { return nil }

        guard let cgImage = CGWindowListCreateImage(
            screen.frame,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return nil
        }

        return pngData(from: cgImage)
    }

    /// Convert CGImage to PNG Data
    private func pngData(from cgImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
