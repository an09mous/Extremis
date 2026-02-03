// MARK: - GitHub Auth Sheet
// Sheet for configuring GitHub Personal Access Token

import SwiftUI

struct GitHubAuthSheet: View {
    @State private var token: String = ""
    let existingToken: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(existingToken: String? = nil, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.existingToken = existingToken
        self.onSave = onSave
        self.onCancel = onCancel
        // Initialize token state with existing token if available
        _token = State(initialValue: existingToken ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GitHub Personal Access Token")
                .font(.headline)

            SecureField("ghp_xxxxxxxxxxxx", text: $token)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Create at GitHub → Settings → Developer settings → Personal access tokens")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("Requires GitHub Copilot subscription for remote MCP server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(token)
                }
                .disabled(token.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
