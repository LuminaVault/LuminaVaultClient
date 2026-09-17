// LuminaVaultClient/LuminaVaultClient/Services/Persistence/Models/CachedNewsTickerItem.swift
//
// The last ticker this device saw, so Home paints the strip instantly and
// keeps showing something on a train. Headline, source, time, link — never a
// body. Whole-snapshot: every refresh replaces the set.

import Foundation
import LuminaVaultShared
import SwiftData

@Model
final class CachedNewsTickerItem {
    @Attribute(.unique) var id: String
    var title: String
    var url: String?
    var source: String
    var sourceUrl: String?
    var publishedAt: Date
    var position: Int
    var fetchedAt: Date
    var stale: Bool

    init(dto: NewsTickerItemDTO, position: Int, fetchedAt: Date, stale: Bool) {
        id = dto.id
        title = dto.title
        url = dto.url
        source = dto.source
        sourceUrl = dto.sourceUrl
        publishedAt = dto.publishedAt
        self.position = position
        self.fetchedAt = fetchedAt
        self.stale = stale
    }

    var dto: NewsTickerItemDTO {
        NewsTickerItemDTO(id: id, title: title, url: url, source: source, sourceUrl: sourceUrl, publishedAt: publishedAt)
    }
}

/// Snapshot store over the app's ModelContainer.
@MainActor
struct NewsTickerLocalStore {
    let container: ModelContainer

    struct Snapshot {
        let items: [NewsTickerItemDTO]
        let fetchedAt: Date
        let stale: Bool
    }

    func load() throws -> Snapshot? {
        let rows = try container.mainContext.fetch(
            FetchDescriptor<CachedNewsTickerItem>(sortBy: [SortDescriptor(\.position)])
        )
        guard let first = rows.first else { return nil }
        return Snapshot(items: rows.map(\.dto), fetchedAt: first.fetchedAt, stale: first.stale)
    }

    func replace(with items: [NewsTickerItemDTO], stale: Bool, fetchedAt: Date) throws {
        let context = container.mainContext
        try context.delete(model: CachedNewsTickerItem.self)
        for (index, item) in items.enumerated() {
            context.insert(CachedNewsTickerItem(dto: item, position: index, fetchedAt: fetchedAt, stale: stale))
        }
        try context.save()
    }
}
