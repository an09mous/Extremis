// MARK: - Tool Indicator View
// UI component for displaying tool call execution status in chat

import SwiftUI

/// View showing a single tool call's execution status
struct ToolIndicatorView: View {
    let toolCall: ChatToolCall
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row - always visible
            HStack(spacing: 8) {
                // State icon
                stateIcon
                    .frame(width: 16, height: 16)

                // Tool name
                Text(toolCall.toolName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)

                // Connector badge
                Text(toolCall.connectorName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                Spacer()

                // Duration (if available)
                if let durationStr = toolCall.durationString {
                    Text(durationStr)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Expand/collapse button
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    // Arguments
                    if !toolCall.argumentsSummary.isEmpty && toolCall.argumentsSummary != "(no arguments)" {
                        HStack(alignment: .top, spacing: 4) {
                            Text("Args:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(toolCall.argumentsSummary)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.8))
                        }
                    }

                    // Result or error
                    if let result = toolCall.resultSummary {
                        HStack(alignment: .top, spacing: 4) {
                            Text("Result:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(result)
                                .font(.system(size: 10))
                                .foregroundColor(.primary.opacity(0.8))
                                .lineLimit(3)
                        }
                    }

                    if let error = toolCall.errorMessage {
                        HStack(alignment: .top, spacing: 4) {
                            Text("Error:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.red)
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.8))
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.leading, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    // MARK: - View Components

    @ViewBuilder
    private var stateIcon: some View {
        switch toolCall.state {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        case .pendingApproval:
            Image(systemName: "questionmark.circle")
                .foregroundColor(.orange)
        case .approved:
            Image(systemName: "checkmark.shield")
                .foregroundColor(.green)
        case .denied:
            Image(systemName: "xmark.shield.fill")
                .foregroundColor(.red)
        case .executing:
            // Animated spinner
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .cancelled:
            Image(systemName: "stop.circle")
                .foregroundColor(.secondary)
        }
    }

    private var backgroundColor: Color {
        switch toolCall.state {
        case .pending:
            return Color(NSColor.controlBackgroundColor)
        case .pendingApproval:
            return Color.orange.opacity(0.05)
        case .approved:
            return Color.green.opacity(0.03)
        case .denied:
            return Color.red.opacity(0.05)
        case .executing:
            return Color.blue.opacity(0.05)
        case .completed:
            return Color.green.opacity(0.05)
        case .failed:
            return Color.red.opacity(0.05)
        case .cancelled:
            return Color(NSColor.controlBackgroundColor)
        }
    }

    private var borderColor: Color {
        switch toolCall.state {
        case .pending:
            return Color.secondary.opacity(0.2)
        case .pendingApproval:
            return Color.orange.opacity(0.3)
        case .approved:
            return Color.green.opacity(0.2)
        case .denied:
            return Color.red.opacity(0.3)
        case .executing:
            return Color.blue.opacity(0.3)
        case .completed:
            return Color.green.opacity(0.3)
        case .failed:
            return Color.red.opacity(0.3)
        case .cancelled:
            return Color.secondary.opacity(0.2)
        }
    }
}

// MARK: - Tool Calls Group View

/// View showing multiple tool calls in a collapsible group
struct ToolCallsGroupView: View {
    let toolCalls: [ChatToolCall]
    @State private var isCollapsed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group header
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text("Tool Calls (\(toolCalls.count))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                // Status summary
                statusSummary

                Spacer()

                // Collapse button
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isCollapsed.toggle() } }) {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Tool calls list (when expanded)
            if !isCollapsed {
                VStack(spacing: 6) {
                    ForEach(toolCalls) { toolCall in
                        ToolIndicatorView(toolCall: toolCall)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var statusSummary: some View {
        let completedCount = toolCalls.filter { $0.state == .completed }.count
        let failedCount = toolCalls.filter { $0.state == .failed }.count
        let executingCount = toolCalls.filter { $0.state == .executing }.count
        let pendingApprovalCount = toolCalls.filter { $0.state == .pendingApproval }.count
        let deniedCount = toolCalls.filter { $0.state == .denied || $0.state == .cancelled }.count

        HStack(spacing: 6) {
            if pendingApprovalCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("\(pendingApprovalCount) awaiting")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }

            if executingCount > 0 {
                HStack(spacing: 2) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("\(executingCount) running")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                }
            }

            if completedCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("\(completedCount)")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }

            if failedCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                    Text("\(failedCount)")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }

            if deniedCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "xmark.shield.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                    Text("\(deniedCount) denied")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - Preview

struct ToolIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Single indicators in different states
            ToolIndicatorView(toolCall: ChatToolCall(
                id: "1",
                toolName: "github_search_issues",
                connectorID: "github-mcp-uuid",
                connectorName: "github",
                argumentsSummary: "query=bug, repo=extremis",
                state: .pending
            ))

            ToolIndicatorView(toolCall: ChatToolCall(
                id: "2",
                toolName: "slack_send_message",
                connectorID: "slack-mcp-uuid",
                connectorName: "slack",
                argumentsSummary: "channel=#general, text=Hello",
                state: .executing
            ))

            ToolIndicatorView(toolCall: ChatToolCall(
                id: "3",
                toolName: "github_get_pr",
                connectorID: "github-mcp-uuid",
                connectorName: "github",
                argumentsSummary: "pr_number=123",
                state: .completed,
                resultSummary: "Found PR #123: Add new feature",
                duration: 0.342
            ))

            ToolIndicatorView(toolCall: ChatToolCall(
                id: "4",
                toolName: "api_call",
                connectorID: "custom-api-uuid",
                connectorName: "custom-api",
                argumentsSummary: "endpoint=/users",
                state: .failed,
                errorMessage: "Connection timeout",
                duration: 5.0
            ))

            Divider()

            // Group view
            ToolCallsGroupView(toolCalls: [
                ChatToolCall(id: "1", toolName: "github_search", connectorID: "github-uuid", connectorName: "github", argumentsSummary: "q=test", state: .completed, resultSummary: "5 results", duration: 0.2),
                ChatToolCall(id: "2", toolName: "slack_post", connectorID: "slack-uuid", connectorName: "slack", argumentsSummary: "text=hi", state: .executing),
                ChatToolCall(id: "3", toolName: "jira_create", connectorID: "jira-uuid", connectorName: "jira", argumentsSummary: "title=Bug", state: .pending)
            ])
        }
        .padding()
        .frame(width: 400)
    }
}
