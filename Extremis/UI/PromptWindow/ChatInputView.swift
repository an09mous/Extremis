// MARK: - Chat Input View
// Text input field for sending chat messages

import SwiftUI
import AppKit

/// View for entering and sending chat messages
struct ChatInputView: View {
    @Binding var text: String
    let isEnabled: Bool
    let isGenerating: Bool
    let placeholder: String
    let autoFocus: Bool
    let onSend: () -> Void
    var onStopGeneration: (() -> Void)?

    @State private var isFocused: Bool = false

    init(
        text: Binding<String>,
        isEnabled: Bool = true,
        isGenerating: Bool = false,
        placeholder: String = "Type a follow-up message...",
        autoFocus: Bool = false,
        onSend: @escaping () -> Void,
        onStopGeneration: (() -> Void)? = nil
    ) {
        self._text = text
        self.isEnabled = isEnabled
        self.isGenerating = isGenerating
        self.placeholder = placeholder
        self.autoFocus = autoFocus
        self.onSend = onSend
        self.onStopGeneration = onStopGeneration
    }

    // Track the actual content height from NSTextView
    @State private var contentHeight: CGFloat = 20

    private let minHeight: CGFloat = 20
    private let maxHeight: CGFloat = 100

    private var textHeight: CGFloat {
        min(max(minHeight, contentHeight), maxHeight)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Scrollable text input using NSTextView for performance
            ScrollableChatTextEditor(
                text: $text,
                placeholder: placeholder,
                isEnabled: isEnabled,
                autoFocus: autoFocus,
                isFocused: $isFocused,
                contentHeight: $contentHeight,
                onSend: { sendIfNotEmpty() }
            )
            .frame(height: textHeight)

            // Show stop button when generating, otherwise show send button
            if isGenerating {
                Button(action: { onStopGeneration?() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Stop generating")
            } else {
                Button(action: sendIfNotEmpty) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(canSend ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send message (Enter)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DS.Colors.surfacePrimary)
        .continuousCornerRadius(DS.Radii.pill)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radii.pill, style: .continuous)
                .stroke(isFocused ? DS.Colors.borderFocused : DS.Colors.borderSubtle, lineWidth: 1)
                .animation(DS.Animation.hoverTransition, value: isFocused)
        )
        .dsShadow(DS.Shadows.subtle)
    }

    private func sendIfNotEmpty() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSend()
        text = ""
        // Reset content height to minimum when text is cleared
        contentHeight = minHeight
    }

    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Scrollable Chat Text Editor (NSTextView-based for performance)

struct ScrollableChatTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool
    let autoFocus: Bool
    @Binding var isFocused: Bool
    @Binding var contentHeight: CGFloat
    let onSend: () -> Void

    func makeNSView(context: NSViewRepresentableContext<ScrollableChatTextEditor>) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true  // Always editable so user can type while generating
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        // Setup placeholder
        context.coordinator.setupPlaceholder(textView: textView, placeholder: placeholder)

        // Auto-focus if requested
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: NSViewRepresentableContext<ScrollableChatTextEditor>) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update text only if different to avoid cursor jump
        if textView.string != text {
            textView.string = text
        }

        // Always editable so user can type while generating
        textView.isEditable = true

        // Update coordinator's isEnabled state for Enter key handling
        context.coordinator.isEnabled = isEnabled

        // Update placeholder visibility
        context.coordinator.updatePlaceholderVisibility(isEmpty: text.isEmpty)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, contentHeight: $contentHeight, isEnabled: isEnabled, onSend: onSend)
    }

    // Custom NSTextField that passes through mouse clicks to the text view behind it
    class ClickThroughTextField: NSTextField {
        override func hitTest(_ point: NSPoint) -> NSView? {
            // Return nil to let clicks pass through to the NSTextView behind
            return nil
        }
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        @Binding var contentHeight: CGFloat
        var isEnabled: Bool
        let onSend: () -> Void
        private var placeholderLabel: NSTextField?

        init(text: Binding<String>, isFocused: Binding<Bool>, contentHeight: Binding<CGFloat>, isEnabled: Bool, onSend: @escaping () -> Void) {
            _text = text
            _isFocused = isFocused
            _contentHeight = contentHeight
            self.isEnabled = isEnabled
            self.onSend = onSend
        }

        func setupPlaceholder(textView: NSTextView, placeholder: String) {
            let label = ClickThroughTextField(labelWithString: placeholder)
            label.textColor = .placeholderTextColor
            label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            label.isEditable = false
            label.isSelectable = false
            label.drawsBackground = false
            label.isBordered = false
            textView.addSubview(label)
            label.frame.origin = NSPoint(x: 5, y: 2)
            placeholderLabel = label
        }

        func updatePlaceholderVisibility(isEmpty: Bool) {
            placeholderLabel?.isHidden = !isEmpty
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updatePlaceholderVisibility(isEmpty: textView.string.isEmpty)
            updateContentHeight(textView: textView)
        }

        func updateContentHeight(textView: NSTextView) {
            // Force layout to ensure we get accurate measurements
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)

            // Get the used rect from the layout manager which accounts for wrapped text
            if let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer {
                let usedRect = layoutManager.usedRect(for: textContainer)
                let newHeight = usedRect.height + 4  // Add small padding
                DispatchQueue.main.async {
                    self.contentHeight = newHeight
                }
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Intercept Enter key to send
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let shiftPressed = NSEvent.modifierFlags.contains(.shift)
                if shiftPressed {
                    // Shift+Enter: insert newline
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    // Enter alone: send message (only if enabled, i.e. not generating)
                    if isEnabled {
                        onSend()
                    }
                    return true  // Always consume Enter to prevent newline insertion
                }
            }

            return false
        }
    }
}

/// Compact inline chat input for the response view footer
struct InlineChatInputView: View {
    @Binding var text: String
    let isEnabled: Bool
    let onSend: () -> Void

    // Use local state for the TextField to avoid binding issues
    @State private var localText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .foregroundColor(.secondary)
                .font(.caption)

            TextField("Ask a follow-up...", text: $localText)
                .textFieldStyle(.plain)
                .font(.callout)
                .disabled(!isEnabled)
                .onSubmit {
                    sendIfNotEmpty()
                }
                .onChange(of: localText) { _ in
                    text = localText
                }
                .onChange(of: text) { newValue in
                    if newValue != localText {
                        localText = newValue
                    }
                }
                .onAppear {
                    localText = text
                }

            if !localText.isEmpty {
                Button(action: sendIfNotEmpty) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.Colors.surfaceElevated)
        .continuousCornerRadius(DS.Radii.xLarge)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radii.xLarge, style: .continuous)
                .stroke(DS.Colors.borderMedium, lineWidth: 1)
        )
    }

    private func sendIfNotEmpty() {
        guard !localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSend()
        localText = ""
    }
}

// MARK: - Preview

struct ChatInputView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ChatInputView(
                text: .constant(""),
                isEnabled: true,
                onSend: { print("Send tapped") }
            )

            ChatInputView(
                text: .constant("Hello, can you help me?"),
                isEnabled: true,
                onSend: { print("Send tapped") }
            )

            ChatInputView(
                text: .constant(""),
                isEnabled: false,
                onSend: { print("Send tapped") }
            )

            Divider()

            InlineChatInputView(
                text: .constant(""),
                isEnabled: true,
                onSend: { print("Send tapped") }
            )

            InlineChatInputView(
                text: .constant("Follow-up question"),
                isEnabled: true,
                onSend: { print("Send tapped") }
            )
        }
        .padding()
        .frame(width: 400)
    }
}
