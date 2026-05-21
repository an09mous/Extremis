// MARK: - General Tab
// General preferences including launch settings

import SwiftUI

struct GeneralTab: View {
    @State private var launchAtLogin = false
    @State private var soundNotificationsEnabled = UserDefaults.standard.soundNotificationsEnabled
    @ObservedObject private var stealthManager = StealthManager.shared
    @State private var processDisguise = UserDefaults.standard.stealthProcessDisguise
    @State private var disguiseName = UserDefaults.standard.stealthDisguiseName
    @State private var stealthOpacity = UserDefaults.standard.stealthOpacity
    @State private var stealthVerifyResult: StealthVerifyResult?

    private enum StealthVerifyResult {
        case pass, fail
    }

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
                            .disabled(!LaunchAtLoginService.shared.isAvailable)

                        if LaunchAtLoginService.shared.isAvailable {
                            Text("Automatically start Extremis when you log in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Not available during development. Install app to enable.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Divider()

                    // Sound Notifications
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Sound notifications when in background", isOn: $soundNotificationsEnabled)
                            .onChange(of: soundNotificationsEnabled) { newValue in
                                UserDefaults.standard.soundNotificationsEnabled = newValue
                            }

                        Text("Play audio alerts when Extremis needs attention while in background")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Stealth Mode
                    stealthModeSection

                    Divider()

                    // App Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extremis")
                            .font(.headline)
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
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

    // MARK: - Stealth Mode Section

    @ViewBuilder
    private var stealthModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stealth Mode")
                .font(.headline)

            Toggle("Enable Stealth Mode", isOn: Binding(
                get: { stealthManager.isStealthActive },
                set: { newValue in
                    if newValue {
                        stealthManager.activate()
                    } else {
                        stealthManager.deactivate()
                    }
                }
            ))

            // Shortcuts display
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Toggle Shortcut:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(StealthHotkeyConfig.stealthToggle.displayString)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                HStack {
                    Text("Preferences Shortcut:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(StealthHotkeyConfig.preferences.displayString)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            // Process disguise
            Toggle("Disguise process name", isOn: $processDisguise)
                .onChange(of: processDisguise) { newValue in
                    UserDefaults.standard.stealthProcessDisguise = newValue
                }

            if processDisguise {
                HStack {
                    Text("Process name:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Process name", text: $disguiseName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: 250)
                        .onChange(of: disguiseName) { newValue in
                            UserDefaults.standard.stealthDisguiseName = newValue
                        }
                }
            }

            // Window opacity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Window Opacity:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(stealthOpacity * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Slider(value: $stealthOpacity, in: 0.15...1.0, step: 0.05)
                        .onChange(of: stealthOpacity) { newValue in
                            StealthManager.shared.updateOpacity(newValue)
                        }
                    Image(systemName: "eye")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text("How transparent the window appears in stealth mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Test Stealth button
            HStack(spacing: 8) {
                Button("Test Stealth") {
                    testStealth()
                }

                if let result = stealthVerifyResult {
                    switch result {
                    case .pass:
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Stealth verified")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    case .fail:
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text("Stealth may not be effective on this system")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                }
            }

            // Info text
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Stealth mode hides Extremis from screen sharing, screenshots, and recordings. Use the toggle shortcut to quickly enable/disable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Private Methods

    private func loadCurrentSettings() {
        launchAtLogin = LaunchAtLoginService.shared.isEnabled
        processDisguise = UserDefaults.standard.stealthProcessDisguise
        disguiseName = UserDefaults.standard.stealthDisguiseName
        stealthOpacity = UserDefaults.standard.stealthOpacity
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        LaunchAtLoginService.shared.setEnabled(enabled)
    }

    private func testStealth() {
        let result = StealthVerifier.verify()
        stealthVerifyResult = result ? .pass : .fail
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

