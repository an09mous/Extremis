// MARK: - Conversation List View
// Sidebar view for displaying and managing conversation sessions

import SwiftUI

/// Sidebar view showing list of conversation sessions
struct ConversationListView: View {
    @ObservedObject var conversationManager: ConversationManager
    let onSelectConversation: (UUID) -> Void
    let onNewSession: () -> Void
    let onDeleteConversation: (UUID) -> Void

    @State private var conversations: [ConversationIndexEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sessions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Conversation list
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else if conversations.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No sessions yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(conversations) { entry in
                            ConversationRowView(
                                entry: entry,
                                isActive: entry.id == conversationManager.currentConversationId,
                                onSelect: { onSelectConversation(entry.id) },
                                onDelete: { onDeleteConversation(entry.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 180)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadConversations()
        }
        .onChange(of: conversationManager.conversationListVersion) { _ in
            loadConversations()
        }
        .onChange(of: conversationManager.currentConversationId) { _ in
            // Force re-render when active conversation changes
            // The ForEach already checks isActive, but this ensures update propagates
        }
    }

    private func loadConversations() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let list = try await conversationManager.listConversations()
                await MainActor.run {
                    // Sort by updatedAt descending (most recent first)
                    conversations = list.sorted { $0.updatedAt > $1.updatedAt }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load sessions"
                    isLoading = false
                }
            }
        }
    }

    /// Refresh the conversation list (call after changes)
    func refresh() {
        loadConversations()
    }
}

// MARK: - Conversation Row View

struct ConversationRowView: View {
    let entry: ConversationIndexEntry
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 0) {
                // Active indicator bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, 4)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                            .foregroundColor(isActive ? .primary : .secondary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(formatDate(entry.updatedAt))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            Text("•")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)

                            Text("\(entry.messageCount) msgs")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Delete button (shown on hover)
                    if isHovering && !isActive {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete session")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : (isHovering ? Color.secondary.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

struct ConversationListView_Previews: PreviewProvider {
    static var previews: some View {
        ConversationListView(
            conversationManager: ConversationManager.shared,
            onSelectConversation: { _ in },
            onNewSession: {},
            onDeleteConversation: { _ in }
        )
        .frame(height: 400)
    }
}
