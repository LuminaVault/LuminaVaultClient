// What a person keeps between visits to the Brain tab: link toggles,
// show-unlinked, colour-by and the 2D/3D choice. A port of the web app's
// `brain-prefs.ts`, with `UserDefaults` for `localStorage`: one key holding
// JSON, tolerant of anything unknown or corrupt.
//
// The vault set is not stored (it is always "every vault" on launch) and
// neither is whether the filter sheet was open: it is modal, and a visit should
// not start behind it.

import Foundation
import LuminaVaultShared

nonisolated enum BrainViewChoice: String, Sendable {
    case twoD = "2d"
    case threeD = "3d"
}

nonisolated struct BrainPrefs: Equatable, Sendable {
    static let key = "lv_brain_prefs_v1"

    var filters: BrainGraphFilters
    /// `nil` until a view has been picked.
    var view: BrainViewChoice?

    static func defaults() -> BrainPrefs {
        BrainPrefs(filters: BrainGraphModel.defaultFilters(), view: nil)
    }

    /// An explicit choice (a button just tapped) wins over the stored one; with
    /// neither, 2D. The port of `readBrainURL(params, storedView)` for an app
    /// that has no URL.
    func effectiveView(explicit: BrainViewChoice?) -> BrainViewChoice {
        explicit ?? view ?? .twoD
    }

    /// Stored prefs over the defaults; anything missing, unknown or of the
    /// wrong type is ignored. `nil` defaults gives the defaults.
    static func load(from defaults: UserDefaults?) -> BrainPrefs {
        var prefs = BrainPrefs.defaults()
        guard let defaults, let object = storedObject(defaults), let raw = object as? [String: Any] else {
            return prefs
        }
        let stored = raw["filters"] as? [String: Any] ?? [:]
        let links = stored["links"] as? [String: Any] ?? [:]
        for kind in BrainLinkKindDTO.allCases {
            if let value = links[kind.rawValue], let flag = boolean(value) { prefs.filters.links[kind] = flag }
        }
        if let value = stored["showOrphans"], let flag = boolean(value) { prefs.filters.showOrphans = flag }
        if let name = stored["colourBy"] as? String, let colour = BrainColourBy(rawValue: name) {
            prefs.filters.colourBy = colour
        }
        if let name = raw["view"] as? String, let view = BrainViewChoice(rawValue: name) { prefs.view = view }
        return prefs
    }

    func save(to defaults: UserDefaults?) {
        guard let defaults else { return }
        var links: [String: Bool] = [:]
        for kind in BrainLinkKindDTO.allCases { links[kind.rawValue] = filters.links[kind] ?? false }
        var payload: [String: Any] = [
            "filters": [
                "links": links,
                "showOrphans": filters.showOrphans,
                "colourBy": filters.colourBy.rawValue,
            ] as [String: Any],
        ]
        if let view { payload["view"] = view.rawValue }
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(text, forKey: Self.key)
    }

    private static func storedObject(_ defaults: UserDefaults) -> Any? {
        let data: Data
        if let text = defaults.string(forKey: key) {
            data = Data(text.utf8)
        } else if let blob = defaults.data(forKey: key) {
            data = blob
        } else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// JSON `true`/`false` only: `1`, `0` and `"yes"` are not booleans.
    private static func boolean(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
