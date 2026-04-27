---
name: Auto-download coordinator architecture
description: AntennaPod-pattern auto-download: coordinator actor, three-state per-podcast setting, episode filters, power/network gates
type: project
---

AutoDownloadCoordinator (actor, Services/) is the single serialized entry point for all auto-downloads. Triggered by BackgroundSyncManager (.feedRefresh), NetworkMonitor (.networkBecameEligible), and PowerMonitor (.powerBecameEligible). Never call DownloadManager.downloadEpisode directly for auto-download from other sites.

Key pieces:
- `AutoDownloadSetting` enum (enabled/disabled/inheritGlobal) stored as String on PodcastInfoModel.autoDownloadSetting. The old Bool `autoDownloadNewEpisodes` was removed.
- `EpisodeFilterEvaluator` (nonisolated static methods) — AntennaPod §8 six-step decision order.
- `PowerMonitor` (final class, implicitly @MainActor) — iOS battery gate; macOS always returns true.
- `EpisodeDownloadModel.autoDownloadEnabled` (Bool, default true) — set to false after first successful auto-download so episodes are never re-downloaded automatically.
- `DownloadManager.modelContainer` is now internal (was fileprivate) so the coordinator can read it.
- New UserDefaults keys read by coordinator: `allowCellularAutoDownload`, `allowAutoDownloadOnBattery`, `episodeCacheLimit` (0=unlimited).
- `PodcastInfoModel` also has: `episodeFilterInclude`, `episodeFilterExclude` (comma-separated terms), `episodeFilterMinDuration` (seconds).

**Why:** Replaces the inlined 5-episode-cap loop in BackgroundSyncManager with a serialized actor that handles network/power retriggers without a new sync, and adds per-podcast granularity.

**How to apply:** Any new auto-download trigger site should call `await AutoDownloadCoordinator.shared.updatePendingEpisodes(...)` + `run(reason:)` rather than calling DownloadManager directly.
