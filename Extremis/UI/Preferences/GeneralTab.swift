// MARK: - General Tab
// General preferences including launch settings

import SwiftUI

struct GeneralTab: View {
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Hotkey Display (read-only)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activation Hotkey")
                            .font(.headline)

                        Text(HotkeyManager.shared.configuration.displayString)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(6)

                        Text("Press this keyboard shortcut anywhere to activate Extremis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Launch at Login
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { newValue in
                                setLaunchAtLogin(newValue)
                            }

                        Text("Automatically start Extremis when you log in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // App Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extremis")
                            .font(.headline)
                        Text("Version 1.0.0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
    }

    // MARK: - Private Methods

    private func loadCurrentSettings() {
        launchAtLogin = UserDefaultsHelper.shared.launchAtLogin
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        UserDefaultsHelper.shared.launchAtLogin = enabled
        print(enabled ? "✅ Launch at login enabled" : "❌ Launch at login disabled")
    }
}

// MARK: - Preview

struct GeneralTab_Previews: PreviewProvider {
    static var previews: some View {
        GeneralTab()
            .frame(width: 450, height: 300)
            .padding()
    }
}

