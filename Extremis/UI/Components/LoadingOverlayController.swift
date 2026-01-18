// MARK: - Loading Overlay Controller
// Minimalistic floating loading indicator for generation operations

import AppKit
import SwiftUI

/// Controller for displaying a floating loading overlay during generation
@MainActor
final class LoadingOverlayController {
    
    // MARK: - Singleton
    
    static let shared = LoadingOverlayController()
    
    // MARK: - Properties
    
    private var window: NSWindow?
    private var hostingView: NSHostingView<LoadingOverlayView>?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Show the loading overlay
    @MainActor
    func show(message: String = "Generating...") {
        // Hide any existing window first
        hide()
        
        // Create the SwiftUI view
        let overlayView = LoadingOverlayView(message: message)
        hostingView = NSHostingView(rootView: overlayView)
        
        // Create window
        let windowWidth: CGFloat = 160
        let windowHeight: CGFloat = 44
        
        // Position at top-center of main screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.visibleFrame
        let windowX = screenFrame.midX - (windowWidth / 2)
        let windowY = screenFrame.maxY - windowHeight - 60 // 60px from top
        
        let windowFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        
        window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        guard let window = window else { return }
        
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        
        // Animate in
        window.alphaValue = 0
        window.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 1
        }
    }
    
    /// Hide the loading overlay
    @MainActor
    func hide() {
        guard let window = window else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
            self?.hostingView = nil
        })
    }
}

// MARK: - Loading Overlay View

struct LoadingOverlayView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 10) {
            LoadingIndicator(style: .spinning, color: .white, size: 16)
            
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

struct LoadingOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingOverlayView(message: "Generating...")
            .padding()
            .background(Color.gray)
    }
}

