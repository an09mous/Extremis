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
    let fullArguments: String
    let state: ApprovalState
    var rememberForSession: Bool

    /// Whether this request requires explicit approval every time
    /// If true, "Remember for session" and "Allow All Once" should be hidden
    let requiresExplicitApproval: Bool

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
        // Determine if this request requires explicit approval every time
        // (shell commands with operators or destructive commands)
        let requiresExplicit = Self.checkRequiresExplicitApproval(toolCall: request.toolCall)

        return ApprovalRequestDisplayModel(
            id: request.id,
            toolName: request.toolCall.toolName,
            connectorId: request.toolCall.connectorName,
            argumentsSummary: request.chatToolCall.argumentsSummary,
            fullArguments: request.chatToolCall.fullArguments,
            state: request.state,
            rememberForSession: request.rememberForSession,
            requiresExplicitApproval: requiresExplicit
        )
    }

    /// Check if a tool call requires explicit approval every time
    /// Returns true for shell commands with operators or destructive commands
    private static func checkRequiresExplicitApproval(toolCall: ToolCall) -> Bool {
        // Check if this is a shell command using the same logic as ToolApprovalManager
        let isShellTool = toolCall.connectorID == "shell" ||
                          toolCall.toolName.contains("shell_execute") ||
                          toolCall.originalToolName == "execute"

        guard isShellTool else {
            return false
        }

        // Extract the command from arguments (using the proper JSONValue pattern)
        guard let commandValue = toolCall.arguments["command"],
              case .string(let command) = commandValue else {
            return false
        }

        // Check if the command requires explicit approval
        return ShellCommandClassifier.requiresExplicitApproval(command)
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

    /// Count of dangerous commands requiring explicit approval
    private var dangerousCommandCount: Int {
        pendingRequests.filter { $0.requiresExplicitApproval }.count
    }

    /// Whether there are any safe commands that can be approved with "Allow All Once"
    private var hasSafeCommandsToApprove: Bool {
        pendingRequests.contains { !$0.requiresExplicitApproval }
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
                    .background(DS.Colors.warningSubtle)
                    .continuousCornerRadius(DS.Radii.small)
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

            // Action section - "Allow All Once" only approves SAFE commands
            // Dangerous commands must be approved individually
            if !pendingRequests.isEmpty {
                HStack {
                    // Warning about dangerous commands (if any)
                    if dangerousCommandCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 11))
                            Text("\(dangerousCommandCount) require\(dangerousCommandCount == 1 ? "s" : "") individual review")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .accessibilityLabel("\(dangerousCommandCount) command\(dangerousCommandCount == 1 ? "" : "s") require individual review")
                    }

                    Spacer()

                    // Allow All button - only shown if there are safe commands to approve
                    // Only approves safe commands; dangerous ones remain pending
                    if hasSafeCommandsToApprove {
                        Button(action: {
                            print("🔘 Allow All Once button clicked (will only approve safe commands)")
                            onApproveAll()
                        }) {
                            Label(
                                dangerousCommandCount > 0 ? "Allow Safe Commands" : "Allow All Once",
                                systemImage: "checkmark.circle"
                            )
                            .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                        .keyboardShortcut(.return, modifiers: .option)
                        .help(dangerousCommandCount > 0
                            ? "Option+Return: Allow safe commands only. Dangerous commands need individual approval."
                            : "Option+Return: Allow all tools for this request only")
                        .accessibilityLabel(dangerousCommandCount > 0 ? "Allow safe commands" : ApprovalAccessibility.allowAll)
                        .accessibilityHint(dangerousCommandCount > 0
                            ? "Approves safe commands. Dangerous commands still need individual approval."
                            : "Allows all pending tool requests for this request only")
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(DS.Colors.warningSubtle)
        .continuousCornerRadius(DS.Radii.large)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radii.large, style: .continuous)
                .stroke(DS.Colors.warningBorder, lineWidth: 1)
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

    /// Whether the arguments are expanded to show full content
    @State private var isExpanded: Bool = false

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
                    // Warning badge for dangerous commands
                    if request.requiresExplicitApproval {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 10))
                            .help("This command requires careful review")
                            .accessibilityLabel("Warning: requires careful review")
                    }

                    Text(request.toolName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(request.requiresExplicitApproval ? .red : .primary)

                    Text(request.connectorId)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DS.Colors.hoverSubtle)
                        .continuousCornerRadius(DS.Radii.small)
                        .accessibilityLabel("from \(request.connectorId)")
                }

                if !request.argumentsSummary.isEmpty && request.argumentsSummary != "(no arguments)" {
                    // Expandable arguments section
                    VStack(alignment: .leading, spacing: 4) {
                        Button(action: { isExpanded.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)

                                if isExpanded {
                                    Text("Hide details")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(request.argumentsSummary)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Click to \(isExpanded ? "hide" : "show") full command")

                        // Expanded view with full command
                        if isExpanded {
                            Text(request.fullArguments)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DS.Colors.surfaceElevated)
                                .continuousCornerRadius(DS.Radii.small)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                                        .stroke(DS.Colors.borderMedium, lineWidth: 1)
                                )
                        }
                    }
                    .accessibilityLabel("with arguments: \(request.fullArguments)")
                }
            }

            Spacer()

            // Action buttons (for single request)
            if request.needsAction {
                HStack(spacing: 6) {
                    // Remember checkbox - hidden for commands requiring explicit approval
                    if !request.requiresExplicitApproval {
                        Toggle(isOn: $rememberForSession) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .help("Remember this approval for the session")

                        Text("Remember for session")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    // Deny button
                    Button(action: { onDeny() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .background(DS.Colors.errorSubtle)
                    .continuousCornerRadius(DS.Radii.small)
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
                    .background(DS.Colors.successSubtle)
                    .continuousCornerRadius(DS.Radii.small)
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
        .background(
            request.requiresExplicitApproval
                ? DS.Colors.errorSubtle
                : (isFocused ? Color.orange.opacity(0.1) : DS.Colors.surfacePrimary)
        )
        .continuousCornerRadius(DS.Radii.medium)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radii.medium, style: .continuous)
                .stroke(
                    request.requiresExplicitApproval
                        ? DS.Colors.errorBorder
                        : (isFocused ? DS.Colors.warningBorder : DS.Colors.borderSubtle),
                    lineWidth: 1
                )
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
            .background(DS.Colors.warningSubtle)
            .continuousCornerRadius(DS.Radii.medium)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radii.medium, style: .continuous)
                    .stroke(DS.Colors.warningBorder, lineWidth: 1)
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
            // Full approval view - safe commands (shows "Remember for session" and "Allow All Once")
            ToolApprovalView(
                requests: [
                    ApprovalRequestDisplayModel(
                        id: "1",
                        toolName: "github_search_issues",
                        connectorId: "github-mcp",
                        argumentsSummary: "query=bug, repo=extremis",
                        fullArguments: "query=bug\nrepo=extremis",
                        state: .pending,
                        rememberForSession: false,
                        requiresExplicitApproval: false
                    ),
                    ApprovalRequestDisplayModel(
                        id: "2",
                        toolName: "slack_send_message",
                        connectorId: "slack-mcp",
                        argumentsSummary: "channel=#general, text=Hello",
                        fullArguments: "channel=#general\ntext=Hello world, this is a longer message to test the expanded view",
                        state: .pending,
                        rememberForSession: false,
                        requiresExplicitApproval: false
                    )
                ],
                onApprove: { _, _ in },
                onDeny: { _ in },
                onApproveAll: { }
            )

            Divider()

            // Dangerous command - hides "Remember for session" and "Allow All Once"
            ToolApprovalView(
                requests: [
                    ApprovalRequestDisplayModel(
                        id: "3",
                        toolName: "shell_execute",
                        connectorId: "shell",
                        argumentsSummary: "command=rm -rf /tmp/test",
                        fullArguments: "command=rm -rf /tmp/test",
                        state: .pending,
                        rememberForSession: false,
                        requiresExplicitApproval: true
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
