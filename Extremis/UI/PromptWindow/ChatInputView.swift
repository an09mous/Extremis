// MARK: - Chat Input View
// Text input field for sending chat messages with image attachment support

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// View for entering and sending chat messages
struct ChatInputView: View {
    @Binding var text: String
    @Binding var pendingAttachments: [ImageAttachment]
    let isEnabled: Bool
    let isGenerating: Bool
    let placeholder: String
    let autoFocus: Bool
    let supportsVision: Bool
    let onSend: () -> Void
    var onStopGeneration: (() -> Void)?
    /// Called when user attempts to paste an image but the model doesn't support vision
    var onNonVisionPasteAttempt: (() -> Void)?

    @State private var isFocused: Bool = false
    @State private var imageError: String?
    @State private var imageErrorDismissId: UUID = UUID()
    @State private var isDropTargeted: Bool = false

    init(
        text: Binding<String>,
        pendingAttachments: Binding<[ImageAttachment]> = .constant([]),
        isEnabled: Bool = true,
        isGenerating: Bool = false,
        placeholder: String = "Type a follow-up message...",
        autoFocus: Bool = false,
        supportsVision: Bool = false,
        onSend: @escaping () -> Void,
        onStopGeneration: (() -> Void)? = nil,
        onNonVisionPasteAttempt: (() -> Void)? = nil
    ) {
        self._text = text
        self._pendingAttachments = pendingAttachments
        self.isEnabled = isEnabled
        self.isGenerating = isGenerating
        self.placeholder = placeholder
        self.autoFocus = autoFocus
        self.supportsVision = supportsVision
        self.onSend = onSend
        self.onStopGeneration = onStopGeneration
        self.onNonVisionPasteAttempt = onNonVisionPasteAttempt
    }

    // Track the actual content height from NSTextView
    @State private var contentHeight: CGFloat = 20

    private let minHeight: CGFloat = 20
    private let maxHeight: CGFloat = 100

    private var textHeight: CGFloat {
        min(max(minHeight, contentHeight), maxHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail strip for pending attachments
            if !pendingAttachments.isEmpty {
                ImageAttachmentView(
                    attachments: pendingAttachments,
                    onRemove: { id in
                        pendingAttachments.removeAll { $0.id == id }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }

            // Brief image error message
            if let errorMsg = imageError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text(errorMsg)
                        .font(.system(size: 11))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Attachment button (only when vision is supported)
                if supportsVision {
                    Button(action: openFilePicker) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(pendingAttachments.count >= ImageProcessor.shared.maxImagesPerMessage)
                    .help(pendingAttachments.count >= ImageProcessor.shared.maxImagesPerMessage
                          ? "Maximum \(ImageProcessor.shared.maxImagesPerMessage) images"
                          : "Attach image")
                }

                // Scrollable text input using NSTextView for performance
                ScrollableChatTextEditor(
                    text: $text,
                    placeholder: placeholder,
                    isEnabled: isEnabled,
                    autoFocus: autoFocus,
                    isFocused: $isFocused,
                    contentHeight: $contentHeight,
                    onSend: { sendIfReady() },
                    onPasteImage: supportsVision ? { imageData in
                        processAndAttachImage(data: imageData, sourceType: .clipboard)
                    } : nil,
                    onPasteImageBlocked: !supportsVision ? {
                        onNonVisionPasteAttempt?()
                    } : nil
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
                    Button(action: sendIfReady) {
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
            .padding(.vertical, 4)
        }
        .background(.thinMaterial)
        .continuousCornerRadius(DS.Radii.pill)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radii.pill, style: .continuous)
                .stroke(isFocused ? DS.Colors.borderFocused : DS.Colors.borderMedium, lineWidth: 1)
                .animation(DS.Animation.hoverTransition, value: isFocused)
        )
        .dsShadow(DS.Shadows.medium)
        .overlay {
            if supportsVision && isDropTargeted {
                ImageDropZoneView()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
            }
        }
        .onDrop(of: [.image], isTargeted: supportsVision ? $isDropTargeted : .constant(false)) { providers in
            guard supportsVision else { return false }
            handleDroppedItems(providers)
            return true
        }
    }

    // MARK: - Drag and Drop

    private func handleDroppedItems(_ providers: [NSItemProvider]) {
        let remaining = ImageProcessor.shared.maxImagesPerMessage - pendingAttachments.count
        guard remaining > 0 else {
            showImageError("Maximum \(ImageProcessor.shared.maxImagesPerMessage) images per message")
            return
        }

        for provider in providers.prefix(remaining) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                guard let data = data else { return }
                DispatchQueue.main.async {
                    self.processAndAttachImage(data: data, sourceType: .dragAndDrop)
                }
            }
        }
    }

    // MARK: - File Picker

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ImageProcessor.supportedUTTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select images to attach"

        // Apply stealth to file picker if stealth mode is active
        if StealthManager.shared.isStealthActive {
            panel.sharingType = .none
        }

        let remaining = ImageProcessor.shared.maxImagesPerMessage - pendingAttachments.count
        guard remaining > 0 else {
            showImageError("Maximum \(ImageProcessor.shared.maxImagesPerMessage) images per message")
            return
        }

        guard panel.runModal() == .OK else { return }

        for url in panel.urls.prefix(remaining) {
            guard let data = try? Data(contentsOf: url) else { continue }
            processAndAttachImage(data: data, sourceType: .filePicker, filename: url.lastPathComponent)
        }
    }

    // MARK: - Image Processing

    private func processAndAttachImage(data: Data, sourceType: ImageSourceType, filename: String? = nil) {
        // Check max images limit
        guard pendingAttachments.count < ImageProcessor.shared.maxImagesPerMessage else {
            showImageError("Maximum \(ImageProcessor.shared.maxImagesPerMessage) images per message")
            return
        }

        do {
            let attachment = try ImageProcessor.shared.process(data: data, sourceType: sourceType, originalFilename: filename)
            pendingAttachments.append(attachment)
            imageError = nil
        } catch let error as ImageProcessingError {
            switch error {
            case .unsupportedFormat:
                showImageError("Unsupported image format")
            case .inputTooLarge(let size):
                let mbSize = Double(size) / 1_048_576.0
                showImageError("Image too large (\(String(format: "%.1f", mbSize))MB, max 10MB)")
            case .processingFailed:
                showImageError("Failed to process image")
            case .outputTooLarge:
                showImageError("Processed image too large")
            }
        } catch {
            showImageError("Failed to attach image")
        }
    }

    private func showImageError(_ message: String) {
        imageError = message
        let dismissId = UUID()
        imageErrorDismissId = dismissId
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if imageErrorDismissId == dismissId {
                imageError = nil
            }
        }
    }

    // MARK: - Send Logic

    private func sendIfReady() {
        guard canSend else { return }
        onSend()
        text = ""
        contentHeight = minHeight
    }

    private var canSend: Bool {
        guard isEnabled else { return false }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !pendingAttachments.isEmpty
        return hasText || hasImages
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
    /// Called when an image is pasted from clipboard (only set when vision is supported)
    var onPasteImage: ((Data) -> Void)?
    /// Called when an image paste is attempted but vision is not supported
    var onPasteImageBlocked: (() -> Void)?

    /// Custom NSTextView subclass that intercepts paste to detect images
    class ImageAwareTextView: NSTextView {
        var onPasteImage: ((Data) -> Void)?
        var onPasteImageBlocked: (() -> Void)?

        /// Pasteboard types that indicate image content
        private static let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
        ]

        /// Intercept Cmd+V at the key equivalent level since paste: doesn't fire
        /// in nonactivating panel windows (no standard Edit menu)
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == "v" {
                if handleImagePaste() {
                    return true  // Consumed — image was handled
                }
            }
            return super.performKeyEquivalent(with: event)
        }

        /// Also override paste: for cases where it IS called (e.g., Edit menu, right-click > Paste)
        override func paste(_ sender: Any?) {
            if handleImagePaste() {
                return  // Consumed
            }
            super.paste(sender)
        }

        /// Shared image paste logic — returns true if an image was detected and handled
        private func handleImagePaste() -> Bool {
            let pasteboard = NSPasteboard.general

            guard Self.pasteboardHasImage(pasteboard) else { return false }

            if let onPasteImage {
                // Vision supported — extract and handle image
                if let imageData = Self.extractImageData(from: pasteboard) {
                    onPasteImage(imageData)
                }
                // Also paste any text alongside the image
                if let textContent = pasteboard.string(forType: .string), !textContent.isEmpty {
                    insertText(textContent, replacementRange: selectedRange())
                }
                return true
            } else if let onPasteImageBlocked {
                // Vision not supported — notify user
                onPasteImageBlocked()
                // Still allow text paste if available
                if pasteboard.string(forType: .string) != nil {
                    // Can't call super.paste from here, so insert text directly
                    if let text = pasteboard.string(forType: .string) {
                        insertText(text, replacementRange: selectedRange())
                    }
                }
                return true
            }

            return false  // No image handler set, let default handle it
        }

        static func pasteboardHasImage(_ pasteboard: NSPasteboard) -> Bool {
            for type in imageTypes {
                if pasteboard.data(forType: type) != nil {
                    return true
                }
            }
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: [UTType.image.identifier]
            ]) as? [URL], !urls.isEmpty {
                return true
            }
            return false
        }

        static func extractImageData(from pasteboard: NSPasteboard) -> Data? {
            // Primary: use NSImage which handles all macOS pasteboard formats natively
            // then convert to PNG for reliable downstream processing
            if let image = NSImage(pasteboard: pasteboard),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let pngData = rep.representation(using: .png, properties: [:]) {
                    return pngData
                }
            }
            // Fallback: try raw pasteboard data for specific types
            for type in imageTypes {
                if let data = pasteboard.data(forType: type) {
                    return data
                }
            }
            // Fallback: try image file URLs on pasteboard
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingContentsConformToTypes: [UTType.image.identifier]
            ]) as? [URL], let url = urls.first {
                return try? Data(contentsOf: url)
            }
            return nil
        }
    }

    func makeNSView(context: NSViewRepresentableContext<ScrollableChatTextEditor>) -> NSScrollView {
        // Use the standard factory to get a properly wired scroll view + text view
        let scrollView = ImageAwareTextView.scrollableTextView()
        let standardTextView = scrollView.documentView as! NSTextView

        // Replace the standard NSTextView with our ImageAwareTextView subclass,
        // reusing the existing (properly wired) text container from the factory
        let textView = ImageAwareTextView(frame: standardTextView.frame, textContainer: standardTextView.textContainer)
        textView.minSize = standardTextView.minSize
        textView.maxSize = standardTextView.maxSize
        textView.isVerticallyResizable = standardTextView.isVerticallyResizable
        textView.isHorizontallyResizable = standardTextView.isHorizontallyResizable
        textView.autoresizingMask = standardTextView.autoresizingMask

        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        // Set image paste handlers
        textView.onPasteImage = onPasteImage
        textView.onPasteImageBlocked = onPasteImageBlocked

        // Replace document view with our subclass
        scrollView.documentView = textView
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
        guard let textView = scrollView.documentView as? ImageAwareTextView else { return }

        // Update text only if different to avoid cursor jump
        if textView.string != text {
            textView.string = text
        }

        // Always editable so user can type while generating
        textView.isEditable = true

        // Update coordinator's isEnabled state for Enter key handling
        context.coordinator.isEnabled = isEnabled

        // Update image paste handlers
        textView.onPasteImage = onPasteImage
        textView.onPasteImageBlocked = onPasteImageBlocked

        // Update placeholder visibility
        context.coordinator.updatePlaceholderVisibility(isEmpty: text.isEmpty)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFocused: $isFocused,
            contentHeight: $contentHeight,
            isEnabled: isEnabled,
            onSend: onSend
        )
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

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            contentHeight: Binding<CGFloat>,
            isEnabled: Bool,
            onSend: @escaping () -> Void
        ) {
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
        .padding(.vertical, 3)
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
