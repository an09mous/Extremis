// MARK: - Providers Tab
// LLM provider configuration

import SwiftUI

struct ProvidersTab: View {
    @State private var selectedProvider: LLMProviderType = .gemini
    @State private var apiKeys: [LLMProviderType: String] = [:]
    @State private var maskedKeys: [LLMProviderType: String] = [:]
    @State private var showingAPIKey: [LLMProviderType: Bool] = [:]
    @State private var statusMessage: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // API Keys Section
            VStack(alignment: .leading, spacing: 12) {
                Text("API Keys")
                    .font(.headline)

                ForEach(LLMProviderType.allCases, id: \.self) { provider in
                    ProviderKeyRow(
                        provider: provider,
                        apiKey: binding(for: provider),
                        maskedKey: maskedKeys[provider] ?? "",
                        isVisible: showBinding(for: provider),
                        isConfigured: isConfigured(provider),
                        isActive: provider == selectedProvider,
                        onSave: { saveAPIKey(for: provider) },
                        onDelete: { deleteAPIKey(for: provider) },
                        onSetActive: { setActiveProvider(provider) }
                    )
                }
            }

            Spacer()

            // Status Message
            if let message = statusMessage {
                HStack {
                    Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundColor(isError ? .orange : .green)
                    Text(message)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            loadCurrentSettings()
        }
    }

    // MARK: - Private Methods

    private func loadCurrentSettings() {
        // Load active provider
        selectedProvider = LLMProviderRegistry.shared.activeProviderType ?? .gemini

        // Load masked keys from keychain for display
        for provider in LLMProviderType.allCases {
            if let key = try? KeychainHelper.shared.retrieveAPIKey(for: provider), !key.isEmpty {
                // Show first 8 and last 4 characters
                if key.count > 12 {
                    let prefix = String(key.prefix(8))
                    let suffix = String(key.suffix(4))
                    maskedKeys[provider] = "\(prefix)...\(suffix)"
                } else {
                    maskedKeys[provider] = "••••••••"
                }
            } else {
                maskedKeys[provider] = ""
            }
            showingAPIKey[provider] = false
            apiKeys[provider] = ""
        }
    }

    private func binding(for provider: LLMProviderType) -> Binding<String> {
        Binding(
            get: { apiKeys[provider] ?? "" },
            set: { apiKeys[provider] = $0 }
        )
    }

    private func showBinding(for provider: LLMProviderType) -> Binding<Bool> {
        Binding(
            get: { showingAPIKey[provider] ?? false },
            set: { showingAPIKey[provider] = $0 }
        )
    }

    private func isConfigured(_ provider: LLMProviderType) -> Bool {
        KeychainHelper.shared.hasAPIKey(for: provider)
    }

    private func activateProvider(_ provider: LLMProviderType) {
        if isConfigured(provider) {
            do {
                try LLMProviderRegistry.shared.setActive(provider)
                withAnimation {
                    statusMessage = "\(provider.displayName) is now active"
                    isError = false
                }
            } catch {
                withAnimation {
                    statusMessage = "Failed to activate \(provider.displayName)"
                    isError = true
                }
            }
        } else {
            withAnimation {
                statusMessage = "Add an API key for \(provider.displayName) first"
                isError = true
            }
        }
    }

    private func saveAPIKey(for provider: LLMProviderType) {
        guard let key = apiKeys[provider], !key.isEmpty else { return }

        do {
            try LLMProviderRegistry.shared.configure(provider, apiKey: key)
            withAnimation {
                statusMessage = "\(provider.displayName) configured successfully"
                isError = false
            }

            // Update masked key display
            if key.count > 12 {
                let prefix = String(key.prefix(8))
                let suffix = String(key.suffix(4))
                maskedKeys[provider] = "\(prefix)...\(suffix)"
            } else {
                maskedKeys[provider] = "••••••••"
            }
            apiKeys[provider] = "" // Clear the input field
        } catch {
            withAnimation {
                statusMessage = "Failed to save API key"
                isError = true
            }
        }
    }

    private func deleteAPIKey(for provider: LLMProviderType) {
        do {
            try KeychainHelper.shared.deleteAPIKey(for: provider)
            maskedKeys[provider] = ""
            apiKeys[provider] = ""
            statusMessage = "\(provider.displayName) key removed"
            isError = false
        } catch {
            statusMessage = "Failed to delete API key"
            isError = true
        }
    }

    private func setActiveProvider(_ provider: LLMProviderType) {
        if isConfigured(provider) {
            do {
                try LLMProviderRegistry.shared.setActive(provider)
                selectedProvider = provider
                statusMessage = "\(provider.displayName) is now active"
                isError = false
            } catch {
                statusMessage = "Failed to activate \(provider.displayName)"
                isError = true
            }
        } else {
            statusMessage = "Add an API key first"
            isError = true
        }
    }
}

// MARK: - Provider Key Row

struct ProviderKeyRow: View {
    let provider: LLMProviderType
    @Binding var apiKey: String
    let maskedKey: String
    @Binding var isVisible: Bool
    let isConfigured: Bool
    let isActive: Bool
    let onSave: () -> Void
    let onDelete: () -> Void
    let onSetActive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider header
            HStack {
                Text(provider.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }

                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }

                Spacer()

                // Use button - only show if configured and not active
                if isConfigured && !isActive {
                    Button("Use") {
                        onSetActive()
                    }
                    .font(.caption)
                }

                // Delete button
                if isConfigured {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Show current key
            if isConfigured && !maskedKey.isEmpty {
                Text("Key: \(maskedKey)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Input for new/update key
            HStack {
                if isVisible {
                    TextField("Enter API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("Enter API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Button(action: { isVisible.toggle() }) {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)

                Button(isConfigured ? "Update" : "Save") { onSave() }
                    .disabled(apiKey.isEmpty)
            }
        }
        .padding(.vertical, 8)
    }
}
