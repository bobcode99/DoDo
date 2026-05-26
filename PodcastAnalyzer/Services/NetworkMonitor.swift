//
//  NetworkMonitor.swift
//  PodcastAnalyzer
//
//  Lightweight NWPathMonitor wrapper that tracks whether the device is on a
//  Wi-Fi or wired Ethernet interface. Used to gate auto-download and
//  auto-transcript jobs so they don't run over cellular.
//

import Network

/// Tracks network interface type for auto-download and auto-transcript gating.
/// The property is `@MainActor`-isolated via `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
/// The NW path update handler dispatches writes back to MainActor, so reads from
/// any `@MainActor` context are race-free.
final class NetworkMonitor {
  static let shared = NetworkMonitor()

  private let monitor = NWPathMonitor()
  private let monitorQueue = DispatchQueue(label: "com.podcast.analyzer.network", qos: .utility)

  /// `true` when the device is on Wi-Fi or wired Ethernet (not cellular).
  private(set) var isOnWiFiOrEthernet: Bool = false

  /// `true` when the device is on any network connection.
  private(set) var isConnected: Bool = false

  /// `true` when the device is on cellular (not Wi-Fi or Ethernet).
  private(set) var isCellular: Bool = false

  /// `true` once NWPathMonitor has fired its first update. Until this flips,
  /// `isConnected` is just the default `false` — callers that gate behavior
  /// on connectivity (e.g. refusing offline playback) MUST consult this flag
  /// so they don't act on stale defaults during the first ~200ms after init.
  private(set) var hasReceivedFirstUpdate: Bool = false

  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let wifi = path.usesInterfaceType(.wifi)
      let ethernet = path.usesInterfaceType(.wiredEthernet)
      let cellular = path.usesInterfaceType(.cellular)
      let connected = path.status == .satisfied
      Task { @MainActor [weak self] in
        guard let self else { return }
        let wasEligible = self.isOnWiFiOrEthernet
        self.isOnWiFiOrEthernet = wifi || ethernet
        self.isConnected = connected
        self.isCellular = cellular && !wifi && !ethernet
        self.hasReceivedFirstUpdate = true
        // Trigger coordinator when network becomes eligible (transition from not-eligible).
        if !wasEligible && self.isOnWiFiOrEthernet {
          Task { await AutoDownloadCoordinator.shared.run(reason: .networkBecameEligible) }
        }
      }
    }
    monitor.start(queue: monitorQueue)
  }
}
