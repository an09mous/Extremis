// MARK: - Command Palette View
// Autocomplete dropdown for command selection when user types /

import SwiftUI

/// Callback when a command is selected from the palette
typealias CommandSelectionHandler = (Command) -> Void

/// View model for the command palette
@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var filterText: String = ""
    @Published var selectedIndex: Int = 0
    @Published private(set) var filteredCommands: [Command] = []

    private let manager = CommandManager.shared

    init() {
        // Initial load
        manager.loadCommands()
        updateFilteredCommands()
    }

    func updateFilteredCommands() {
        if filterText.isEmpty {
            filteredCommands = manager.commandsSortedForPalette
        } else {
            filteredCommands = manager.filter(query: filterText)
        }
        // Reset selection to first item
        selectedIndex = 0
    }

    func setFilter(_ text: String) {
        // Remove leading "/" if present
        filterText = text.hasPrefix("/") ? String(text.dropFirst()) : text
        updateFilteredCommands()
    }

    func moveSelectionUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func moveSelectionDown() {
        if selectedIndex < filteredCommands.count - 1 {
            selectedIndex += 1
        }
    }

    func selectedCommand() -> Command? {
        guard selectedIndex >= 0 && selectedIndex < filteredCommands.count else {
            return nil
        }
        return filteredCommands[selectedIndex]
    }

    var hasCommands: Bool {
        !filteredCommands.isEmpty
    }
}

/// Command palette dropdown view
struct CommandPaletteView: View {
    @ObservedObject var viewModel: CommandPaletteViewModel
    let onSelect: CommandSelectionHandler
    let onDismiss: () -> Void

    /// Maximum number of visible commands
    private let maxVisible = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "command")
                    .foregroundColor(.secondary)
                Text("Commands")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("↑↓ navigate · ↩ select · esc dismiss")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Commands list
            if viewModel.filteredCommands.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.filteredCommands.prefix(maxVisible).enumerated()), id: \.element.id) { index, command in
                                CommandPaletteRow(
                                    command: command,
                                    isSelected: index == viewModel.selectedIndex,
                                    filterText: viewModel.filterText
                                )
                                .id(index)
                                .onTapGesture {
                                    onSelect(command)
                                }
                            }
                        }
                    }
                    .onChange(of: viewModel.selectedIndex) { newIndex in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                .frame(maxHeight: CGFloat(min(viewModel.filteredCommands.count, maxVisible)) * 52)
            }

            // Footer showing count
            if viewModel.filteredCommands.count > maxVisible {
                Divider()
                HStack {
                    Spacer()
                    Text("\(viewModel.filteredCommands.count - maxVisible) more...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        .frame(width: 320)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundColor(.secondary)
            if viewModel.filterText.isEmpty {
                Text("No commands available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Create commands in Preferences → Commands")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            } else {
                Text("No matching commands")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Try a different search term")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

/// Single row in the command palette
struct CommandPaletteRow: View {
    let command: Command
    let isSelected: Bool
    let filterText: String

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: command.displayIcon)
                .font(.title3)
                .foregroundColor(isSelected ? .white : .accentColor)
                .frame(width: 24)

            // Command info
            VStack(alignment: .leading, spacing: 2) {
                // Command name with highlight
                highlightedName
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)

                if let description = command.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Keyboard hint
            if isSelected {
                Text("↩")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected
                ? Color.accentColor
                : Color.clear
        )
        .contentShape(Rectangle())
    }

    /// Highlights matching text in the command name
    @ViewBuilder
    private var highlightedName: some View {
        if filterText.isEmpty {
            Text(command.name)
        } else {
            let name = command.name
            let lowercasedName = name.lowercased()
            let lowercasedFilter = filterText.lowercased()

            if let range = lowercasedName.range(of: lowercasedFilter) {
                let startIndex = name.index(name.startIndex, offsetBy: lowercasedName.distance(from: lowercasedName.startIndex, to: range.lowerBound))
                let endIndex = name.index(name.startIndex, offsetBy: lowercasedName.distance(from: lowercasedName.startIndex, to: range.upperBound))

                Text(name[..<startIndex]) +
                Text(name[startIndex..<endIndex])
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .white : .accentColor) +
                Text(name[endIndex...])
            } else {
                Text(command.name)
            }
        }
    }
}

// MARK: - Preview

struct CommandPaletteView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = CommandPaletteViewModel()

        CommandPaletteView(
            viewModel: viewModel,
            onSelect: { command in print("Selected: \(command.name)") },
            onDismiss: { print("Dismissed") }
        )
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
