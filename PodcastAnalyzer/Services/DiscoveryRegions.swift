//
//  DiscoveryRegions.swift
//  PodcastAnalyzer
//
//  Which storefronts Home offers, and which one it is showing.
//
//  There are 174 live storefronts (see locales.md), and nobody browses more
//  than a handful. The shortlist is what the user ticked; Home's switcher shows
//  only those, so picking a country is a two-tap affair instead of a scroll
//  through the world.
//
//  Storage is UserDefaults, read through this one type rather than by each
//  view, so the "is the selection still valid" rule lives in a single place —
//  a selection can be orphaned by unticking it in Settings, and every reader
//  would otherwise need to remember that.
//

import Foundation
import OSLog

@MainActor
@Observable
final class DiscoveryRegions {
  static let shared = DiscoveryRegions()

  private enum Keys {
    static let enabled = "enabledPodcastRegions"
    static let selected = "selectedPodcastRegion"
    /// Codes the user verified by probing that aren't in the shipped catalogue.
    static let custom = "customPodcastStorefronts"
  }

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "DiscoveryRegions")
  private let defaults: UserDefaults

  /// Codes the user has ticked, in the order Home should offer them.
  /// Never empty — see `normalize`.
  private(set) var enabled: [String]

  /// Custom codes the user added after a successful probe. Kept apart from
  /// `enabled` so unticking one doesn't lose the fact that it was verified.
  private(set) var custom: [String]

  /// The storefront Home is currently showing. Always a member of `enabled`.
  private(set) var selected: String

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let storedCustom = defaults.stringArray(forKey: Keys.custom) ?? []
    let storedEnabled = defaults.stringArray(forKey: Keys.enabled)
      ?? [Constants.defaultRegion]
    let storedSelected = defaults.string(forKey: Keys.selected)

    let normalized = Self.normalize(storedEnabled, custom: storedCustom)
    self.custom = storedCustom
    self.enabled = normalized
    self.selected = Self.resolveSelection(storedSelected, within: normalized)
  }

  // MARK: - Rules

  /// Drop unknown codes, de-duplicate, and guarantee at least one entry.
  ///
  /// An empty shortlist would leave Home with nothing to show and no way back,
  /// so the device default is reinstated rather than allowing that state.
  private static func normalize(_ codes: [String], custom: [String]) -> [String] {
    var seen = Set<String>()
    let cleaned = codes
      .map { $0.lowercased() }
      .filter { Storefront.isKnown($0) || custom.contains($0) }
      .filter { seen.insert($0).inserted }
    return cleaned.isEmpty ? [Constants.defaultRegion] : cleaned
  }

  /// A stored selection survives only while it is still ticked; otherwise Home
  /// falls back to the first entry rather than showing a region the user just
  /// removed.
  private static func resolveSelection(_ stored: String?, within enabled: [String]) -> String {
    guard let stored, enabled.contains(stored) else {
      return enabled.first ?? Constants.defaultRegion
    }
    return stored
  }

  // MARK: - Display

  /// Storefront for a code, synthesizing an entry for a verified custom code
  /// that isn't in the shipped catalogue.
  func storefront(for code: String) -> Storefront {
    Storefront.named(code) ?? Storefront(code: code, name: code.uppercased())
  }

  /// The storefronts Home should offer, in order.
  var enabledStorefronts: [Storefront] {
    enabled.map(storefront(for:))
  }

  // MARK: - Mutation

  /// - Parameter notify: post `.podcastRegionChanged`. Off when the caller is
  ///   already acting on the change — HomeViewModel's `selectedRegion` didSet
  ///   persists through here, and it also *observes* that notification, so
  ///   posting would echo its own write straight back at it.
  func select(_ code: String, notify: Bool = true) {
    let code = code.lowercased()
    guard enabled.contains(code), code != selected else { return }
    selected = code
    defaults.set(code, forKey: Keys.selected)
    if notify {
      NotificationCenter.default.post(name: .podcastRegionChanged, object: code)
    }
  }

  /// Replace the shortlist wholesale — also how reordering lands, since
  /// `Array.move(fromOffsets:toOffset:)` is SwiftUI's and this stays
  /// Foundation-only. The List does the move and hands back the new order.
  func setEnabled(_ codes: [String]) {
    enabled = Self.normalize(codes, custom: custom)
    defaults.set(enabled, forKey: Keys.enabled)

    // Untick the displayed region and Home has to move somewhere valid.
    let resolved = Self.resolveSelection(selected, within: enabled)
    if resolved != selected {
      selected = resolved
      defaults.set(resolved, forKey: Keys.selected)
      NotificationCenter.default.post(name: .podcastRegionChanged, object: resolved)
    }
    logger.info("Discovery regions set to \(self.enabled.joined(separator: ","), privacy: .public)")
  }

  func toggle(_ code: String) {
    let code = code.lowercased()
    setEnabled(enabled.contains(code) ? enabled.filter { $0 != code } : enabled + [code])
  }

  /// Record a custom storefront the user verified, and tick it.
  func addCustom(_ code: String) {
    let code = code.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else { return }
    if !Storefront.isKnown(code), !custom.contains(code) {
      custom.append(code)
      defaults.set(custom, forKey: Keys.custom)
    }
    if !enabled.contains(code) {
      setEnabled(enabled + [code])
    }
  }
}
