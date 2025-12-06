// MARK: - Response View
// SwiftUI view for displaying AI-generated response

import SwiftUI

/// View displaying the AI-generated response
struct ResponseView: View {
    let response: String
    let isGenerating: Bool
    let error: String?
    let onInsert: () -> Void
    let onCopy: () -> Void
    let onReprompt: () -> Void
    let onCancel: () -> Void

    @State private var showCopiedToast = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)
                Text("Response")
                    .font(.headline)
                Spacer()

                if isGenerating {
                    LoadingIndicator(style: .spinning)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content area
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let errorMessage = error {
                        ErrorBanner(message: errorMessage)
                    } else if response.isEmpty && isGenerating {
                        GeneratingPlaceholder()
                    } else {
                        Text(response)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Action buttons
            HStack {
                Button(action: onReprompt) {
                    Label("Re-prompt", systemImage: "arrow.uturn.backward")
                }
                .disabled(isGenerating)

                Button(action: {
                    onCopy()
                    showCopiedToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopiedToast = false
                    }
                }) {
                    Label(showCopiedToast ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                }
                .disabled(response.isEmpty || isGenerating)

                Spacer()

                Text("Press Enter to insert")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])

                Button(action: onInsert) {
                    Label("Insert", systemImage: "arrow.down.doc")
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(response.isEmpty || isGenerating)
            }
            .padding()
        }
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.callout)
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Generating Placeholder

struct GeneratingPlaceholder: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 8) {
            LoadingIndicator(style: .dots)
            Text("Generating response\(String(repeating: ".", count: dotCount))")
                .foregroundColor(.secondary)
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 4
        }
    }
}

// MARK: - Preview

struct ResponseView_Previews: PreviewProvider {
    static var previews: some View {
        ResponseView(
            response: "This is a sample AI-generated response that demonstrates how the text will appear.",
            isGenerating: false,
            error: nil,
            onInsert: {},
            onCopy: {},
            onReprompt: {},
            onCancel: {}
        )
        .frame(width: 500, height: 400)
    }
}

