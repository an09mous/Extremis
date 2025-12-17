// MARK: - Chat Input View
// Text input field for sending chat messages

import SwiftUI

/// View for entering and sending chat messages
struct ChatInputView: View {
    @Binding var text: String
    let isEnabled: Bool
    let placeholder: String
    let autoFocus: Bool
    let onSend: () -> Void

    // Use local state for the TextField to avoid binding issues
    @State private var localText: String = ""
    @FocusState private var isFocused: Bool

    init(
        text: Binding<String>,
        isEnabled: Bool = true,
        placeholder: String = "Type a follow-up message...",
        autoFocus: Bool = false,
        onSend: @escaping () -> Void
    ) {
        self._text = text
        self.isEnabled = isEnabled
        self.placeholder = placeholder
        self.autoFocus = autoFocus
        self.onSend = onSend
    }

    var body: some View {
        HStack(spacing: 8) {
            // Text field - uses onSubmit for Enter key handling
            TextField(placeholder, text: $localText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isFocused)
                .disabled(!isEnabled)
                .onSubmit {
                    sendIfNotEmpty()
                }
                .onChange(of: localText) { _ in
                    // Sync local state to binding
                    text = localText
                }
                .onChange(of: text) { newValue in
                    // Sync binding to local state (for external clears)
                    if newValue != localText {
                        localText = newValue
                    }
                }
                .onAppear {
                    localText = text
                    // Auto-focus the text field if requested
                    if autoFocus {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isFocused = true
                        }
                    }
                }

            // Send button
            Button(action: sendIfNotEmpty) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(canSend ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send message (Enter)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private func sendIfNotEmpty() {
        guard !localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSend()
        // Clear local state immediately - this will propagate to binding via onChange
        localText = ""
    }

    private var canSend: Bool {
        isEnabled && !localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
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

