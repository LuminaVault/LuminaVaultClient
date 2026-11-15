// LuminaVaultClient/LuminaVaultClient/Features/Spaces/SpaceEditorSheet.swift
// HER-35: single sheet that handles both Create and Edit.
//
// The sheet asks for a name, an icon and an optional category. There is no
// slug field: the server derives the slug from the name, and it can never
// change afterwards. There is no colour field: nothing in the app shows a
// space's colour.
import SwiftUI

struct SpaceEditorSheet: View {
    enum Mode: Equatable {
        case create
        case edit(SpaceDTO)
    }

    let mode: Mode
    let knownCategories: [String]
    /// Returns nil when the space was saved, or the message to show when it
    /// was not. The sheet stays open on a failure so nothing typed is lost.
    let onSubmit: (SpaceEditorPayload) async -> String?

    @State private var form = SpaceEditorForm()
    @State private var isSubmitting = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    private var isEdit: Bool { if case .edit = mode { return true } else { return false } }
    private var titleText: String { isEdit ? "Edit Space" : "New Space" }

    private let iconColumns = [GridItem(.adaptive(minimum: 52), spacing: 12)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $form.name)
                        .textInputAutocapitalization(.words)
                }
                if let failure {
                    Section {
                        Text(failure)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Couldn't save: \(failure)")
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: iconColumns, spacing: 12) {
                        ForEach(SpaceIcon.choices) { choice in
                            iconButton(choice)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Category") {
                    TextField("Category (e.g. ai, stocks, work)", text: $form.category)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    let suggestions = SpaceEditorForm.suggestedCategories(from: knownCategories)
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { cat in
                                    Button(cat) { form.category = cat }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(titleText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "Save" : "Create") { submit() }
                        .disabled(!form.canSubmit || isSubmitting)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private func iconButton(_ choice: SpaceIcon.Choice) -> some View {
        let isSelected = form.icon == choice.symbol
        return Button {
            form.icon = choice.symbol
        } label: {
            LVIconView(
                SpaceIcon.resolve(choice.symbol),
                size: 26,
                tint: isSelected ? palette.accent : .secondary,
            )
            .frame(width: 52, height: 52)
            .background(
                isSelected ? palette.accent.opacity(0.15) : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.accent, lineWidth: 2)
                }
            }
        }
        // Plain, so each icon is its own tap target inside the Form row.
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func submit() {
        Task {
            isSubmitting = true
            defer { isSubmitting = false }
            failure = nil
            if let message = await onSubmit(form.payload) {
                failure = message
            } else {
                dismiss()
            }
        }
    }

    private func prefill() {
        if case let .edit(space) = mode {
            form = SpaceEditorForm(editing: space)
        }
    }
}

/// What the editor holds while the user types. Kept apart from the view so
/// its rules can be tested without rendering anything.
struct SpaceEditorForm: Equatable {
    var name: String = ""
    /// The selected icon, or nil when an existing space has an icon the grid
    /// does not offer. A nil icon is left untouched on save.
    var icon: String? = SpaceIcon.defaultSymbol
    var category: String = ""

    init() {}

    init(editing space: SpaceDTO) {
        name = space.name
        icon = SpaceIcon.isChoice(space.icon) ? space.icon : nil
        category = space.category ?? ""
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canSubmit: Bool { !trimmedName.isEmpty }

    var payload: SpaceEditorPayload {
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return SpaceEditorPayload(
            name: trimmedName,
            icon: icon,
            category: trimmedCategory.isEmpty ? nil : trimmedCategory,
        )
    }

    /// Categories worth offering as one-tap chips. The list the view model
    /// hands over always starts with the "All" pseudo-category, which is a
    /// filter and not something a space can belong to.
    static func suggestedCategories(from known: [String]) -> [String] {
        known.filter { $0 != allCategoriesSlug }
    }
}

struct SpaceEditorPayload: Equatable {
    let name: String
    /// nil means "keep the icon the space already has".
    let icon: String?
    let category: String?
}
