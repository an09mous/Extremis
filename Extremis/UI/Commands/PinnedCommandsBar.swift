// MARK: - Pinned Commands Bar
// Quick access bar for pinned commands

import SwiftUI

/// Callback when a pinned command is executed
typealias PinnedCommandExecutionHandler = (Command) -> Void

/// Horizontal bar displaying pinned commands for quick access
struct PinnedCommandsBar: View {
    @ObservedObject var manager: CommandManager
    let onExecute: PinnedCommandExecutionHandler

    var body: some View {
        if !manager.pinnedCommands.isEmpty {
            HStack(spacing: 8) {
                ForEach(manager.pinnedCommands) { command in
                    PinnedCommandButton(
                        command: command,
                        onTap: { onExecute(command) }
                    )
                }

                Spacer()

                // Hint text
                Text("Quick commands")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DS.Colors.surfaceSecondary)
        }
    }
}

/// Single pinned command button
struct PinnedCommandButton: View {
    let command: Command
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: command.displayIcon)
                    .font(.caption)
                Text(command.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: DS.Radii.medium, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                    .animation(DS.Animation.hoverTransition, value: isHovering)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radii.medium, style: .continuous)
                    .stroke(isHovering ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    .animation(DS.Animation.hoverTransition, value: isHovering)
            )
        }
        .buttonStyle(.plain)
        .help(command.description ?? command.promptTemplate.prefix(100) + "...")
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

/// Compact version of the pinned commands bar (icon-only)
struct CompactPinnedCommandsBar: View {
    @ObservedObject var manager: CommandManager
    let onExecute: PinnedCommandExecutionHandler

    var body: some View {
        if !manager.pinnedCommands.isEmpty {
            HStack(spacing: 4) {
                ForEach(manager.pinnedCommands) { command in
                    CompactPinnedCommandButton(
                        command: command,
                        onTap: { onExecute(command) }
                    )
                }
            }
        }
    }
}

/// Compact icon-only pinned command button
struct CompactPinnedCommandButton: View {
    let command: Command
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            Image(systemName: command.displayIcon)
                .font(.caption)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                        .fill(isHovering ? Color.accentColor.opacity(0.15) : Color.clear)
                        .animation(DS.Animation.hoverTransition, value: isHovering)
                )
        }
        .buttonStyle(.plain)
        .help(command.name + (command.description.map { ": " + $0 } ?? ""))
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Preview

struct PinnedCommandsBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Note: Preview requires CommandManager to be loaded
            Text("Preview requires running app with commands")
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 400)
    }
}
