// LuminaVaultClient/LuminaVaultClient/Features/Spaces/SpacesViewModel.swift
// HER-35: drives the Spaces tab. Holds the canonical list, the active
// category filter, and a debounced search query. CRUD writes are optimistic
// — the local model updates immediately and a server error rolls it back.
import Foundation
import SwiftUI
import PostHog

/// Pseudo-category used by the segmented control to mean "show every Space
/// regardless of category". Not persisted — only ever a UI-state value.
let allCategoriesSlug = "__all__"

@Observable
@MainActor
final class SpacesViewModel {
    private let spacesClient: SpacesClientProtocol

    var spaces: [SpaceDTO] = []
    var selectedCategory: String = allCategoriesSlug
    var searchQuery: String = ""
    var isLoading = false
    var error: String?

    init(spacesClient: SpacesClientProtocol) {
        self.spacesClient = spacesClient
    }

    /// Distinct category labels present across the loaded spaces. Drives the
    /// segmented control row. Always prepends the "All" pseudo-slug.
    var categories: [String] {
        let raw = spaces.compactMap(\.category)
        let unique = Array(Set(raw)).sorted()
        return [allCategoriesSlug] + unique
    }

    /// Spaces filtered by the active category and the debounced search.
    var visibleSpaces: [SpaceDTO] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return spaces.filter { space in
            let categoryMatches = selectedCategory == allCategoriesSlug || space.category == selectedCategory
            let queryMatches = trimmedQuery.isEmpty
                || space.name.lowercased().contains(trimmedQuery)
                || space.slug.lowercased().contains(trimmedQuery)
                || (space.description ?? "").lowercased().contains(trimmedQuery)
            return categoryMatches && queryMatches
        }
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            spaces = try await spacesClient.list()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func create(_ request: CreateSpaceRequest) async {
        error = nil
        do {
            let created = try await spacesClient.create(request)
            spaces.append(created)
            spaces.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            // PostHog: capture space creation
            var props: [String: Any] = ["space_slug": created.slug]
            if let category = created.category { props["category"] = category }
            PostHogSDK.shared.capture("space_created", properties: props)
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func update(id: UUID, _ request: UpdateSpaceRequest) async {
        error = nil
        do {
            let updated = try await spacesClient.update(id: id, request)
            if let idx = spaces.firstIndex(where: { $0.id == id }) {
                spaces[idx] = updated
            }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(id: UUID) async {
        let previous = spaces
        spaces.removeAll { $0.id == id }
        do {
            try await spacesClient.delete(id: id)
            // PostHog: capture space deletion
            PostHogSDK.shared.capture("space_deleted", properties: ["space_id": id.uuidString])
        } catch {
            // Roll back the optimistic removal.
            spaces = previous
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
