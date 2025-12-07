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
    @State private var ollamaConnected = false
    @State private var ollamaBaseURL = "http://127.0.0.1:11434"
    @State private var ollamaModels: [LLMModel] = []
    @State private var ollamaSelectedModelId: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // API Keys Section
            VStack(alignment: .leading, spacing: 12) {
                Text("LLM Providers")
                    .font(.headline)

                ForEach(LLMProviderType.allCases, id: \.self) { provider in
                    if provider == .ollama {
                        OllamaProviderRow(
                            isConnected: $ollamaConnected,
                            baseURL: $ollamaBaseURL,
                            availableModels: $ollamaModels,
                            selectedModelId: $ollamaSelectedModelId,
                            isActive: provider == selectedProvider,
                            onCheckConnection: { checkOllamaConnection() },
                            onSetActive: { setActiveProvider(provider) },
                            onSelectModel: { model in selectOllamaModel(model) }
                        )
                    } else {
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
            if provider == .ollama {
                // Load Ollama settings
                if let savedURL = UserDefaults.standard.string(forKey: "ollama_base_url"), !savedURL.isEmpty {
                    ollamaBaseURL = savedURL
                }
                // Auto-check Ollama connection to get models
                checkOllamaConnection()
                continue
            }

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
        if provider == .ollama {
            return ollamaConnected
        }
        return KeychainHelper.shared.hasAPIKey(for: provider)
    }

    private func checkOllamaConnection() {
        Task {
            if let ollamaProvider = LLMProviderRegistry.shared.provider(for: .ollama) as? OllamaProvider {
                // Always update base URL to ensure provider has current value
                UserDefaults.standard.set(ollamaBaseURL, forKey: "ollama_base_url")
                ollamaProvider.updateBaseURL(ollamaBaseURL)

                let connected = await ollamaProvider.checkConnection()

                await MainActor.run {
                    ollamaConnected = connected
                    if connected {
                        // Update models list and selected model from provider
                        // (fetchAvailableModels already restores saved model selection)
                        ollamaModels = ollamaProvider.availableModelsFromServer
                        ollamaSelectedModelId = ollamaProvider.currentModel.id
                    } else {
                        ollamaModels = []
                    }
                }
            }
        }
    }

    private func selectOllamaModel(_ model: LLMModel) {
        LLMProviderRegistry.shared.setModel(model, for: .ollama)
        ollamaSelectedModelId = model.id
        refreshMenuBar()
    }

    /// Refresh menu bar to reflect provider/model changes
    private func refreshMenuBar() {
        DispatchQueue.main.async {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.refreshMenuBar()
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
                refreshMenuBar()  // Update menu bar
                statusMessage = "\(provider.displayName) is now active"
                isError = false
            } catch {
                statusMessage = "Failed to activate \(provider.displayName)"
                isError = true
            }
        } else {
            if provider == .ollama {
                statusMessage = "Check connection to Ollama server first"
            } else {
                statusMessage = "Add an API key first"
            }
            isError = true
        }
    }
}

// MARK: - Ollama Provider Row

struct OllamaProviderRow: View {
    @Binding var isConnected: Bool
    @Binding var baseURL: String
    @Binding var availableModels: [LLMModel]
    @Binding var selectedModelId: String
    let isActive: Bool
    let onCheckConnection: () -> Void
    let onSetActive: () -> Void
    let onSelectModel: (LLMModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider header
            HStack {
                Text("Ollama (Local)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
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

                // Use button - only show if connected and not active
                if isConnected && !isActive {
                    Button("Use") {
                        onSetActive()
                    }
                    .font(.caption)
                }
            }

            // Connection status
            Text(isConnected ? "Server connected" : "Server not available")
                .font(.caption)
                .foregroundColor(isConnected ? .secondary : .red)

            // Base URL input and check connection
            HStack {
                TextField("Server URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)

                Button("Check Connection") {
                    onCheckConnection()
                }
            }

            // Model selection - only show if connected and models available
            if isConnected && !availableModels.isEmpty {
                HStack {
                    Text("Model:")
                        .font(.caption)

                    Picker("", selection: $selectedModelId) {
                        ForEach(availableModels, id: \.id) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selectedModelId) { newValue in
                        if let model = availableModels.first(where: { $0.id == newValue }) {
                            onSelectModel(model)
                        }
                    }
                }
            } else if isConnected && availableModels.isEmpty {
                Text("No models found. Run 'ollama pull <model>' to download.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Text("Default: http://127.0.0.1:11434")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
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
