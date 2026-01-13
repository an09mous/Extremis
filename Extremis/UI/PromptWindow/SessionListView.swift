// MARK: - Session List View
// Sidebar view for displaying and managing sessions

import SwiftUI

/// Sidebar view showing list of sessions
struct SessionListView: View {
    @ObservedObject var sessionManager: SessionManager
    let onSelectSession: (UUID) -> Void
    let onNewSession: () -> Void
    let onDeleteSession: (UUID) -> Void

    @State private var sessions: [SessionIndexEntry] = []
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

            // Session list
            if isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else if sessions.isEmpty && !sessionManager.hasDraftSession {
                // Show empty state only if no draft AND no saved sessions
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
                        // Draft session row (if exists)
                        if sessionManager.hasDraftSession {
                            DraftSessionRow(
                                isActive: true,  // Draft is always the current session
                                isDisabled: sessionManager.isAnySessionGenerating,
                                onSelect: { /* Already active, no-op */ }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }

                        // Persisted sessions
                        ForEach(sessions) { entry in
                            SessionRowView(
                                entry: entry,
                                // Not active if we have a draft (draft takes precedence)
                                isActive: !sessionManager.hasDraftSession && entry.id == sessionManager.currentSessionId,
                                isDisabled: sessionManager.isAnySessionGenerating && entry.id != sessionManager.generatingSessionId,
                                onSelect: { onSelectSession(entry.id) },
                                onDelete: { onDeleteSession(entry.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: sessionManager.hasDraftSession)
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
            loadSessions(showLoading: sessions.isEmpty)
        }
        .onChange(of: sessionManager.sessionListVersion) { _ in
            loadSessions()
        }
        .onChange(of: sessionManager.currentSessionId) { _ in
            // Force re-render when active session changes
            // The ForEach already checks isActive, but this ensures update propagates
        }
        .onChange(of: sessionManager.hasDraftSession) { _ in
            // Force re-render when draft state changes
        }
    }

    private func loadSessions(showLoading: Bool = false) {
        // Only show loading indicator on initial load, not on incremental updates
        if showLoading {
            isLoading = true
        }
        errorMessage = nil

        Task {
            do {
                let list = try await sessionManager.listSessions()
                await MainActor.run {
                    // Sort by updatedAt descending (most recent first)
                    sessions = list.sorted { $0.updatedAt > $1.updatedAt }
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

    /// Refresh the session list (call after changes)
    func refresh() {
        loadSessions()
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let entry: SessionIndexEntry
    let isActive: Bool
    let isDisabled: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    // Static formatters to avoid creating new instances on every render
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        Button(action: {
            // Only allow selection if not disabled
            if !isDisabled {
                onSelect()
            }
        }) {
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
                            .foregroundColor(isDisabled ? .secondary.opacity(0.5) : (isActive ? .primary : .secondary))
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text(formatDate(entry.updatedAt))
                                .font(.system(size: 10))
                                .foregroundColor(isDisabled ? .secondary.opacity(0.5) : .secondary)

                            Text("•")
                                .font(.system(size: 8))
                                .foregroundColor(isDisabled ? .secondary.opacity(0.5) : .secondary)

                            Text("\(entry.messageCount) msgs")
                                .font(.system(size: 10))
                                .foregroundColor(isDisabled ? .secondary.opacity(0.5) : .secondary)
                        }
                    }

                    Spacer()

                    // Show lock icon when disabled, delete button on hover otherwise
                    if isDisabled {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                    } else if isHovering && !isActive {
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
                    .fill(isActive ? Color.accentColor.opacity(0.12) : (isHovering && !isDisabled ? Color.secondary.opacity(0.08) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(isDisabled ? "Generation in progress - wait or cancel to switch" : "")
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            return Self.weekdayFormatter.string(from: date)
        } else {
            return Self.dateFormatter.string(from: date)
        }
    }
}

// MARK: - Preview

struct SessionListView_Previews: PreviewProvider {
    static var previews: some View {
        SessionListView(
            sessionManager: SessionManager.shared,
            onSelectSession: { _ in },
            onNewSession: {},
            onDeleteSession: { _ in }
        )
        .frame(height: 400)
    }
}
