// LuminaVaultClient/LuminaVaultClient/Utilities/Extensions/Sequence+LVUnique.swift

import Foundation

extension Sequence where Element: Hashable {
    /// The elements in order, with later duplicates dropped.
    ///
    /// Several server-provided string lists are rendered with
    /// `ForEach(list, id: \.self)` — plugin screenshot URLs, plugin
    /// permissions, note tags, memory tags. Self-identity is the *right*
    /// identity for those: an `AsyncImage` keyed on its URL keeps its
    /// downloaded image when the surrounding model reloads, whereas an
    /// index-based id would re-trigger the download on any reorder.
    ///
    /// What self-identity requires and the server does not guarantee is
    /// uniqueness. A repeated element produces duplicate ids inside one
    /// `ForEach`, which is undefined behaviour — and it is a product bug in
    /// its own right, because "#work #work" and two identical carousel pages
    /// are wrong however they are keyed. De-duplicating fixes both at once.
    func lvUnique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Sequence {
    /// The elements in order, with later duplicates of `key` dropped.
    ///
    /// The same guarantee as ``lvUnique()`` for lists rendered with a
    /// key-path identity — `ForEach(_, id: \.provider)` needs unique
    /// providers just as `id: \.self` needs unique elements — where the
    /// element itself is a `Codable` DTO that is not `Hashable`.
    func lvUnique<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
