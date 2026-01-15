// MARK: - Context Viewer Sheet
// SwiftUI sheet view for displaying full captured context
//
// ============================================================================
// EXTENSIBILITY GUIDE: Adding New Context Fields
// ============================================================================
// When adding a new field to the Context model (e.g., `ip`, `timestamp`, etc.),
// you must update this file in the following locations:
//
// 1. DISPLAY (UI):
//    - For ContextSource fields: Update `sourceSection` (~line 80)
//    - For new top-level Context fields: Update `body` (~line 22-40)
//    - For new metadata types: Update `metadataSection` switch (~line 128)
//    - For new fields in existing metadata: Update the corresponding view
//      (slackMetadataView, gmailMetadataView, githubMetadataView, genericMetadataView)
//
// 2. COPY FUNCTIONALITY (per-section copy buttons):
//    - For metadata fields: Update `formatMetadata()` (~line 390)
//
// 3. PREVIEWS:
//    - Update `ContextViewerSheet_Previews` to include sample data for new fields
// ============================================================================

import SwiftUI
import AppKit

/// Sheet view displaying the complete captured context
struct ContextViewerSheet: View {
    let context: Context
    let onDismiss: () -> Void

    @State private var copiedSection: String? = nil
    @State private var expandedSections: Set<String> = []
    @State private var escapeMonitor: Any? = nil

    /// Character limit for initial text display (performance optimization)
    private let displayLimit = 5000

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourceSection

                    // EXTENSIBILITY: Add new top-level Context fields here
                    // Example for a new `ip` field:
                    // if let ip = context.ip, !ip.isEmpty {
                    //     textSection(title: "IP Address", content: ip, sectionId: "ip")
                    // }

                    if let selectedText = context.selectedText, !selectedText.isEmpty {
                        textSection(title: "Selected Text", content: selectedText, sectionId: "selected")
                    }

                    metadataSection
                }
                .padding()
            }

            Divider()

            // Footer
            footer
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 500, maxHeight: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Install local event monitor to intercept Escape key before it reaches parent window
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Escape key
                    onDismiss()
                    return nil // Consume the event
                }
                return event
            }
        }
        .onDisappear {
            // Clean up event monitor
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
        }
    }
    
    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("Captured Context")
                .font(.headline)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Escape)")
        }
        .padding()
    }
    
    // MARK: - Source Section
    // EXTENSIBILITY: Add new ContextSource fields here (e.g., ip, deviceId, etc.)

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Source Application", icon: "app.badge")

            VStack(alignment: .leading, spacing: 4) {
                labeledRow(label: "Application", value: context.source.applicationName)
                labeledRow(label: "Bundle ID", value: context.source.bundleIdentifier)

                if let windowTitle = context.source.windowTitle {
                    labeledRow(label: "Window", value: windowTitle)
                }

                if let url = context.source.url {
                    labeledRow(label: "URL", value: url.absoluteString)
                }

                // EXTENSIBILITY: Add new ContextSource fields here
                // Example:
                // if let ip = context.source.ip {
                //     labeledRow(label: "IP Address", value: ip)
                // }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Text Section (reusable)

    private func textSection(title: String, content: String, sectionId: String) -> some View {
        let isExpanded = expandedSections.contains(sectionId)
        let isTruncated = content.count > displayLimit
        let displayContent = (isTruncated && !isExpanded)
            ? String(content.prefix(displayLimit)) + "..."
            : content

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader(title: title, icon: "text.alignleft")
                if isTruncated {
                    Text("(\(content.count.formatted()) chars)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                copyButton(content: content, sectionId: sectionId)
            }

            ScrollView {
                Text(displayContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: isExpanded ? 300 : 150)
            .padding(12)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )

            // Show expand/collapse button for truncated content
            if isTruncated {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedSections.remove(sectionId)
                        } else {
                            expandedSections.insert(sectionId)
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                        Text(isExpanded ? "Show less" : "Show full content")
                            .font(.caption)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Metadata Section
    // EXTENSIBILITY: Add new metadata types here when adding to ContextMetadata enum
    // 1. Add a new case to the switch below
    // 2. Create a corresponding view function (e.g., newAppMetadataView)
    // 3. Update formatMetadata() for copy functionality

    @ViewBuilder
    private var metadataSection: some View {
        switch context.metadata {
        case .slack(let slack):
            slackMetadataView(slack)
        case .gmail(let gmail):
            gmailMetadataView(gmail)
        case .github(let github):
            githubMetadataView(github)
        case .generic(let generic):
            if generic.focusedElementRole != nil || generic.focusedElementLabel != nil {
                genericMetadataView(generic)
            }
        // EXTENSIBILITY: Add new metadata type cases here
        // case .newApp(let newApp):
        //     newAppMetadataView(newApp)
        }
    }

    private func slackMetadataView(_ slack: SlackMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Slack Context", icon: "bubble.left.and.bubble.right")

            VStack(alignment: .leading, spacing: 4) {
                if let channel = slack.channelName {
                    labeledRow(label: "Channel", value: channel)
                }
                labeledRow(label: "Type", value: slack.channelType.rawValue.capitalized)
                if !slack.participants.isEmpty {
                    labeledRow(label: "Participants", value: slack.participants.joined(separator: ", "))
                }
                if !slack.recentMessages.isEmpty {
                    Text("Recent Messages: \(slack.recentMessages.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func gmailMetadataView(_ gmail: GmailMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Gmail Context", icon: "envelope")

            VStack(alignment: .leading, spacing: 4) {
                if let subject = gmail.subject {
                    labeledRow(label: "Subject", value: subject)
                }
                if !gmail.recipients.isEmpty {
                    labeledRow(label: "To", value: gmail.recipients.joined(separator: ", "))
                }
                if !gmail.ccRecipients.isEmpty {
                    labeledRow(label: "CC", value: gmail.ccRecipients.joined(separator: ", "))
                }
                if gmail.isComposing {
                    Text("Currently composing")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func githubMetadataView(_ github: GitHubMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "GitHub Context", icon: "chevron.left.forwardslash.chevron.right")

            VStack(alignment: .leading, spacing: 4) {
                if let repo = github.repoName {
                    labeledRow(label: "Repository", value: repo)
                }
                if let prNumber = github.prNumber {
                    labeledRow(label: "PR", value: "#\(prNumber)")
                }
                if let prTitle = github.prTitle {
                    labeledRow(label: "Title", value: prTitle)
                }
                if let baseBranch = github.baseBranch, let headBranch = github.headBranch {
                    labeledRow(label: "Branches", value: "\(headBranch) → \(baseBranch)")
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func genericMetadataView(_ generic: GenericMetadata) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Element Info", icon: "square.dashed")

            VStack(alignment: .leading, spacing: 4) {
                if let role = generic.focusedElementRole {
                    labeledRow(label: "Element Type", value: role)
                }
                if let label = generic.focusedElementLabel {
                    labeledRow(label: "Label", value: label)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if copiedSection != nil {
                Label("Copied!", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                    .transition(.opacity)
            }

            Spacer()
        }
        .padding()
        .animation(.easeInOut(duration: 0.2), value: copiedSection)
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.primary)
    }

    private func labeledRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func copyButton(content: String, sectionId: String) -> some View {
        Button(action: {
            copyToClipboard(content, sectionId: sectionId)
        }) {
            Image(systemName: copiedSection == sectionId ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundColor(copiedSection == sectionId ? .green : .secondary)
        }
        .buttonStyle(.borderless)
        .help("Copy \(sectionId) text")
    }

    // MARK: - Copy Actions

    private func copyToClipboard(_ content: String, sectionId: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)

        withAnimation {
            copiedSection = sectionId
        }

        // Reset feedback after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                if copiedSection == sectionId {
                    copiedSection = nil
                }
            }
        }
    }

    // EXTENSIBILITY: Update this function when adding new metadata types
    // or new fields to existing metadata types (for copy functionality)
    private func formatMetadata() -> String {
        switch context.metadata {
        case .slack(let slack):
            var lines: [String] = ["Type: Slack"]
            if let channel = slack.channelName {
                lines.append("Channel: \(channel)")
            }
            lines.append("Channel Type: \(slack.channelType.rawValue)")
            if !slack.participants.isEmpty {
                lines.append("Participants: \(slack.participants.joined(separator: ", "))")
            }
            // EXTENSIBILITY: Add new SlackMetadata fields here
            return lines.joined(separator: "\n")

        case .gmail(let gmail):
            var lines: [String] = ["Type: Gmail"]
            if let subject = gmail.subject {
                lines.append("Subject: \(subject)")
            }
            if !gmail.recipients.isEmpty {
                lines.append("To: \(gmail.recipients.joined(separator: ", "))")
            }
            // EXTENSIBILITY: Add new GmailMetadata fields here
            return lines.joined(separator: "\n")

        case .github(let github):
            var lines: [String] = ["Type: GitHub"]
            if let repo = github.repoName {
                lines.append("Repository: \(repo)")
            }
            if let prNumber = github.prNumber {
                lines.append("PR: #\(prNumber)")
            }
            if let prTitle = github.prTitle {
                lines.append("Title: \(prTitle)")
            }
            // EXTENSIBILITY: Add new GitHubMetadata fields here
            return lines.joined(separator: "\n")

        case .generic(let generic):
            var lines: [String] = ["Type: Generic"]
            if let role = generic.focusedElementRole {
                lines.append("Element Type: \(role)")
            }
            if let label = generic.focusedElementLabel {
                lines.append("Label: \(label)")
            }
            // EXTENSIBILITY: Add new GenericMetadata fields here
            return lines.joined(separator: "\n")

        // EXTENSIBILITY: Add new metadata type cases here
        // case .newApp(let newApp):
        //     var lines: [String] = ["Type: NewApp"]
        //     // Add fields...
        //     return lines.joined(separator: "\n")
        }
    }
}

// MARK: - Previews

struct ContextViewerSheet_Previews: PreviewProvider {
    static var previews: some View {
        // Full context preview
        ContextViewerSheet(
            context: Context(
                source: ContextSource(
                    applicationName: "Visual Studio Code",
                    bundleIdentifier: "com.microsoft.VSCode",
                    windowTitle: "ContextViewerSheet.swift - Extremis",
                    url: nil
                ),
                selectedText: "func calculateTotal() -> Double {\n    return items.reduce(0) { $0 + $1.price }\n}",
                metadata: .generic(GenericMetadata(focusedElementRole: "AXTextArea", focusedElementLabel: "Editor"))
            ),
            onDismiss: {}
        )
        .previewDisplayName("Full Context - Code")

        // Slack context preview
        ContextViewerSheet(
            context: Context(
                source: ContextSource(
                    applicationName: "Slack",
                    bundleIdentifier: "com.tinyspeck.slackmacgap",
                    windowTitle: "#engineering - Acme Corp"
                ),
                selectedText: "Can someone review my PR? It's ready for feedback.",
                metadata: .slack(SlackMetadata(
                    channelName: "#engineering",
                    channelType: .channel,
                    participants: ["Alice", "Bob", "Charlie"]
                ))
            ),
            onDismiss: {}
        )
        .previewDisplayName("Slack Context")

        // Minimal context preview
        ContextViewerSheet(
            context: Context(
                source: ContextSource(
                    applicationName: "TextEdit",
                    bundleIdentifier: "com.apple.TextEdit",
                    windowTitle: "Untitled"
                ),
                metadata: .generic(GenericMetadata())
            ),
            onDismiss: {}
        )
        .previewDisplayName("Minimal Context")
    }
}

