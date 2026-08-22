//
//  DiscoveryRegionsTests.swift
//  PodcastAnalyzerTests
//
//  The shortlist rules, which exist because a bad state here strands Home with
//  nothing to show: an empty list, or a selection the user just unticked.
//
//  Every test uses its own UserDefaults suite so the host app's real settings
//  are never read or written.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Discovery regions")
struct DiscoveryRegionsTests {

    private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Catalogue

    @Test("The generated catalogue holds real storefronts and not invented ones")
    func catalogueContents() {
        #expect(Storefront.isKnown("us"))
        #expect(Storefront.isKnown("tw"))
        #expect(Storefront.isKnown("jp"))
        #expect(!Storefront.isKnown("xx"), "xx answered 500 when probed")
        #expect(Storefront.all.count > 150, "the probe found 174; a big drop means a bad regeneration")
    }

    @Test("Every entry has a name and a flag")
    func catalogueWellFormed() {
        for storefront in Storefront.all {
            #expect(!storefront.name.isEmpty, "\(storefront.code) has no name")
            #expect(storefront.flag.count == 1, "\(storefront.code) flag should be one grapheme")
            #expect(storefront.code.count == 2, "\(storefront.code) should be alpha-2")
        }
    }

    @Test("Codes are unique")
    func catalogueUnique() {
        #expect(Set(Storefront.all.map(\.code)).count == Storefront.all.count)
    }

    // MARK: - Shortlist rules

    @Test("A fresh install starts with exactly the device region")
    func defaultsToDeviceRegion() {
        let regions = DiscoveryRegions(defaults: makeDefaults())
        #expect(regions.enabled == [Constants.defaultRegion])
        #expect(regions.selected == Constants.defaultRegion)
    }

    @Test("The shortlist can never be emptied")
    func neverEmpty() {
        let regions = DiscoveryRegions(defaults: makeDefaults())
        regions.setEnabled([])
        #expect(!regions.enabled.isEmpty, "an empty shortlist leaves Home with nothing to show")
    }

    @Test("Unknown codes are dropped")
    func dropsUnknown() {
        let regions = DiscoveryRegions(defaults: makeDefaults())
        regions.setEnabled(["us", "xx", "tw"])
        #expect(regions.enabled == ["us", "tw"])
    }

    @Test("Duplicates collapse and order is kept")
    func dedupesPreservingOrder() {
        let regions = DiscoveryRegions(defaults: makeDefaults())
        regions.setEnabled(["tw", "us", "tw"])
        #expect(regions.enabled == ["tw", "us"])
    }

    @Test("Unticking the displayed region moves the selection somewhere valid")
    func selectionFollowsShortlist() {
        let regions = DiscoveryRegions(defaults: makeDefaults())
        regions.setEnabled(["us", "tw"])
        regions.select("tw")
        #expect(regions.selected == "tw")

        regions.setEnabled(["us"])
        #expect(regions.selected == "us", "the removed region must not stay selected")
    }

    @Test("Selecting something not on the shortlist is refused")
    func cannotSelectUnticked() {
        let regions = DiscoveryRegions(defaults: makeDefaults())
        regions.setEnabled(["us"])
        regions.select("jp")
        #expect(regions.selected == "us")
    }

    @Test("A verified custom code survives normalization")
    func customCodeIsKept() {
        let name = UUID().uuidString
        let regions = DiscoveryRegions(defaults: makeDefaults(name))
        // "zz" is not a storefront, so only the custom list can vouch for it.
        regions.addCustom("zz")
        #expect(regions.enabled.contains("zz"))

        regions.setEnabled(regions.enabled)
        #expect(regions.enabled.contains("zz"), "normalization must not drop a verified custom code")
    }

    @Test("A custom storefront still gets a display name")
    func customStorefrontDisplay() {
        let regions = DiscoveryRegions(defaults: makeDefaults())
        regions.addCustom("zz")
        #expect(regions.storefront(for: "zz").name == "ZZ")
    }

    @Test("Selection and shortlist round-trip through storage")
    func persistsAcrossLaunch() {
        let name = UUID().uuidString
        let defaults = makeDefaults(name)
        let first = DiscoveryRegions(defaults: defaults)
        first.setEnabled(["us", "tw", "jp"])
        first.select("jp")

        let second = DiscoveryRegions(defaults: defaults)
        #expect(second.enabled == ["us", "tw", "jp"])
        #expect(second.selected == "jp")
    }

    // MARK: - Accent colour

    @Test("An accent colour round-trips, and absence means System Default")
    func accentRoundTrip() {
        let encoded = AppAccentColorDefaults.encode(AccentPreset.green.color)
        let decoded = AppAccentColorDefaults.decode(encoded)
        #expect(decoded != nil)
        #expect(AppAccentColorDefaults.decode("") == nil, "no stored value means System Default")
        #expect(AppAccentColorDefaults.decode("garbage") == nil)
    }
}
