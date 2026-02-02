// MARK: - Commands Tab
// User command management in Preferences

import SwiftUI

struct CommandsTab: View {
    @StateObject private var viewModel = CommandsTabViewModel()
    @State private var showingAddSheet = false
    @State private var editingCommand: Command?
    @State private var showingDeleteConfirmation = false
    @State private var commandToDelete: Command?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Commands Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Commands")
                                .font(.headline)

                            Spacer()

                            Button(action: { showingAddSheet = true }) {
                                Image(systemName: "plus")
                            }
                            .help("Add Command")
                        }

                        Text("Create predefined prompts that can be executed with /command syntax.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if viewModel.commands.isEmpty {
                            emptyStateView
                        } else {
                            commandsListView
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            // Status Message
            if let message = viewModel.statusMessage {
                HStack {
                    Image(systemName: viewModel.isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundColor(viewModel.isError ? .orange : .green)
                    Text(message)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            viewModel.loadCommands()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEditCommandSheet(
                mode: .add,
                canPin: viewModel.canPinMore,
                onSave: { command in
                    viewModel.addCommand(command)
                    showingAddSheet = false
                },
                onCancel: { showingAddSheet = false }
            )
        }
        .sheet(item: $editingCommand) { command in
            AddEditCommandSheet(
                mode: .edit(command),
                canPin: viewModel.canPinMore || command.isPinned,
                onSave: { updated in
                    viewModel.updateCommand(updated)
                    editingCommand = nil
                },
                onCancel: { editingCommand = nil }
            )
        }
        .confirmationDialog(
            "Delete Command",
            isPresented: $showingDeleteConfirmation,
            presenting: commandToDelete
        ) { command in
            Button("Delete", role: .destructive) {
                viewModel.removeCommand(id: command.id)
                commandToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                commandToDelete = nil
            }
        } message: { command in
            Text("Are you sure you want to delete '\(command.name)'? This action cannot be undone.")
        }
    }

    // MARK: - Commands List

    private var commandsListView: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.commands) { command in
                CommandRow(
                    command: command,
                    canPin: viewModel.canPinMore,
                    onTogglePin: { viewModel.togglePin(id: command.id) },
                    onEdit: { editingCommand = command },
                    onDelete: {
                        commandToDelete = command
                        showingDeleteConfirmation = true
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "command")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No Commands")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Create commands to quickly execute common prompts with your selected text or context.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Add Command") {
                showingAddSheet = true
            }
            .padding(.top, 4)

            Button("Reset to Defaults") {
                viewModel.resetToDefaults()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Command Row

struct CommandRow: View {
    let command: Command
    let canPin: Bool
    let onTogglePin: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: command.displayIcon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            // Command info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(command.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if command.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                if let description = command.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Usage stats
                if command.usageCount > 0 {
                    Text("Used \(command.usageCount) time\(command.usageCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button(action: onTogglePin) {
                    Image(systemName: command.isPinned ? "pin.slash" : "pin")
                        .foregroundColor(command.isPinned ? .orange : .secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!canPin && !command.isPinned)
                .help(command.isPinned ? "Unpin" : (canPin ? "Pin to quick access" : "Max pinned reached"))

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Edit Command")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete Command")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - View Model

@MainActor
final class CommandsTabViewModel: ObservableObject {
    @Published private(set) var commands: [Command] = []
    @Published private(set) var pinnedCommands: [Command] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var isError = false

    private let manager = CommandManager.shared

    func loadCommands() {
        manager.loadCommands()
        commands = manager.commands
        pinnedCommands = manager.pinnedCommands
    }

    var canPinMore: Bool {
        manager.canPinMore
    }

    func addCommand(_ command: Command) {
        manager.addCommand(command)
        commands = manager.commands
        pinnedCommands = manager.pinnedCommands
        statusMessage = "Command '\(command.name)' added"
        isError = false
    }

    func updateCommand(_ command: Command) {
        manager.updateCommand(command)
        commands = manager.commands
        pinnedCommands = manager.pinnedCommands
        statusMessage = "Command '\(command.name)' updated"
        isError = false
    }

    func removeCommand(id: UUID) {
        let name = commands.first { $0.id == id }?.name ?? "Command"
        manager.removeCommand(id: id)
        commands = manager.commands
        pinnedCommands = manager.pinnedCommands
        statusMessage = "'\(name)' deleted"
        isError = false
    }

    func togglePin(id: UUID) {
        manager.togglePin(id: id)
        commands = manager.commands
        pinnedCommands = manager.pinnedCommands
    }

    func resetToDefaults() {
        manager.resetToDefaults()
        commands = manager.commands
        pinnedCommands = manager.pinnedCommands
        statusMessage = "Commands reset to defaults"
        isError = false
    }
}
