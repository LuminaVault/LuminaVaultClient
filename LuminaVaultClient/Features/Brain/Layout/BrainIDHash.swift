// Stable id hashing for the Brain layouts. An exact port of the web app's
// `id-hash.ts`, so an id hashes to the same value on both platforms and a
// newcomer is seeded in the same place.

nonisolated enum BrainIDHash {
    /// FNV-1a over the id's UTF-16 code units (as JavaScript's `charCodeAt`
    /// sees them): a stable unsigned 32-bit hash.
    static func hashID(_ id: String, seed: UInt32 = 0x811C_9DC5) -> UInt32 {
        var h = seed
        for unit in id.utf16 {
            h ^= UInt32(unit)
            h = h &* 0x0100_0193
        }
        return h
    }

    /// Murmur3's finaliser: spreads every input bit over the output.
    static func mix32(_ value: UInt32) -> UInt32 {
        var h = value
        h ^= h >> 16
        h = h &* 0x85EB_CA6B
        h ^= h >> 13
        h = h &* 0xC2B2_AE35
        h ^= h >> 16
        return h
    }

    /// A stable value in [-0.5, 0.5) per id and axis (web `jitter`).
    static func jitter(_ id: String, axis: UInt32) -> Double {
        jitter(hash: hashID(id), axis: axis)
    }

    static func jitter(hash: UInt32, axis: UInt32) -> Double {
        Double(mix32(hash &+ (axis &+ 1) &* 0x9E37_79B9)) / 4_294_967_296 - 0.5
    }
}
