// MARK: - Preferences Window
// Main preferences window with tabs

import SwiftUI
import AppKit

/// Window controller for preferences
final class PreferencesWindowController: NSWindowController {
    
    static let shared = PreferencesWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Extremis Preferences"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .windowBackgroundColor
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        // Register with StealthManager for screen capture exclusion
        StealthManager.shared.registerWindow(window)

        let contentView = PreferencesView()
        window.contentView = NSHostingView(rootView: contentView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Main Preferences View

struct PreferencesView: View {
    @State private var selectedTab = 0
    @ObservedObject private var stealthManager = StealthManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            ProvidersTab()
                .tabItem {
                    Label("Providers", systemImage: "brain")
                }
                .tag(1)

            ConnectorsTab()
                .tabItem {
                    Label("Connectors", systemImage: "puzzlepiece.extension")
                }
                .tag(2)

            CommandsTab()
                .tabItem {
                    Label("Commands", systemImage: "command")
                }
                .tag(3)
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 450)
        .background {
            if stealthManager.isStealthActive {
                ZStack {
                    Color.clear
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(stealthManager.currentOpacity)
                }
                .background(.ultraThinMaterial.opacity(stealthManager.currentOpacity))
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Preview

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
            .frame(width: 500, height: 400)
    }
}

