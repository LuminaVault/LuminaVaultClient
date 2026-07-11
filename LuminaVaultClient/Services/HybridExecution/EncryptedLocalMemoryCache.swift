import CryptoKit
import Foundation
import LuminaVaultShared

actor EncryptedLocalMemoryCache {
    private let fileURL: URL
    private let key: SymmetricKey

    init(fileURL: URL, keyData: Data) {
        self.fileURL = fileURL
        key = SymmetricKey(data: keyData)
    }

    func load() throws -> [LocalMemorySyncItemDTO] {
        guard let sealed = try? Data(contentsOf: fileURL), !sealed.isEmpty else { return [] }
        let box = try AES.GCM.SealedBox(combined: sealed)
        return try JSONDecoder.hybrid.decode([LocalMemorySyncItemDTO].self, from: AES.GCM.open(box, using: key))
    }

    func merge(_ response: LocalMemorySyncResponse) throws {
        var values = try Dictionary(uniqueKeysWithValues: load().map { ($0.id, $0) })
        response.deletedIDs.forEach { values.removeValue(forKey: $0) }
        response.memories.forEach { values[$0.id] = $0 }
        let plaintext = try JSONEncoder.hybrid.encode(values.values.sorted { $0.updatedAt < $1.updatedAt })
        let sealed = try AES.GCM.seal(plaintext, using: key).combined!
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sealed.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func search(_ query: String, limit: Int = 5) throws -> [LocalMemorySyncItemDTO] {
        let terms = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return try load().map { item in
            let words = Set(item.content.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            return (item, terms.intersection(words).count)
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}

private extension JSONEncoder {
    static var hybrid: JSONEncoder {
        let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value
    }
}

private extension JSONDecoder {
    static var hybrid: JSONDecoder {
        let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value
    }
}
