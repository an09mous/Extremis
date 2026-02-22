// MARK: - Prompt View
// SwiftUI view for user instruction input

import SwiftUI
import AppKit

/// Main prompt view for entering instructions
struct PromptInputView: View {
    @Binding var instructionText: String
    @Binding var isGenerating: Bool
    let contextInfo: String?
    let hasContext: Bool  // Has any text context (for Summarize button)
    let hasSelection: Bool  // Has specifically selected text (for hint text)
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onSummarize: () -> Void
    var onViewContext: (() -> Void)? = nil  // Optional callback to view full context

    // Command palette support
    @StateObject private var commandPaletteVM = CommandPaletteViewModel()
    @State private var showCommandPalette = false
    var onExecuteCommand: ((Command) -> Void)? = nil

    // Image attachment support
    var supportsImages: Bool = false
    @Binding var stagedAttachments: [MessageAttachment]
    var onPasteImage: (() -> Void)?
    var onPickImages: (([URL]) -> Void)?
    var onRemoveAttachment: ((UUID) -> Void)?

    @State private var isDragTargeted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Context indicator
            if let info = contextInfo, !info.isEmpty {
                ContextBanner(text: info, onViewContext: onViewContext)
            }

            // Instruction input area
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    Text("What would you like me to help with?")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)

                // Text input with command palette - uses custom view that submits on Enter
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        // Staged attachments bar (above text input)
                        if !stagedAttachments.isEmpty {
                            StagedAttachmentsBar(
                                attachments: stagedAttachments,
                                onRemove: { id in onRemoveAttachment?(id) }
                            )
                        }

                        HStack(alignment: .top, spacing: 8) {
                            // Attach image button (only when model supports images)
                            if supportsImages {
                                Button(action: openFilePicker) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Attach image")
                                .padding(.top, 6)
                            }

                            SubmittableTextEditor(
                                text: $instructionText,
                                onSubmit: {
                                    if showCommandPalette, let command = commandPaletteVM.selectedCommand() {
                                        selectCommand(command)
                                    } else if !isGenerating {
                                        onSubmit()
                                    }
                                },
                                onTextChange: { text in
                                    handleTextChange(text)
                                },
                                onArrowUp: showCommandPalette ? { commandPaletteVM.moveSelectionUp() } : nil,
                                onArrowDown: showCommandPalette ? { commandPaletteVM.moveSelectionDown() } : nil,
                                onEscape: showCommandPalette ? { showCommandPalette = false } : nil,
                                onPasteImage: supportsImages ? onPasteImage : nil
                            )
                        }
                    }
                    .padding(12)
                    .background(.thinMaterial)
                    .continuousCornerRadius(DS.Radii.large)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radii.large, style: .continuous)
                            .stroke(isDragTargeted ? DS.Colors.borderFocused : DS.Colors.borderMedium, lineWidth: isDragTargeted ? 2 : 1)
                    )
                    .dsShadow(DS.Shadows.subtle)
                    .onDrop(of: [.fileURL], isTargeted: supportsImages ? $isDragTargeted : .constant(false)) { providers in
                        guard supportsImages else { return false }
                        return handleDrop(providers: providers)
                    }

                    // Command palette overlay
                    if showCommandPalette {
                        CommandPaletteView(
                            viewModel: commandPaletteVM,
                            onSelect: { command in
                                selectCommand(command)
                            },
                            onDismiss: {
                                showCommandPalette = false
                            }
                        )
                        .offset(y: 50) // Position below text input
                        .zIndex(100)
                    }
                }
                .padding(.horizontal)
                .frame(minHeight: 100)

                // Action buttons - Layout: [Hint] ... [Cancel] [Summarize?] [Primary Action]
                HStack(spacing: 12) {
                    // Hint text - contextual guidance (left-aligned)
                    Group {
                        Text("Enter your instruction")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Spacer()

                    // Action buttons group (right-aligned)
                    HStack(spacing: 8) {
                        Button("Cancel") {
                            onCancel()
                        }
                        .keyboardShortcut(.escape, modifiers: [])

                        // Summarize button (secondary action, shown when context exists)
                        if hasContext {
                            Button(action: onSummarize) {
                                Label("Summarize", systemImage: "doc.text.magnifyingglass")
                            }
                            .disabled(isGenerating)
                            .help("Summarize text context (quick action)")
                        }

                        // Primary action button
                        let isEmpty = instructionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        let hasImages = !stagedAttachments.isEmpty

                        Button(action: onSubmit) {
                            HStack(spacing: 4) {
                                if isGenerating {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                }
                                Text(primaryButtonLabel())
                            }
                        }
                        .disabled(isGenerating || (hasSelection && isEmpty && !hasImages))
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
    }

    // Helper to determine primary button label
    private func primaryButtonLabel() -> String {
        if isGenerating {
            return "Generating..."
        } else {
            return "Generate"
        }
    }

    // MARK: - Command Palette Helpers

    private func handleTextChange(_ text: String) {
        // Check if text starts with / and doesn't contain spaces (command mode)
        // Only show command palette when there's selected text (commands operate on selection)
        if hasSelection && text.hasPrefix("/") && !text.contains(" ") {
            let filter = String(text.dropFirst())
            commandPaletteVM.setFilter(filter)
            showCommandPalette = true
        } else {
            showCommandPalette = false
        }
    }

    private func selectCommand(_ command: Command) {
        showCommandPalette = false
        instructionText = ""  // Clear the /command text
        onExecuteCommand?(command)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK {
                onPickImages?(panel.urls)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    if let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            self.onPickImages?([url])
                        }
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Submittable Text Editor (Enter to submit, Shift+Enter for newline)

struct SubmittableTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var text: String
    let onSubmit: () -> Void
    var onTextChange: ((String) -> Void)? = nil
    var onArrowUp: (() -> Void)? = nil
    var onArrowDown: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil
    var onPasteImage: (() -> Void)? = nil

    /// Custom NSTextView that overrides paste: to intercept image paste via Cmd+V
    class ImagePasteTextView: NSTextView {
        var onPasteImage: (() -> Void)?

        override func paste(_ sender: Any?) {
            if let onPasteImage = onPasteImage, ImageProcessor.pasteboardHasImage() {
                onPasteImage()
                return
            }
            super.paste(sender)
        }
    }

    func makeNSView(context: NSViewRepresentableContext<SubmittableTextEditor>) -> NSScrollView {
        // Build text system from scratch with our custom text view
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = ImagePasteTextView(frame: .zero, textContainer: textContainer)
        textView.onPasteImage = onPasteImage
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Focus the text view
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: NSViewRepresentableContext<SubmittableTextEditor>) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
        // Update coordinator with current callbacks
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onArrowUp = onArrowUp
        context.coordinator.onArrowDown = onArrowDown
        context.coordinator.onEscape = onEscape
        context.coordinator.onPasteImage = onPasteImage
        // Keep onPasteImage callback in sync on the text view
        if let imagePasteTV = textView as? ImagePasteTextView {
            imagePasteTV.onPasteImage = onPasteImage
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onTextChange: onTextChange, onArrowUp: onArrowUp, onArrowDown: onArrowDown, onEscape: onEscape, onPasteImage: onPasteImage)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSubmit: () -> Void
        var onTextChange: ((String) -> Void)?
        var onArrowUp: (() -> Void)?
        var onArrowDown: (() -> Void)?
        var onEscape: (() -> Void)?
        var onPasteImage: (() -> Void)?

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onTextChange: ((String) -> Void)?, onArrowUp: (() -> Void)?, onArrowDown: (() -> Void)?, onEscape: (() -> Void)?, onPasteImage: (() -> Void)? = nil) {
            _text = text
            self.onSubmit = onSubmit
            self.onTextChange = onTextChange
            self.onArrowUp = onArrowUp
            self.onArrowDown = onArrowDown
            self.onEscape = onEscape
            self.onPasteImage = onPasteImage
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            onTextChange?(textView.string)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Intercept Enter key
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Check if Shift is pressed
                let shiftPressed = NSEvent.modifierFlags.contains(.shift)

                if shiftPressed {
                    // Shift+Enter: insert newline
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    // Enter alone: submit
                    onSubmit()
                    return true
                }
            }

            // Handle arrow keys for command palette navigation
            if commandSelector == #selector(NSResponder.moveUp(_:)), let onArrowUp = onArrowUp {
                onArrowUp()
                return true
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)), let onArrowDown = onArrowDown {
                onArrowDown()
                return true
            }

            // Handle Escape for dismissing command palette
            if commandSelector == #selector(NSResponder.cancelOperation(_:)), let onEscape = onEscape {
                onEscape()
                return true
            }

            return false
        }
    }
}

// MARK: - Context Banner

struct ContextBanner: View {
    let text: String
    var onViewContext: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()

            // View button (only if callback provided)
            if let onViewContext = onViewContext {
                Button(action: onViewContext) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("View full context")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(DS.Colors.surfaceSecondary)
    }
}

// MARK: - Preview

struct PromptInputView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Without any context
            PromptInputView(
                instructionText: .constant(""),
                isGenerating: .constant(false),
                contextInfo: "TextEdit - Untitled",
                hasContext: false,
                hasSelection: false,
                onSubmit: {},
                onCancel: {},
                onSummarize: {},
                onViewContext: nil,
                stagedAttachments: .constant([])
            )
            .frame(width: 500, height: 300)
            .previewDisplayName("No Context")

            // With context but no selection (preceding/succeeding text)
            PromptInputView(
                instructionText: .constant(""),
                isGenerating: .constant(false),
                contextInfo: "TextEdit - Untitled (cursor context)",
                hasContext: true,
                hasSelection: false,
                onSubmit: {},
                onCancel: {},
                onSummarize: {},
                onViewContext: { print("View context tapped") },
                stagedAttachments: .constant([])
            )
            .frame(width: 500, height: 300)
            .previewDisplayName("With Context (No Selection)")

            // With selection (shows Summarize button)
            PromptInputView(
                instructionText: .constant(""),
                isGenerating: .constant(false),
                contextInfo: "TextEdit - Untitled (text selected: Lorem ipsum...)",
                hasContext: true,
                hasSelection: true,
                onSubmit: {},
                onCancel: {},
                onSummarize: {},
                onViewContext: { print("View context tapped") },
                stagedAttachments: .constant([])
            )
            .frame(width: 500, height: 300)
            .previewDisplayName("With Selection")
        }
    }
}

// MARK: - Context Banner Preview

struct ContextBanner_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContextBanner(text: "TextEdit - Untitled (text selected: Lorem ipsum...)")
                .previewDisplayName("Without View Button")

            ContextBanner(
                text: "TextEdit - Untitled (text selected: Lorem ipsum...)",
                onViewContext: { print("View tapped") }
            )
            .previewDisplayName("With View Button")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}

