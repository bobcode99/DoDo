//
//  PowerMonitor.swift
//  PodcastAnalyzer
//
//  Tracks device charging state for auto-download gating.
//  iOS-only battery monitoring; macOS always reports isCharging = false
//  which the coordinator treats as "allowed" (no battery concern on macOS).
//

import Foundation
import OSLog
#if os(iOS)
import UIKit
#endif

/// Tracks device charging state. Implicitly @MainActor via SWIFT_DEFAULT_ACTOR_ISOLATION.
final class PowerMonitor {
  static let shared = PowerMonitor()
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PowerMonitor")

  /// true when the device is plugged in and charging or fully charged (iOS).
  /// Always false on macOS — the coordinator treats macOS as power-unrestricted.
  private(set) var isCharging: Bool = false

  private init() {
#if os(iOS)
    UIDevice.current.isBatteryMonitoringEnabled = true
    isCharging = Self.computeCharging()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(batteryStateChanged),
      name: UIDevice.batteryStateDidChangeNotification,
      object: nil
    )
#endif
  }

#if os(iOS)
  @objc private func batteryStateChanged() {
    Task { @MainActor in
      let wasCharging = self.isCharging
      self.isCharging = Self.computeCharging()
      if !wasCharging && self.isCharging {
        self.logger.info("Device started charging — triggering auto-download coordinator")
        Task { await AutoDownloadCoordinator.shared.run(reason: .powerBecameEligible) }
      }
    }
  }

  private static func computeCharging() -> Bool {
    let state = UIDevice.current.batteryState
    return state == .charging || state == .full
  }
#endif

  /// Returns true when the auto-download power policy is satisfied.
  func autoDownloadPowerAllowed(allowOnBattery: Bool) -> Bool {
#if os(iOS)
    return isCharging || allowOnBattery
#else
    return true  // macOS: no battery concern
#endif
  }
}
