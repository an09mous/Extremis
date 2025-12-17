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

    var body: some View {
        VStack(spacing: 0) {
            // Context indicator
            if let info = contextInfo, !info.isEmpty {
                ContextBanner(text: info)
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

                // Text input - uses custom view that submits on Enter
                // Empty instruction = autocomplete mode
                SubmittableTextEditor(
                    text: $instructionText,
                    onSubmit: {
                        if !isGenerating {
                            onSubmit()
                        }
                    }
                )
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal)
                .frame(minHeight: 100)

                // Action buttons - Layout: [Provider] ... [Hint] [Cancel] [Summarize?] [Primary Action]
                HStack(spacing: 12) {
                    // Provider indicator (left-aligned info)
                    ProviderIndicator()

                    Spacer()

                    // Hint text - contextual guidance
                    Group {
                        if hasSelection {
                            Text("Enter instruction to transform")
                        } else if hasContext {
                            Text("Enter instruction or summarize")
                        } else {
                            Text("Empty = autocomplete")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

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

                        Button(action: onSubmit) {
                            HStack(spacing: 4) {
                                if isGenerating {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                }
                                Text(primaryButtonLabel(isEmpty: isEmpty))
                            }
                        }
                        .disabled(isGenerating || (hasSelection && isEmpty))
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
    private func primaryButtonLabel(isEmpty: Bool) -> String {
        if isGenerating {
            return "Generating..."
        } else if hasSelection {
            return "Generate"
        } else if isEmpty {
            return "Autocomplete"
        } else {
            return "Generate"
        }
    }
}

// MARK: - Submittable Text Editor (Enter to submit, Shift+Enter for newline)

struct SubmittableTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var text: String
    let onSubmit: () -> Void

    func makeNSView(context: NSViewRepresentableContext<SubmittableTextEditor>) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)

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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
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
            return false
        }
    }
}

// MARK: - Context Banner

struct ContextBanner: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Provider Indicator

struct ProviderIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text(LLMProviderRegistry.shared.activeProviderType?.displayName ?? "No Provider")
                .font(.caption)
                .foregroundColor(.secondary)
        }
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
                onSummarize: {}
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
                onSummarize: {}
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
                onSummarize: {}
            )
            .frame(width: 500, height: 300)
            .previewDisplayName("With Selection")
        }
    }
}

