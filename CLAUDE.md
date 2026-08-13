# CLAUDE.md

iOS/macOS podcast player — SwiftUI + SwiftData, MVVM.

## Build & Test

```bash
# Build (iOS Simulator)
xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Build (macOS)
xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer \
  -destination 'platform=macOS' build

# All tests
xcodebuild test -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Single test
xcodebuild test ... -only-testing:PodcastAnalyzerTests/SuiteName/testName
```

## Architecture

`View → ViewModel → Service → SwiftData Model`

**Entry:** `PodcastAnalyzerApp.swift` → `ContentView.swift` (TabView: Home / Settings / Search + MiniPlayerBar overlay)

**Key services (singletons unless noted):**
| Service | Notes |
|---------|-------|
| `EnhancedAudioManager.shared` | AVPlayer, lock screen controls, SRT captions |
| `PodcastRssService` | Actor — RSS parsing via FeedKit |
| `DownloadManager.shared` | URLSession background downloads |
| `FileStorageManager.shared` | Actor — audio (`~/Library/Audio/`), captions (`~/Documents/Captions/`) |

**SwiftData models:** `PodcastInfoModel`, `EpisodeDownloadModel`, `QueueItemModel`, `EpisodeAIAnalysis`, `EpisodeQuickTagsModel`

**Runtime structs:** `PodcastInfo`, `PodcastEpisodeInfo`, `PlaybackEpisode`, `LibraryEpisode`

**Episode composite key:** `"\(podcastTitle)\u{1F}\(episodeTitle)"` — used as the upsert key in `EpisodeDownloadModel`.

## Critical Rules

- **Audio:** Never create multiple `AVPlayer` instances — always use `EnhancedAudioManager.shared`.
- **Downloads:** Keyed by `audioURL`. States: `notDownloaded → downloading(%) → downloaded(path) | failed(error)`.
- **Schema migrations:** Not implemented — schema changes reset data. Break old formats freely.
- **No backward compatibility**: Break old formats freely.

## File naming

- Audio: `{podcast_title}_{episode_title}.mp3` (spaces/special chars → `_`)
- Captions: `{episode_id}.srt`
