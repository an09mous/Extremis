// MARK: - Auto-Expanding Text Input
// Reusable auto-expanding text input component for instruction and follow-up inputs

import SwiftUI
import AppKit

/// Auto-expanding text input that starts compact and grows with content
/// Used for both initial instruction input and follow-up messages
struct AutoExpandingTextInput: View {
    @Binding var text: String
    let placeholder: String
    let minLines: Int
    let maxLines: Int
    let isEnabled: Bool
    let autoFocus: Bool
    let onSubmit: () -> Void

    @State private var isFocused: Bool = false
    @State private var contentHeight: CGFloat = 20

    private var lineHeight: CGFloat { 20 }

    private var minHeight: CGFloat {
        CGFloat(minLines) * lineHeight
    }

    private var maxHeight: CGFloat {
        CGFloat(maxLines) * lineHeight
    }

    private var textHeight: CGFloat {
        min(max(minHeight, contentHeight), maxHeight)
    }

    init(
        text: Binding<String>,
        placeholder: String = "Enter instruction...",
        minLines: Int = 1,
        maxLines: Int = 5,
        isEnabled: Bool = true,
        autoFocus: Bool = true,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.minLines = minLines
        self.maxLines = maxLines
        self.isEnabled = isEnabled
        self.autoFocus = autoFocus
        self.onSubmit = onSubmit
    }

    var body: some View {
        AutoExpandingTextEditor(
            text: $text,
            placeholder: placeholder,
            isEnabled: isEnabled,
            autoFocus: autoFocus,
            isFocused: $isFocused,
            contentHeight: $contentHeight,
            onSubmit: onSubmit
        )
        .frame(height: textHeight)
        .padding(12)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Auto-Expanding Text Editor (NSTextView-based)

struct AutoExpandingTextEditor: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool
    let autoFocus: Bool
    @Binding var isFocused: Bool
    @Binding var contentHeight: CGFloat
    let onSubmit: () -> Void

    func makeNSView(context: NSViewRepresentableContext<AutoExpandingTextEditor>) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = isEnabled
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

    func updateNSView(_ scrollView: NSScrollView, context: NSViewRepresentableContext<AutoExpandingTextEditor>) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update text only if different to avoid cursor jump
        if textView.string != text {
            textView.string = text
            context.coordinator.updateContentHeight(textView: textView)
        }

        textView.isEditable = isEnabled

        // Update placeholder visibility
        context.coordinator.updatePlaceholderVisibility(isEmpty: text.isEmpty)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, contentHeight: $contentHeight, onSubmit: onSubmit)
    }

    // Custom NSTextField that passes through mouse clicks to the text view behind it
    class ClickThroughTextField: NSTextField {
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var isFocused: Bool
        @Binding var contentHeight: CGFloat
        let onSubmit: () -> Void
        private var placeholderLabel: NSTextField?

        init(text: Binding<String>, isFocused: Binding<Bool>, contentHeight: Binding<CGFloat>, onSubmit: @escaping () -> Void) {
            _text = text
            _isFocused = isFocused
            _contentHeight = contentHeight
            self.onSubmit = onSubmit
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
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)

            if let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer {
                let usedRect = layoutManager.usedRect(for: textContainer)
                let newHeight = usedRect.height + 4
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
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let shiftPressed = NSEvent.modifierFlags.contains(.shift)
                if shiftPressed {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    onSubmit()
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Preview

struct AutoExpandingTextInput_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AutoExpandingTextInput(
                text: .constant(""),
                placeholder: "Enter instruction...",
                minLines: 1,
                maxLines: 4,
                onSubmit: {}
            )

            AutoExpandingTextInput(
                text: .constant("Fix the typo"),
                placeholder: "Enter instruction...",
                minLines: 1,
                maxLines: 4,
                onSubmit: {}
            )

            AutoExpandingTextInput(
                text: .constant("This is a longer instruction that might wrap to multiple lines when the user types more content into the field."),
                placeholder: "Enter instruction...",
                minLines: 1,
                maxLines: 4,
                onSubmit: {}
            )
        }
        .padding()
        .frame(width: 400)
    }
}
