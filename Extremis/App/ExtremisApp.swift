// MARK: - Extremis App Entry Point
// Main application entry point - pure AppKit for menu bar app

import AppKit

// Use NSApplicationMain approach for menu bar apps
@main
struct ExtremisApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        // Set activation policy to accessory (menu bar app)
        app.setActivationPolicy(.accessory)

        // Run the app
        app.run()
    }
}

