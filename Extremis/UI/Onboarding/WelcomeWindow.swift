// MARK: - Welcome Window
// Onboarding screen shown on first launch to explain accessibility permissions

import SwiftUI
import AppKit

// MARK: - Welcome View

struct WelcomeView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with gradient
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Welcome to Extremis")
                    .font(.system(size: 28, weight: .bold))
                
                Text("Your AI-powered writing assistant")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 32)
            
            // Features list
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    icon: "text.cursor",
                    iconColor: .blue,
                    title: "Context-Aware",
                    description: "Reads text around your cursor to understand what you're writing"
                )
                
                FeatureRow(
                    icon: "wand.and.stars",
                    iconColor: .purple,
                    title: "AI-Powered",
                    description: "Generates helpful suggestions using your preferred LLM"
                )
                
                FeatureRow(
                    icon: "keyboard",
                    iconColor: .orange,
                    title: "Quick Access",
                    description: "Press ⌘⇧Space anywhere to summon Extremis"
                )
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Permission explanation
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised.circle.fill")
                        .foregroundColor(.blue)
                    Text("Accessibility Permission Required")
                        .font(.headline)
                }
                
                Text("To read and insert text, Extremis needs accessibility access.\nYour data stays private — only sent to your configured AI provider.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 24)
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: onSkip) {
                    Text("Set Up Later")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Welcome Window Controller

final class WelcomeWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<WelcomeView>?

    /// Callback when user completes onboarding
    var onComplete: (() -> Void)?

    func show() {
        // Create the window if needed
        if window == nil {
            let welcomeView = WelcomeView(
                onContinue: { [weak self] in
                    self?.handleContinue()
                },
                onSkip: { [weak self] in
                    self?.handleSkip()
                }
            )

            hostingView = NSHostingView(rootView: welcomeView)

            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )

            window?.contentView = hostingView
            window?.title = "Welcome to Extremis"
            window?.titlebarAppearsTransparent = true
            window?.titleVisibility = .hidden
            window?.isReleasedWhenClosed = false
            window?.center()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func handleContinue() {
        // Mark as shown
        UserDefaultsHelper.shared.hasShownAccessibilityPrompt = true
        close()

        // Request accessibility permission
        PermissionManager.shared.requestAccessibility()
        onComplete?()
    }

    private func handleSkip() {
        // Mark as shown
        UserDefaultsHelper.shared.hasShownAccessibilityPrompt = true
        close()

        print("ℹ️ User chose to set up accessibility later")
        onComplete?()
    }
}

// MARK: - Preview

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(onContinue: {}, onSkip: {})
    }
}

