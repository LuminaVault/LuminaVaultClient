// Port of the web app's brain-prefs.test.ts. UserDefaults stands in for
// localStorage, with a throwaway suite per test.

import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

struct BrainPrefsTests {
    private func suite() -> UserDefaults {
        let name = "BrainPrefsTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else { return .standard }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private var fresh: BrainPrefs { BrainPrefs(filters: BrainGraphModel.defaultFilters(), view: nil) }

    @Test func usesTheKeyLvBrainPrefsV1() {
        #expect(BrainPrefs.key == "lv_brain_prefs_v1")
    }

    @Test func fallsBackToTheDefaultsWhenNothingIsStored() {
        #expect(BrainPrefs.load(from: suite()) == fresh)
    }

    @Test func roundTripsFiltersAndTheView() {
        let defaults = suite()
        var filters = BrainGraphModel.defaultFilters()
        filters.links[.tag] = false
        filters.links[.similar] = true
        filters.showOrphans = false
        filters.colourBy = .author
        BrainPrefs(filters: filters, view: .threeD).save(to: defaults)
        #expect(BrainPrefs.load(from: defaults) == BrainPrefs(filters: filters, view: .threeD))
    }

    @Test func storesTheChoiceAsOneJSONStringUnderOneKey() throws {
        let defaults = suite()
        BrainPrefs(filters: BrainGraphModel.defaultFilters(), view: .twoD).save(to: defaults)
        let text = try #require(defaults.string(forKey: "lv_brain_prefs_v1"))
        #expect(text.contains("\"2d\""))
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("lv_brain") }.count == 1)
    }

    @Test func neverStoresTheVaultSet() throws {
        let defaults = suite()
        let id = UUID()
        var filters = BrainGraphModel.defaultFilters()
        filters.vaults = [id]
        BrainPrefs(filters: filters, view: nil).save(to: defaults)
        let text = try #require(defaults.string(forKey: BrainPrefs.key))
        #expect(!text.localizedCaseInsensitiveContains(id.uuidString))
        #expect(BrainPrefs.load(from: defaults).filters.vaults == nil)
    }

    @Test func fallsBackToTheDefaultsOnCorruptedJSON() {
        let defaults = suite()
        defaults.set("{\"filters\": {\"links\": ", forKey: BrainPrefs.key)
        #expect(BrainPrefs.load(from: defaults) == fresh)
        defaults.set(Data([0xFF, 0x00, 0x12]), forKey: BrainPrefs.key)
        #expect(BrainPrefs.load(from: defaults) == fresh)
        defaults.set("[1,2,3]", forKey: BrainPrefs.key)
        #expect(BrainPrefs.load(from: defaults) == fresh)
    }

    @Test func ignoresUnknownLinkKindsAndUnknownEnumValuesAndKeepsDefaultsForMissingOnes() {
        let defaults = suite()
        defaults.set(
            #"{"filters":{"links":{"tag":false,"wormhole":true,"similar":"yes"},"colourBy":"mood"},"view":"4d"}"#,
            forKey: BrainPrefs.key
        )
        let loaded = BrainPrefs.load(from: defaults)
        var expected = BrainGraphModel.defaultFilters()
        expected.links[.tag] = false
        #expect(loaded.filters == expected)
        #expect(loaded.filters.links.count == BrainLinkKindDTO.allCases.count)
        #expect(loaded.view == nil)
    }

    @Test func worksWithoutAnyStorageAtAll() {
        #expect(BrainPrefs.load(from: nil) == fresh)
        fresh.save(to: nil)
    }

    @Test func neitherStoresNorRestoresWhetherTheFilterSheetWasOpen() throws {
        let defaults = suite()
        defaults.set(#"{"filters":{},"panelOpen":true}"#, forKey: BrainPrefs.key)
        #expect(BrainPrefs.load(from: defaults) == fresh)
        BrainPrefs(filters: BrainGraphModel.defaultFilters(), view: .twoD).save(to: defaults)
        #expect(try !#require(defaults.string(forKey: BrainPrefs.key)).contains("panelOpen"))
    }

    // brain-url.ts: an explicit choice wins over the stored one; iOS has no URL.
    @Test func anExplicitViewWinsOverTheStoredOneAndTheStoredOverTwoD() {
        let stored = BrainPrefs(filters: BrainGraphModel.defaultFilters(), view: .threeD)
        #expect(stored.effectiveView(explicit: .twoD) == .twoD)
        #expect(stored.effectiveView(explicit: nil) == .threeD)
        #expect(fresh.effectiveView(explicit: nil) == .twoD)
        #expect(fresh.effectiveView(explicit: .threeD) == .threeD)
    }
}
