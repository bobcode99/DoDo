# DoDo Data Model & CloudKit Sync — Explained

This document covers every SwiftData `@Model` in the app, which ones sync via CloudKit, why the split exists, how the data is stored, and how records relate to each other.

---

## 1. The Big Picture

One `ModelContainer`, two physical stores:

```
ModelContainer (PodcastAnalyzerApp.sharedModelContainer)
│
├── "local" store  (cloudKitDatabase: .none)          → local.store (SQLite)
│     PodcastInfoModel
│     EpisodeDownloadModel
│     EpisodeQuickTagsModel
│     QueueItemModel
│     EpisodeTranscriptModel
│
└── "cloud" store  (.private("iCloud.com.jn.PodcastAnalyzer")) → cloud.store (SQLite)
      PlaybackProgressModel
      SubscribedPodcastModel
      EpisodeAIAnalysis
```

Both SQLite files live in the app group container:
`~/Library/Group Containers/group.com.jn.PodcastAnalyzer/Library/Application Support/`

Audio files themselves are plain files on disk (`~/Library/Audio/`), **never** in SwiftData and never synced — only their paths are recorded in `EpisodeDownloadModel.localAudioPath`.

---

## 2. How CloudKit Sync Actually Works Across Devices

SwiftData's CloudKit support is a *mirror*, not a message bus:

1. **Local write** — you save a `PlaybackProgressModel` row into `cloud.store` on your iPhone. That save completes instantly, offline or not.
2. **Background export** — the system (NSPersistentCloudKitContainer under the hood) batches local changes and uploads them as `CKRecord`s to your **private CloudKit database**, scoped to your Apple ID. No server code, no accounts — Apple hosts it.
3. **Push to other devices** — your Mac, signed into the same Apple ID with iCloud Drive enabled, receives a silent push notification that records changed.
4. **Background import** — the Mac downloads the changed records and writes them into *its own* `cloud.store`.
5. **App reacts** — the import fires an `NSPersistentStoreRemoteChange` notification. Our sync coordinators listen for it and merge the new rows into app state.

Key properties of this design:

- **Eventual consistency.** There is no "sync now and wait" API. Changes typically arrive in seconds-to-minutes, but the app must work correctly when data hasn't arrived yet (this is why onboarding's "restore from iCloud" check is racy by nature).
- **Same container ID everywhere.** iOS and macOS builds share one bundle ID, one entitlements file, one container: `iCloud.com.jn.PodcastAnalyzer`. Same container = same data.
- **Conflicts resolved by us.** CloudKit does last-writer-wins at the record level, but the meaningful merge (is the iPhone's playback position newer than the Mac's?) is done in `PlaybackProgressSyncCoordinator` using the `updatedAt` timestamp.

### CloudKit constraints that shaped the models

Any model in the cloud store must:
- have **every property optional or defaulted** (CloudKit may deliver partial records)
- have **no `#Unique`** constraints (unsupported; would break the local store too)
- have **no required relationships** (we use none at all — see §5)
- keep each record **under 1 MB**

---

## 3. Model-by-Model Reference

### ☁️ Cloud store (syncs across devices)

#### `PlaybackProgressModel` — *"where am I in this episode?"*
| Field | Purpose |
|---|---|
| `id` | Episode composite key: `"{podcastTitle}\u{1F}{episodeTitle}"` — joins to `EpisodeDownloadModel.id` |
| `lastPlaybackPosition`, `duration` | Resume point |
| `isCompleted`, `playCount`, `lastPlayedDate` | Played state |
| `updatedAt` | **Merge decider** — newer timestamp wins between devices |
| `deviceName` | Diagnostics only ("Bob's iPhone") |

Written by `PlaybackProgressSyncCoordinator` (push throttled to 30s unless forced, e.g. mark-as-played). Incoming remote changes are merged back into the local `EpisodeDownloadModel`; if the episode was never seen on this device, a placeholder row is created so "started elsewhere" episodes appear.

#### `SubscribedPodcastModel` — *"which shows am I subscribed to?"*
| Field | Purpose |
|---|---|
| `rssUrl` | Matching key → `PodcastInfoModel.rssUrl` |
| `title` | Display before feed is fetched |
| `dateSubscribed` | Ordering |

Deliberately tiny pointer. Full `PodcastInfoModel` is NOT synced because its embedded RSS snapshot (all episodes) could blow the 1 MB record cap. Receiving device sees a new `rssUrl`, fetches the feed fresh over the network, and subscribes silently (`SubscriptionSyncCoordinator.resubscribeMissingPodcasts()`). Also powers onboarding's "skip import — restore from iCloud" path.

#### `EpisodeAIAnalysis` — *"AI summary + Q&A for this episode"*
| Field | Purpose |
|---|---|
| `episodeAudioURL`, `episodeTitle`, `podcastTitle` | Matching keys |
| `analysisJSON` | Whole `ParsedEpisodeAnalysisResponse` as one JSON string |
| `qaHistoryJSON` | Q&A conversation history as JSON |
| `provider`, `model`, `generatedAt` | Which AI produced it |
| `createdAt`, `updatedAt` | Timestamps |

Text-only JSON — comfortably under 1 MB. Synced so an analysis generated on the Mac shows up on the phone without paying for a second AI call.

### 💾 Local store (this device only)

#### `EpisodeDownloadModel` — *the per-episode workhorse*
The central row for any episode the user has touched (downloaded, played, starred…). Keyed by the composite `id` (`podcastTitle\u{1F}episodeTitle`).

| Field group | Fields | Why local |
|---|---|---|
| Identity | `id`, `episodeTitle`, `podcastTitle`, `audioURL`, `guid` | — |
| Download | `localAudioPath`, `downloadedDate`, `fileSize`, `autoDownloadEnabled` | **A file path from another device is meaningless here** — the core reason this model can't sync wholesale |
| Playback | `lastPlaybackPosition`, `duration`, `isCompleted`, `playCount`, `lastPlayedDate`, `progressUpdatedAt` | The sync-safe *subset* of these is mirrored out through `PlaybackProgressModel` |
| User marks | `isStarred`, `notes`, `upNextDismissedAt` | Not synced (could be, later) |
| Display cache | `imageURL`, `pubDate` | Re-derivable from RSS |

This is the "why both models?" answer: `EpisodeDownloadModel` mixes device-local state (paths) with shareable state (progress). Instead of syncing it and fighting over which fields are safe, the shareable slice is copied into `PlaybackProgressModel`, which exists *only* to be synced. Same pattern as `PodcastInfoModel` → `SubscribedPodcastModel`.

#### `PodcastInfoModel` — *a subscribed/browsed show*
Holds `podcastInfo` (a `PodcastInfo` struct: full RSS snapshot with all episodes, encoded as one blob), plus fast-query mirror fields (`title`, `rssUrl`, `imageURL`, `episodeCount`, `latestEpisodeDate`, `isSubscribed`), feed-refresh metadata (`httpCacheHeader`, `predictedNextReleaseDate`, `detectedCadence`), and per-show settings (`autoTranscribeNewEpisodes`, `autoDownloadSetting`, episode filters, `transcriptionTerms`). Local because the blob is big and re-fetchable; only the `rssUrl` pointer syncs.

#### `EpisodeTranscriptModel` — *transcript storage (replaced SRT files)*
`episodeId` (composite key), `source` ("rss" / "local" / "yapServer"), `segmentsJSON`, `wordTimingsJSON?`, `translationsJSON?`, `plainText` (for search), `generatedAt`. Local: transcripts can be multi-MB (over CloudKit's record cap) and are regenerable on-device.

#### `EpisodeQuickTagsModel` — *lightweight on-device AI tags*
`episodeAudioURL` key, `tags`, categories, `contentType`, `difficulty`, `briefSummary`. Cheap to regenerate; not worth sync traffic.

#### `QueueItemModel` — *Up Next queue*
`id` (composite key), `position`, episode display fields. Local — queue order is a per-device listening session concept.

---

## 4. Who Writes What (data flow)

```
User plays audio
  → EnhancedAudioManager updates EpisodeDownloadModel (local)
      → PlaybackProgressSyncCoordinator.push() copies slice → PlaybackProgressModel (cloud)
          → CloudKit uploads → other devices import
              → NSPersistentStoreRemoteChange fires there
                  → coordinator merges into their EpisodeDownloadModel (updatedAt wins)

User subscribes to show
  → PodcastInfoModel.isSubscribed = true (local)
      → SubscriptionSyncCoordinator.sync() upserts → SubscribedPodcastModel (cloud)
          → other device sees new rssUrl → fetches RSS → creates its own PodcastInfoModel

AI analysis generated (either device)
  → EpisodeAIAnalysis saved directly into cloud store
      → mirrors to other devices as-is (no coordinator needed; readers fetch on view load)
```

---

## 5. Relations: There Are No SwiftData Relationships — On Purpose

No `@Relationship` anywhere. Models join by **string keys**:

| Key | Links |
|---|---|
| `"{podcastTitle}\u{1F}{episodeTitle}"` (composite, `EpisodeKeyUtils`) | `EpisodeDownloadModel.id` ↔ `PlaybackProgressModel.id` ↔ `QueueItemModel.id` ↔ `EpisodeTranscriptModel.episodeId` |
| `rssUrl` | `PodcastInfoModel.rssUrl` ↔ `SubscribedPodcastModel.rssUrl` |
| `audioURL` | `EpisodeDownloadModel.audioURL` ↔ `EpisodeAIAnalysis.episodeAudioURL` ↔ `EpisodeQuickTagsModel.episodeAudioURL` |

Why:
1. **CloudKit can't relate across stores.** A cloud-store model cannot hold a relationship to a local-store model — so `PlaybackProgressModel` ↔ `EpisodeDownloadModel` *must* be a key join.
2. **Resilience.** A synced progress row can arrive before the episode exists locally; a key join tolerates that (we create a placeholder), a hard relationship couldn't.
3. **Simplicity.** No delete rules, no inverse relationships, no cascade surprises.

Trade-off: renamed podcast/episode titles break the composite key. Accepted — titles are stable in practice, and the project explicitly ships no migrations.

---

## 6. Requirements for Sync to Work

- Same Apple ID on both devices, iCloud Drive ON.
- App's iCloud capability with container `iCloud.com.jn.PodcastAnalyzer` (shared entitlements file — single multiplatform target guarantees iOS and macOS use the same container).
- Network. Changes queue offline and flush later.
- Patience: propagation is seconds to minutes; nothing in the app blocks on it.
