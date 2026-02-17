// MARK: - Add/Edit Command Sheet
// Form for creating and editing commands

import SwiftUI

/// Mode for the add/edit sheet
enum AddEditCommandMode: Identifiable {
    case add
    case edit(Command)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let command):
            return command.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .add:
            return "Add Command"
        case .edit:
            return "Edit Command"
        }
    }

    var saveButtonTitle: String {
        switch self {
        case .add:
            return "Add"
        case .edit:
            return "Save"
        }
    }
}

struct AddEditCommandSheet: View {
    let mode: AddEditCommandMode
    let canPin: Bool
    let onSave: (Command) -> Void
    let onCancel: () -> Void

    // Form state
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var promptTemplate: String = ""
    @State private var icon: String = ""
    @State private var isPinned: Bool = false

    // Validation
    @State private var validationErrors: [String] = []
    @State private var showingValidationAlert = false

    // Existing command data for edits
    private var existingID: UUID?
    private var existingCreatedAt: Date?
    private var existingUsageCount: Int
    private var existingLastUsedAt: Date?

    init(mode: AddEditCommandMode, canPin: Bool, onSave: @escaping (Command) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode
        self.canPin = canPin
        self.onSave = onSave
        self.onCancel = onCancel

        // Pre-populate if editing
        if case .edit(let command) = mode {
            _name = State(initialValue: command.name)
            _description = State(initialValue: command.description ?? "")
            _promptTemplate = State(initialValue: command.promptTemplate)
            _icon = State(initialValue: command.icon ?? "")
            _isPinned = State(initialValue: command.isPinned)
            existingID = command.id
            existingCreatedAt = command.createdAt
            existingUsageCount = command.usageCount
            existingLastUsedAt = command.lastUsedAt
        } else {
            existingUsageCount = 0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Basic Info
                    GroupBox("Basic Information") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Name")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Fix Grammar", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                Text("Short, descriptive name for the command")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description (optional)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("Correct grammar and spelling errors", text: $description)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Icon (SF Symbol)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("star", text: $icon)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 120)
                                    if !icon.isEmpty {
                                        Image(systemName: icon)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }

                            Toggle("Pin to Quick Access", isOn: $isPinned)
                                .disabled(!canPin && !isPinned)
                                .help(canPin || isPinned ? "Show in quick access bar" : "Maximum pinned commands reached")
                        }
                        .padding(.vertical, 8)
                    }

                    // Prompt Template
                    GroupBox("Prompt Template") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter the prompt that will be sent to the LLM when this command is executed.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextEditor(text: $promptTemplate)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 120)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radii.small, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )

                            Text("The selected text/context will be automatically included with your prompt.")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            // Example prompts
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Examples:")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                Group {
                                    Text("• \"Fix the grammar and spelling. Return only the corrected text.\"")
                                    Text("• \"Explain what this code does in simple terms.\"")
                                    Text("• \"Summarize this content in 2-3 bullet points.\"")
                                    Text("• \"Translate this text to Spanish.\"")
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.8))
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    }

                    // Icon Picker (Common SF Symbols)
                    GroupBox("Common Icons") {
                        iconPickerGrid
                            .padding(.vertical, 8)
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button(mode.saveButtonTitle) {
                    save()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 500, height: 650)
        .alert("Validation Error", isPresented: $showingValidationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationErrors.joined(separator: "\n"))
        }
    }

    // MARK: - Icon Picker

    private let commonIcons = [
        "text.badge.checkmark", "text.redaction", "doc.text.magnifyingglass",
        "pencil", "text.bubble", "questionmark.circle",
        "chevron.left.forwardslash.chevron.right", "terminal", "doc.text",
        "sparkles", "wand.and.stars", "lightbulb",
        "translate", "globe", "character.book.closed",
        "bolt", "gear", "slider.horizontal.3",
        "arrow.triangle.2.circlepath", "checkmark.circle", "xmark.circle",
        "star", "heart", "bookmark"
    ]

    private var iconPickerGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
            ForEach(commonIcons, id: \.self) { iconName in
                Button(action: { icon = iconName }) {
                    Image(systemName: iconName)
                        .font(.title3)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radii.medium, style: .continuous)
                                .fill(icon == iconName ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radii.medium, style: .continuous)
                                .stroke(icon == iconName ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(iconName)
            }
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !promptTemplate.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedTemplate = promptTemplate.trimmingCharacters(in: .whitespaces)

        // Validate
        var errors: [String] = []
        if trimmedName.isEmpty {
            errors.append("Name is required")
        }
        if trimmedTemplate.isEmpty {
            errors.append("Prompt template is required")
        }

        if !errors.isEmpty {
            validationErrors = errors
            showingValidationAlert = true
            return
        }

        // Build command
        let command = Command(
            id: existingID ?? UUID(),
            name: trimmedName,
            description: description.isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
            promptTemplate: trimmedTemplate,
            icon: icon.isEmpty ? nil : icon.trimmingCharacters(in: .whitespaces),
            isPinned: isPinned,
            usageCount: existingUsageCount,
            lastUsedAt: existingLastUsedAt,
            createdAt: existingCreatedAt ?? Date(),
            updatedAt: Date()
        )

        onSave(command)
    }
}

// MARK: - Preview

struct AddEditCommandSheet_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AddEditCommandSheet(
                mode: .add,
                canPin: true,
                onSave: { _ in },
                onCancel: {}
            )
            .previewDisplayName("Add Mode")

            AddEditCommandSheet(
                mode: .edit(Command(
                    name: "Fix Grammar",
                    description: "Correct grammar and spelling",
                    promptTemplate: "Fix the grammar and spelling errors in this text.",
                    icon: "text.badge.checkmark",
                    isPinned: true
                )),
                canPin: true,
                onSave: { _ in },
                onCancel: {}
            )
            .previewDisplayName("Edit Mode")
        }
    }
}
