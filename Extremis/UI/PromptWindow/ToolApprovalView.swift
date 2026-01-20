// MARK: - Tool Approval View
// UI components for human-in-loop tool approval

import SwiftUI

// MARK: - Approval Request Display Model (T3.12)

/// View-friendly model for displaying a tool approval request
struct ApprovalRequestDisplayModel: Identifiable {
    let id: String
    let toolName: String
    let connectorId: String
    let argumentsSummary: String
    let state: ApprovalState
    var rememberForSession: Bool

    /// Icon name based on state
    var stateIcon: String {
        switch state {
        case .pending:
            return "questionmark.circle"
        case .approved:
            return "checkmark.shield.fill"
        case .denied:
            return "xmark.shield.fill"
        case .dismissed:
            return "xmark.circle"
        }
    }

    /// Color based on state
    var stateColor: Color {
        switch state {
        case .pending:
            return .orange
        case .approved:
            return .green
        case .denied, .dismissed:
            return .red
        }
    }

    /// Whether the request needs user action
    var needsAction: Bool {
        if case .pending = state { return true }
        return false
    }

    /// Time since request was made
    var timeSinceRequest: String {
        // For now, just show "Now" since requests are handled immediately
        "Now"
    }

    /// Create from a ToolApprovalRequest
    static func from(_ request: ToolApprovalRequest) -> ApprovalRequestDisplayModel {
        ApprovalRequestDisplayModel(
            id: request.id,
            toolName: request.toolCall.toolName,
            connectorId: request.toolCall.connectorName,
            argumentsSummary: request.chatToolCall.argumentsSummary,
            state: request.state,
            rememberForSession: request.rememberForSession
        )
    }
}

// MARK: - Tool Approval View (T3.10, T3.11)

/// View for approving or denying tool execution requests
struct ToolApprovalView: View {
    /// Requests to approve
    let requests: [ApprovalRequestDisplayModel]

    /// Called when user approves a request
    let onApprove: (String, Bool) -> Void  // (requestId, rememberForSession)

    /// Called when user denies a request
    let onDeny: (String) -> Void

    /// Called when user approves all requests
    let onApproveAll: () -> Void  // One-time approval for all, no remember

    /// Index of currently focused request
    @State private var focusedIndex: Int = 0

    /// Pending requests only
    private var pendingRequests: [ApprovalRequestDisplayModel] {
        requests.filter { $0.needsAction }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.orange)
                    .font(.system(size: 16))
                    .accessibilityHidden(true)

                Text("Tool Approval Required")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                // Count badge
                Text("\(pendingRequests.count) pending")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
                    .accessibilityLabel("\(pendingRequests.count) tools pending approval")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ApprovalAccessibility.approvalRequired)
            .accessibilityAddTraits(.isHeader)

            // Request list
            VStack(spacing: 8) {
                ForEach(Array(pendingRequests.enumerated()), id: \.element.id) { index, request in
                    ApprovalRequestRow(
                        request: request,
                        isFocused: index == focusedIndex,
                        onApprove: { remember in
                            onApprove(request.id, remember)
                        },
                        onDeny: {
                            onDeny(request.id)
                        }
                    )
                }
            }

            // Action section
            if !pendingRequests.isEmpty {
                HStack {
                    Spacer()

                    // Allow All button (one-time approval, no remember)
                    Button(action: {
                        print("🔘 Allow All Once button clicked")
                        onApproveAll()
                    }) {
                        Label("Allow All Once", systemImage: "checkmark.circle")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .keyboardShortcut(.return, modifiers: .option)
                    .help("Option+Return: Allow all tools for this request only")
                    .accessibilityLabel(ApprovalAccessibility.allowAll)
                    .accessibilityHint("Press Option+Return to allow all pending tool requests for this request only")
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool approval dialog with \(pendingRequests.count) pending requests")
    }
}

// MARK: - Approval Request Row

/// Single request row in the approval list
struct ApprovalRequestRow: View {
    let request: ApprovalRequestDisplayModel
    let isFocused: Bool
    let onApprove: (Bool) -> Void  // (rememberForSession) -> Void
    let onDeny: () -> Void

    /// Local state for remember toggle
    @State private var rememberForSession: Bool = false

    /// Accessibility state description
    private var stateDescription: String {
        switch request.state {
        case .pending:
            return "pending approval"
        case .approved:
            return "approved"
        case .denied:
            return "denied"
        case .dismissed:
            return "dismissed"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Tool info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(request.toolName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)

                    Text(request.connectorId)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(3)
                        .accessibilityLabel("from \(request.connectorId)")
                }

                if !request.argumentsSummary.isEmpty && request.argumentsSummary != "(no arguments)" {
                    Text(request.argumentsSummary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityLabel("with arguments: \(request.argumentsSummary)")
                }
            }

            Spacer()

            // Action buttons (for single request)
            if request.needsAction {
                HStack(spacing: 6) {
                    // Remember checkbox
                    Toggle(isOn: $rememberForSession) {
                        EmptyView()
                    }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("Remember this approval for the session")

                    Text("Remember for session")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    // Deny button
                    Button(action: { onDeny() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
                    .help("Deny")
                    .accessibilityLabel(ApprovalAccessibility.denyTool(request.toolName))
                    .accessibilityHint("Denies this tool from executing")

                    // Allow button
                    Button(action: { onApprove(rememberForSession) }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
                    .help(rememberForSession ? "Allow (will remember for session)" : "Allow once")
                    .accessibilityLabel(ApprovalAccessibility.allowTool(request.toolName))
                    .accessibilityHint(rememberForSession ? "Allows this tool and remembers for the session" : "Allows this tool once")
                }
            } else {
                // Show state icon for resolved requests
                Image(systemName: request.stateIcon)
                    .font(.system(size: 14))
                    .foregroundColor(request.stateColor)
                    .accessibilityLabel("Status: \(stateDescription)")
            }
        }
        .padding(10)
        .background(isFocused ? Color.orange.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ApprovalAccessibility.toolPending(request.toolName))
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
    }
}

// MARK: - Inline Approval Banner

/// Compact inline approval banner for chat stream
struct InlineApprovalBanner: View {
    let pendingCount: Int
    let onShowApproval: () -> Void

    var body: some View {
        Button(action: onShowApproval) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                    .accessibilityHidden(true)

                Text("\(pendingCount) tool\(pendingCount == 1 ? "" : "s") awaiting approval")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Text("Review")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pendingCount) tool\(pendingCount == 1 ? "" : "s") awaiting approval. Review now.")
        .accessibilityHint("Opens the tool approval dialog to review and approve or deny pending tool requests")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Accessibility Labels

enum ApprovalAccessibility {
    static let approvalRequired = "Tool approval required"
    static func toolPending(_ name: String) -> String {
        "Tool \(name) is pending approval"
    }
    static func allowTool(_ name: String) -> String {
        "Allow \(name) to execute"
    }
    static func denyTool(_ name: String) -> String {
        "Deny \(name) execution"
    }
    static let allowAll = "Allow all pending tools"
    static let rememberSession = "Remember approvals for the rest of the session"
}

// MARK: - Preview

struct ToolApprovalView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Full approval view
            ToolApprovalView(
                requests: [
                    ApprovalRequestDisplayModel(
                        id: "1",
                        toolName: "github_search_issues",
                        connectorId: "github-mcp",
                        argumentsSummary: "query=bug, repo=extremis",
                        state: .pending,
                        rememberForSession: false
                    ),
                    ApprovalRequestDisplayModel(
                        id: "2",
                        toolName: "slack_send_message",
                        connectorId: "slack-mcp",
                        argumentsSummary: "channel=#general, text=Hello",
                        state: .pending,
                        rememberForSession: false
                    )
                ],
                onApprove: { _, _ in },
                onDeny: { _ in },
                onApproveAll: { }
            )

            Divider()

            // Inline banner
            InlineApprovalBanner(
                pendingCount: 3,
                onShowApproval: {}
            )
        }
        .padding()
        .frame(width: 450)
    }
}
