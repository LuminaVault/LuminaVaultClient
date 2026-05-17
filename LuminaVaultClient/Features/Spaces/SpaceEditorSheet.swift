// LuminaVaultClient/LuminaVaultClient/Features/Spaces/SpaceEditorSheet.swift
// HER-35: single sheet that handles both Create and Edit. Editing mode
// hides the slug field — slug is immutable per SpaceSlugPolicy server-side.
import SwiftUI

struct SpaceEditorSheet: View {
    enum Mode: Equatable {
        case create
        case edit(SpaceDTO)
    }

    let mode: Mode
    let knownCategories: [String]
    let onSubmit: (SpaceEditorPayload) async -> Void

    @State private var name: String = ""
    @State private var slug: String = ""
    @State private var icon: String = "folder.fill"
    @State private var color: String = ""
    @State private var category: String = ""
    @State private var isSubmitting = false
    @Environment(\.dismiss) private var dismiss

    private var isEdit: Bool { if case .edit = mode { return true } else { return false } }
    private var titleText: String { isEdit ? "Edit Space" : "New Space" }

    private static let iconChoices: [String] = [
        "folder.fill",
        "sparkles",
        "chart.line.uptrend.xyaxis",
        "heart.fill",
        "briefcase.fill",
        "lightbulb.fill",
        "book.fill",
        "music.note",
        "camera.fill",
        "globe",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    if !isEdit {
                        TextField("Slug (lowercase, dashes ok)", text: $slug)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section("Icon") {
                    Picker("Icon", selection: $icon) {
                        ForEach(Self.iconChoices, id: \.self) { name in
                            Label(name, systemImage: name).tag(name)
                        }
                    }
                }
                Section("Category") {
                    TextField("Category (e.g. ai, stocks, work)", text: $category)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !knownCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(knownCategories.filter { $0 != allCategoriesSlug }, id: \.self) { cat in
                                    Button(cat) { category = cat }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
                Section("Color (optional)") {
                    TextField("Hex code, e.g. #FFAA00", text: $color)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(titleText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEdit ? "Save" : "Create") {
                        Task {
                            isSubmitting = true
                            defer { isSubmitting = false }
                            await onSubmit(SpaceEditorPayload(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                slug: slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                                icon: icon,
                                color: color.isEmpty ? nil : color,
                                category: category.isEmpty ? nil : category,
                            ))
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (!isEdit && slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || isSubmitting)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    private func prefill() {
        if case let .edit(space) = mode {
            name = space.name
            slug = space.slug
            icon = space.icon ?? "folder.fill"
            color = space.color ?? ""
            category = space.category ?? ""
        }
    }
}

struct SpaceEditorPayload: Equatable {
    let name: String
    let slug: String
    let icon: String
    let color: String?
    let category: String?
}
