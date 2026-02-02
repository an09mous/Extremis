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
        window.center()
        window.isReleasedWhenClosed = false
        
        super.init(window: window)
        
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
    }
}

// MARK: - Preview

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
            .frame(width: 500, height: 400)
    }
}

