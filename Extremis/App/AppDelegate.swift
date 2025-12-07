// MARK: - App Delegate
// Handles app lifecycle, permissions, menu bar, and hotkey registration

import AppKit
import SwiftUI
import ObjectiveC
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Properties

    /// Menu bar status item
    private var statusItem: NSStatusItem?

    /// Prompt window controller
    private lazy var promptWindowController: PromptWindowController = {
        let controller = PromptWindowController()
        controller.onInsertText = { [weak self] text, source in
            self?.insertText(text, into: source)
        }
        return controller
    }()

    // MARK: - Services

    private let hotkeyManager = HotkeyManager.shared
    private let permissionManager = PermissionManager.shared
    private let contextOrchestrator = ContextOrchestrator.shared
    private let textInserter = TextInserterService.shared

    /// Current captured context
    private var currentContext: Context?

    /// API Key dialog components (kept as instance vars to prevent deallocation)
    private var apiKeyWindow: NSWindow?
    private var apiKeyProviderType: LLMProviderType?
    private var apiKeyInputField: NSTextField?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupMenuBar()
        setupHotkey()
        checkPermissions()

        // Check Ollama connection asynchronously and rebuild menu when done
        checkOllamaAndRefreshMenu()

        print("✅ Extremis launched successfully")
    }

    /// Check Ollama connection and refresh the menu bar
    private func checkOllamaAndRefreshMenu() {
        Task {
            if let ollamaProvider = LLMProviderRegistry.shared.provider(for: .ollama) as? OllamaProvider {
                // Load saved URL if available
                if let savedURL = UserDefaults.standard.string(forKey: "ollama_base_url"), !savedURL.isEmpty {
                    ollamaProvider.updateBaseURL(savedURL)
                }
                let _ = await ollamaProvider.checkConnection()
                // Rebuild menu on main thread after connection check
                await MainActor.run {
                    setupMenuBar()
                }
            }
        }
    }

    /// Setup main menu with Edit menu for keyboard shortcuts
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Extremis", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (required for Cmd+V, Cmd+A, etc.)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        print("👋 Extremis terminating")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Setup

    private func setupMenuBar() {
        // Only create status item once
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Extremis")
            }
        }

        // Rebuild menu
        let menu = NSMenu()
        menu.delegate = self

        let openItem = NSMenuItem(title: "Open Extremis", action: #selector(showPromptWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        // Show active model info (informative, not clickable)
        let activeModelItem = buildActiveModelMenuItem()
        menu.addItem(activeModelItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Extremis", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func buildActiveModelMenuItem() -> NSMenuItem {
        let activeProvider = LLMProviderRegistry.shared.activeProviderType
        let provider = activeProvider.flatMap { LLMProviderRegistry.shared.provider(for: $0) }
        let currentModel = provider?.currentModel

        let providerName = activeProvider?.displayName ?? "None"
        let modelName = currentModel?.name ?? "Not configured"

        let item = NSMenuItem(
            title: "Using \(providerName): \(modelName)",
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = true  // Keep enabled so it doesn't look greyed out
        item.toolTip = "Change provider or model in Preferences"
        return item
    }

    /// Refresh menu bar - called when provider/model changes
    @objc func refreshMenuBar() {
        DispatchQueue.main.async { [weak self] in
            self?.setupMenuBar()
        }
    }

    /// Provider picker window components
    private var providerPickerWindow: NSWindow?
    private var providerPickerPopup: NSPopUpButton?

    @objc private func continueFromProviderPicker(_ sender: NSButton) {
        guard let popup = providerPickerPopup,
              let selectedItem = popup.selectedItem,
              let providerType = selectedItem.representedObject as? LLMProviderType else {
            return
        }

        // Close picker window
        providerPickerWindow?.orderOut(nil)
        providerPickerWindow = nil
        providerPickerPopup = nil

        // Show API key dialog for selected provider
        showAPIKeyDialogForProvider(providerType)
    }

    @objc private func cancelProviderPicker(_ sender: NSButton) {
        providerPickerWindow?.orderOut(nil)
        providerPickerWindow = nil
        providerPickerPopup = nil
    }

    private func showAPIKeyDialogForProvider(_ providerType: LLMProviderType) {
        print("🔧 Configuring API key for: \(providerType.displayName)")

        // Create a proper window for API key input (supports Cmd+V)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configure \(providerType.displayName)"
        window.center()
        window.isReleasedWhenClosed = false  // Prevent crash on close

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))

        // Label
        let label = NSTextField(labelWithString: "Enter your API key for \(providerType.displayName):")
        label.frame = NSRect(x: 20, y: 100, width: 360, height: 20)
        contentView.addSubview(label)

        // Text field (not secure, so user can see what they paste)
        let input = NSTextField(frame: NSRect(x: 20, y: 60, width: 360, height: 24))
        input.placeholderString = "Paste your API key here..."
        input.isEditable = true
        input.isSelectable = true
        contentView.addSubview(input)

        // Buttons
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveAPIKeyFromWindow(_:)))
        saveButton.frame = NSRect(x: 290, y: 15, width: 90, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelAPIKeyWindow(_:)))
        cancelButton.frame = NSRect(x: 190, y: 15, width: 90, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)

        window.contentView = contentView

        // Store references as instance properties
        self.apiKeyWindow = window
        self.apiKeyProviderType = providerType
        self.apiKeyInputField = input

        // Make input the first responder
        window.makeFirstResponder(input)

        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func saveAPIKeyFromWindow(_ sender: NSButton) {
        guard let window = apiKeyWindow,
              let providerType = apiKeyProviderType,
              let input = apiKeyInputField else {
            print("❌ No API key window context")
            return
        }

        let apiKey = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Close and clear references
        window.orderOut(nil)
        self.apiKeyWindow = nil
        self.apiKeyProviderType = nil
        self.apiKeyInputField = nil

        if !apiKey.isEmpty {
            do {
                print("🔧 Saving API key for \(providerType.displayName) (\(providerType.rawValue))")
                try LLMProviderRegistry.shared.configure(providerType, apiKey: apiKey)
                print("🔧 API key saved, now setting as active...")
                try LLMProviderRegistry.shared.setActive(providerType)
                print("🔧 Active provider is now: \(LLMProviderRegistry.shared.activeProviderType?.displayName ?? "none")")
                setupMenuBar() // Refresh menu
                print("✅ Provider \(providerType.displayName) configured and active")
                showAlert(title: "Success", message: "\(providerType.displayName) configured and set as active provider.")
            } catch {
                print("❌ Failed to configure: \(error)")
                showAlert(title: "Error", message: "Failed to configure provider: \(error.localizedDescription)")
            }
        } else {
            print("⚠️ Empty API key, not saving")
        }
    }

    @objc private func cancelAPIKeyWindow(_ sender: NSButton) {
        print("🔧 Cancel button clicked")
        apiKeyWindow?.orderOut(nil)
        apiKeyWindow = nil
        apiKeyProviderType = nil
        apiKeyInputField = nil
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = title == "Error" ? .warning : .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setupHotkey() {
        // Main prompt hotkey: Cmd+Shift+Space
        let promptConfig = HotkeyConfiguration.default
        do {
            try hotkeyManager.register(
                identifier: .prompt,
                configuration: promptConfig
            ) { [weak self] in
                self?.handleHotkeyActivation()
            }
        } catch {
            print("❌ Failed to register prompt hotkey: \(error)")
        }

        // Autocomplete hotkey: Option+Tab
        let autocompleteConfig = HotkeyConfiguration(
            keyCode: UInt32(kVK_Tab),  // Tab key
            modifiers: UInt32(optionKey)  // Option
        )
        do {
            try hotkeyManager.register(
                identifier: .autocomplete,
                configuration: autocompleteConfig
            ) { [weak self] in
                self?.handleAutocompleteActivation()
            }
        } catch {
            print("❌ Failed to register autocomplete hotkey: \(error)")
        }
    }

    private func checkPermissions() {
        if !permissionManager.isAccessibilityEnabled() {
            print("⚠️ Accessibility permission not granted")
            permissionManager.requestAccessibility()
        }
    }

    // MARK: - Actions

    @objc private func menuBarButtonClicked() {
        // Menu handled by statusItem.menu
    }

    @objc private func showPromptWindow() {
        Task { @MainActor in
            await captureContextAndShowPrompt()
        }
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Core Flow

    func handleHotkeyActivation() {
        print("⌨️ Hotkey activated!")

        // Always hide first to ensure clean state, then capture fresh context
        promptWindowController.hidePrompt()

        Task { @MainActor in
            // Small delay to let the previous window close and focus return
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await captureContextAndShowPrompt()
        }
    }

    /// Handle direct autocomplete hotkey - captures context, generates, and inserts automatically
    func handleAutocompleteActivation() {
        print("⚡ Autocomplete hotkey activated!")

        Task { @MainActor in
            await performDirectAutocomplete()
        }
    }

    @MainActor
    private func performDirectAutocomplete() async {
        // Show loading overlay
        LoadingOverlayController.shared.show(message: "Generating...")

        defer {
            // Always hide loading overlay when done
            LoadingOverlayController.shared.hide()
        }

        do {
            print("\n" + String(repeating: "=", count: 60))
            print("⚡ DIRECT AUTOCOMPLETE - Capturing Context...")
            print(String(repeating: "=", count: 60))

            // Capture context
            let context = try await contextOrchestrator.captureContext()
            logCapturedContext(context)

            // Check if provider is configured
            guard let provider = LLMProviderRegistry.shared.activeProvider else {
                print("❌ No LLM provider configured")
                showAutocompleteError("No LLM provider configured")
                return
            }

            print("🤖 Generating autocomplete response...")

            // Generate response using empty instruction (autocomplete mode)
            var generatedText = ""
            for try await chunk in provider.generateStream(instruction: "", context: context) {
                generatedText += chunk
            }

            print("✅ Generated: \(generatedText.prefix(100))...")

            // Insert the generated text
            if !generatedText.isEmpty {
                // Small delay to ensure focus returns to the original app
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                try await textInserter.insert(text: generatedText, into: context.source)
                print("✅ Autocomplete text inserted")
            } else {
                showAutocompleteError("No text generated")
            }

        } catch {
            print("❌ Autocomplete failed: \(error)")
            showAutocompleteError(error.localizedDescription)
        }
    }

    /// Show error notification for autocomplete failures
    private func showAutocompleteError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Autocomplete Failed"
            alert.informativeText = message
            alert.alertStyle = .warning
            let okButton = alert.addButton(withTitle: "OK")
            okButton.keyEquivalent = "\r" // Enter key dismisses

            // Show as a floating alert
            alert.window.level = .floating
            alert.runModal()
        }
    }

    @MainActor
    private func captureContextAndShowPrompt() async {
        do {
            print("\n" + String(repeating: "=", count: 60))
            print("🚀 EXTREMIS ACTIVATED - Capturing Context...")
            print(String(repeating: "=", count: 60))

            // Capture context from the current app
            currentContext = try await contextOrchestrator.captureContext()

            // Log the captured context
            logCapturedContext(currentContext!)

            // Show prompt window with context
            promptWindowController.showPrompt(with: currentContext!)
        } catch {
            print("❌ Failed to capture context: \(error)")
            // Show prompt anyway with minimal context
            let fallbackContext = Context(
                source: ContextSource(
                    applicationName: "Unknown",
                    bundleIdentifier: ""
                )
            )
            promptWindowController.showPrompt(with: fallbackContext)
        }
    }

    /// Log all captured context details
    private func logCapturedContext(_ context: Context) {
        print("\n📋 CAPTURED CONTEXT:")
        print("─────────────────────────────────────────────────────────")

        // Source Information
        print("🖥️  SOURCE APPLICATION:")
        print("    • App Name: \(context.source.applicationName)")
        print("    • Bundle ID: \(context.source.bundleIdentifier)")
        print("    • Window Title: \(context.source.windowTitle ?? "N/A")")
        print("    • URL: \(context.source.url?.absoluteString ?? "N/A")")

        // Selected Text
        print("\n📝 SELECTED TEXT:")
        if let selected = context.selectedText, !selected.isEmpty {
            print("    \"\(selected.prefix(200))\(selected.count > 200 ? "..." : "")\"")
        } else {
            print("    (none)")
        }

        // Preceding Text
        print("\n📄 PRECEDING TEXT:")
        if let preceding = context.precedingText, !preceding.isEmpty {
            print("    \"\(preceding.prefix(200))\(preceding.count > 200 ? "..." : "")\"")
        } else {
            print("    (none)")
        }

        // App-specific Metadata
        print("\n🏷️  METADATA:")
        switch context.metadata {
        case .slack(let slack):
            print("    Type: SLACK")
            print("    • Channel: \(slack.channelName ?? "N/A")")
            print("    • Channel Type: \(slack.channelType.rawValue)")
            print("    • Thread ID: \(slack.threadId ?? "N/A")")
            print("    • Participants: \(slack.participants.isEmpty ? "(none)" : slack.participants.joined(separator: ", "))")
            print("    • Recent Messages (\(slack.recentMessages.count)):")
            for (i, msg) in slack.recentMessages.prefix(5).enumerated() {
                print("      [\(i+1)] \(msg.sender): \"\(msg.content.prefix(100))\(msg.content.count > 100 ? "..." : "")\"")
            }
            if slack.recentMessages.count > 5 {
                print("      ... and \(slack.recentMessages.count - 5) more messages")
            }

        case .gmail(let gmail):
            print("    Type: GMAIL")
            print("    • Subject: \(gmail.subject ?? "N/A")")
            print("    • Recipients: \(gmail.recipients.isEmpty ? "(none)" : gmail.recipients.joined(separator: ", "))")
            print("    • CC: \(gmail.ccRecipients.isEmpty ? "(none)" : gmail.ccRecipients.joined(separator: ", "))")
            print("    • Is Composing: \(gmail.isComposing)")
            print("    • Original Sender: \(gmail.originalSender ?? "N/A")")
            print("    • Thread Messages (\(gmail.threadMessages.count)):")
            for (i, msg) in gmail.threadMessages.prefix(3).enumerated() {
                print("      [\(i+1)] \(msg.sender): \"\(msg.content.prefix(100))...\"")
            }

        case .github(let github):
            print("    Type: GITHUB")
            print("    • Repo: \(github.repoName ?? "N/A")")
            print("    • PR #: \(github.prNumber.map { String($0) } ?? "N/A")")
            print("    • PR Title: \(github.prTitle ?? "N/A")")
            print("    • Base Branch: \(github.baseBranch ?? "N/A")")
            print("    • Head Branch: \(github.headBranch ?? "N/A")")
            print("    • Changed Files (\(github.changedFiles.count)):")
            for file in github.changedFiles.prefix(5) {
                print("      - \(file)")
            }
            print("    • Comments (\(github.comments.count)):")
            for (i, comment) in github.comments.prefix(3).enumerated() {
                print("      [\(i+1)] \(comment.author): \"\(comment.body.prefix(100))...\"")
            }

        case .generic(let generic):
            print("    Type: GENERIC")
            print("    • Focused Element Role: \(generic.focusedElementRole ?? "N/A")")
            print("    • Focused Element Label: \(generic.focusedElementLabel ?? "N/A")")
        }

        print("─────────────────────────────────────────────────────────\n")
    }

    private func insertText(_ text: String, into source: ContextSource) {
        Task {
            do {
                try await textInserter.insert(text: text, into: source)
                print("✅ Text inserted successfully")
            } catch {
                print("❌ Failed to insert text: \(error)")
                // Fallback: copy to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}

