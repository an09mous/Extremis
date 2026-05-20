// MARK: - Stealth Toast Controller
// Transient toast notification for stealth mode toggle feedback

import AppKit
import SwiftUI

/// Manages the brief "Stealth On"/"Stealth Off" toast notification
@MainActor
final class StealthToastController {

    // MARK: - Singleton

    static let shared = StealthToastController()

    // MARK: - Properties

    private var toastWindow: NSWindow?
    private var dismissWorkItem: DispatchWorkItem?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Show a toast message that auto-dismisses after ~1 second
    func showToast(message: String) {
        // Cancel any existing toast
        dismissWorkItem?.cancel()
        dismissExistingToast()

        // Create the SwiftUI view
        let toastView = StealthToastView(message: message)
        let hostingView = NSHostingView(rootView: toastView)

        // Window dimensions
        let windowWidth: CGFloat = 180
        let windowHeight: CGFloat = 40

        // Position at top-center of main screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let windowX = screenFrame.midX - (windowWidth / 2)
        let windowY = screenFrame.maxY - windowHeight - 80

        let windowFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)

        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient]

        // Register with StealthManager so the toast itself is invisible to screen capture
        StealthManager.shared.registerWindow(window)

        self.toastWindow = window

        // Fade in
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 1
        }

        // Auto-dismiss after 1 second
        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOutToast()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    // MARK: - Private Methods

    private func fadeOutToast() {
        guard let window = toastWindow else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.toastWindow?.orderOut(nil)
            self?.toastWindow = nil
        })
    }

    private func dismissExistingToast() {
        toastWindow?.orderOut(nil)
        toastWindow = nil
    }
}

// MARK: - Stealth Toast View

struct StealthToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            IncognitoIcon(size: 16)
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DS.Radii.medium, style: .continuous)
                .fill(Color.black.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radii.medium, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Incognito Icon

/// Custom hat + glasses incognito icon drawn with SwiftUI shapes
struct IncognitoIcon: View {
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let scale = s / 24.0 // Design on 24x24 grid

            // Hat brim - wide ellipse
            let brimRect = CGRect(
                x: 1 * scale,
                y: 9 * scale,
                width: 22 * scale,
                height: 4 * scale
            )
            let brim = Path(ellipseIn: brimRect)
            context.fill(brim, with: .foreground)

            // Hat crown - rounded rectangle
            var crown = Path()
            let crownX = 6 * scale
            let crownY = 2 * scale
            let crownW = 12 * scale
            let crownH = 9 * scale
            let crownR = 3 * scale
            crown.addRoundedRect(
                in: CGRect(x: crownX, y: crownY, width: crownW, height: crownH),
                cornerSize: CGSize(width: crownR, height: crownR)
            )
            context.fill(crown, with: .foreground)

            // Left lens - circle
            let lensY = 14 * scale
            let lensR = 4.2 * scale
            let leftLens = Path(ellipseIn: CGRect(
                x: 2.5 * scale, y: lensY,
                width: lensR * 2, height: lensR * 2
            ))
            context.fill(leftLens, with: .foreground)

            // Right lens - circle
            let rightLens = Path(ellipseIn: CGRect(
                x: 24 * scale - 2.5 * scale - lensR * 2, y: lensY,
                width: lensR * 2, height: lensR * 2
            ))
            context.fill(rightLens, with: .foreground)

            // Bridge between lenses
            var bridge = Path()
            bridge.move(to: CGPoint(x: 10.9 * scale, y: (lensY + lensR)))
            bridge.addQuadCurve(
                to: CGPoint(x: 13.1 * scale, y: (lensY + lensR)),
                control: CGPoint(x: 12 * scale, y: lensY - 0.5 * scale)
            )
            context.stroke(bridge, with: .foreground, lineWidth: 1.5 * scale)
        }
        .frame(width: size, height: size)
    }
}
