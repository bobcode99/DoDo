# Transcript Search & Background Auto-Transcription Plan



## Context



The PodcastAnalyzer app has a mature transcript system (Apple Speech + WhisperKit) generating SRT files at `~/Documents/Captions/{podcast}/{episode}.srt`. Users cannot search across transcript content today. This adds:



1. **Cross-podcast transcript search** with podcast filtering and episode navigation

2. **Background auto-transcription** when charging (power user feature)



---



## Feature 1: Transcript Search



### Concurrency Strategy



- **`.task(id:)` for search** -- SwiftUI auto-cancels the previous task when `searchQuery` changes, eliminating manual debounce logic entirely

- **`withTaskGroup`** -- scan SRT files across multiple podcasts in parallel (one child task per podcast)

- **`Task.isCancelled` checks** -- between file reads for responsiveness when user types quickly

- **`nonisolated` search function** -- heavy file I/O + string matching runs off MainActor; only result assignment hops back



### Files to Create



#### 1. `ViewModels/TranscriptSearchViewModel.swift` (NEW)



`@MainActor @Observable` view model.



```swift

struct TranscriptSearchResult: Identifiable, Sendable {

    let id: String  // podcastTitle + "\u{1F}" + episodeTitle

    let episode: PodcastEpisodeInfo

    let podcastTitle: String

    let podcastImageURL: String

    let podcastLanguage: String

    let matches: [TranscriptMatch]

}



struct TranscriptMatch: Identifiable, Sendable {

    let id: Int

    let timestamp: TimeInterval

    let text: String  // snippet with context around match

}

```



**Key method — search runs off main actor:**

```swift

func performSearch(query: String, podcasts: [PodcastInfoModel], filterPodcast: String?) async {

    isSearching = true

    let results = await Self.searchTranscripts(query: query, podcasts: podcasts, filter: filterPodcast)

    if !Task.isCancelled {

        self.results = results

    }

    isSearching = false

}



// nonisolated static — runs on cooperative pool, not MainActor

private nonisolated static func searchTranscripts(

    query: String, podcasts: [PodcastInfoModel], filter: String?

) async -> [TranscriptSearchResult] {

    await withTaskGroup(of: [TranscriptSearchResult].self) { group in

        for podcast in podcasts {

            if let filter, filter != podcast.podcastInfo.title { continue }

            group.addTask {

                // Per-podcast: iterate episodes, load SRT, search segments

                // Check Task.isCancelled between episodes

            }

        }

        var all: [TranscriptSearchResult] = []

        for await batch in group { all.append(contentsOf: batch) }

        return all

    }

}

```



Inside each child task:

- Call `FileStorageManager.shared.captionFileExists(for:podcastTitle:)` 

- Load SRT via `FileStorageManager.shared.loadCaptionFile(for:podcastTitle:)`

- Parse with `SRTParser.parseSegments(from:)` — already `nonisolated`

- Match segments with `text.localizedCaseInsensitiveContains(query)`

- Build context snippets (~80 chars around first match occurrence)

- Check `Task.isCancelled` between episodes for fast cancellation



### Files to Modify



#### 2. `Views/SearchView.swift`



**Changes:**

- Add `.transcripts` to `SearchTab` enum (line 13)

- Add `@State private var transcriptSearchVM = TranscriptSearchViewModel()`

- Replace manual debounce for transcript tab with `.task(id:)`:

  ```swift

  .task(id: searchText) {

      // SwiftUI auto-cancels previous task on each keystroke

      guard selectedTab == .transcripts, !searchText.isEmpty else { return }

      try? await Task.sleep(for: .milliseconds(400))  // optional small delay

      guard !Task.isCancelled else { return }

      await transcriptSearchVM.performSearch(

          query: searchText, podcasts: subscribedPodcasts,

          filterPodcast: transcriptSearchVM.selectedPodcastFilter

      )

  }

  ```

- Add `case .transcripts: transcriptResultsView` in the content switch

- New computed view `transcriptResultsView`:

  - Podcast filter `Picker(.menu)` at top

  - `List` of `TranscriptSearchResult` items

  - Each row: artwork, episode title, podcast name, match count, up to 3 snippet previews with timestamps

  - Tap → `NavigationLink` to `EpisodeDetailView` (same pattern as `LibraryEpisodeRow`)

  - Empty state: "No transcript matches" or "No transcripts generated yet"



**No separate row view files** -- define `TranscriptResultRow` as a private struct inside `SearchView.swift`, keeping it simple like the existing `LibraryEpisodeRow` and `ApplePodcastRow`.



### UI Layout



```

[Apple Podcasts] [Library] [Transcripts]     <- glass morphism tabs

─────────────────────────────────────────

[All Podcasts ▾]                             <- Menu picker

─────────────────────────────────────────

 🖼 Episode Title                  3 matches

    Podcast Name · Jan 15

    05:23  "...the impact of AI on..."

    12:45  "...AI models can now..."

─────────────────────────────────────────

 🖼 Another Episode                1 match

    Other Podcast · Feb 3

    15:30  "...AI regulation in..."

```



---



## Feature 2: Background Auto-Transcription While Charging



### Concurrency Strategy



- **`for await` on `NotificationCenter.notifications`** -- async sequence for battery state changes, no manual observer registration

- **`withTaskGroup`** -- parallel scanning of episodes that need transcription

- **Reuse `TranscriptManager.shared.queueTranscript()`** -- don't duplicate job queue logic; just feed it episodes

- **`Task.isCancelled`** -- stop processing when device unplugs



### Files to Create



#### 1. `Services/BackgroundTranscriptProcessor.swift` (NEW)



`@MainActor @Observable` singleton. Minimal state:



```swift

@MainActor @Observable

final class BackgroundTranscriptProcessor {

    static let shared = BackgroundTranscriptProcessor()

    

    var isEnabled: Bool { didSet { UserDefaults.standard.set(isEnabled, forKey: "autoTranscribeWhileCharging") } }

    var isProcessing = false

    var pendingCount = 0  // episodes needing transcription

    var processedCount = 0

    

    private var monitorTask: Task<Void, Never>?

}

```



**Key methods:**

- `startMonitoring()` -- starts a long-lived task that uses `for await` on `NotificationCenter.default.notifications(named: UIDevice.batteryStateDidChangeNotification)` to react to charging state changes. When charging begins and `isEnabled`, calls `processAll()`.

- `processAll(podcasts:)`:

  1. Fetch all subscribed podcasts (passed from caller or fetched via ModelContext)

  2. For each episode across all podcasts, check `FileStorageManager.captionFileExists()` and `DownloadManager` state

  3. For downloaded episodes without transcripts → `TranscriptManager.shared.queueTranscript()`

  4. For non-downloaded episodes → first download via `DownloadManager`, then queue transcript

  5. Periodically check `UIDevice.current.batteryState` — stop if unplugged

- `cancelProcessing()` -- cancels the processing task



**No complex status enum** -- just `isProcessing`, `pendingCount`, `processedCount`. The existing `TranscriptManager.activeJobs` already shows per-job progress in the UI.



### Files to Modify



#### 2. `Views/SettingsView.swift`



Add a new section after the existing "Transcript" section:



```swift

Section {

    Toggle("Auto-Transcribe While Charging", isOn: ...)

    // Show processing status inline when active

    if processor.isProcessing {

        LabeledContent("Progress") {

            Text("\(processor.processedCount) of \(processor.pendingCount)")

        }

    }

    Button("Process All Now") { ... }

        .disabled(processor.isProcessing)

} header: {

    Text("Background Transcription")

} footer: {

    Text("Automatically transcribe downloaded episodes when charging")

}

```



#### 3. `PodcastAnalyzerApp.swift`



Add one line in the app's scene body `.onAppear` or `init`:

```swift

BackgroundTranscriptProcessor.shared.startMonitoring()

```



#### 4. `Views/DataManagementView.swift`



Add per-podcast transcript deletion: list podcasts with transcript counts, swipe to delete a podcast's transcripts via `FileStorageManager.shared.deleteCaptionFile()` for each episode.



---



## Implementation Order



### Phase 1: Transcript Search

1. Create `TranscriptSearchViewModel.swift` with `withTaskGroup`-based parallel search

2. Add `.transcripts` case to `SearchTab` enum

3. Add transcript search UI + `.task(id: searchText)` wiring

4. Add podcast filter picker and result navigation



### Phase 2: Background Auto-Transcription

1. Create `BackgroundTranscriptProcessor.swift` with async notification monitoring

2. Add settings section to `SettingsView.swift`

3. Wire up charging monitor in `PodcastAnalyzerApp.swift`

4. Add per-podcast transcript deletion to `DataManagementView.swift`



---



## Key Reuse



| Component | Used For |

|---|---|

| `FileStorageManager.captionFileExists/loadCaptionFile` | Check + load SRT files |

| `SRTParser.parseSegments()` | Parse SRT into timed segments |

| `TranscriptManager.shared.queueTranscript()` | Queue bulk transcription |

| `DownloadManager.shared` | Download episodes for auto-transcription |

| `SearchTabButton` + `.glassEffect()` | Tab button styling |

| `CachedArtworkImage` | Artwork in results |

| `EpisodeDetailView` navigation | Navigate from results |



---



## Verification



1. `xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17' build`

2. Verify "Transcripts" tab appears and search works with existing SRT files

3. Verify `.task(id:)` auto-cancels on rapid typing (no lag)

4. Verify podcast filter narrows results

5. Verify tapping result navigates to episode detail

6. Verify auto-transcribe toggle persists and processing starts when charging

7. `xcodebuild test -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer -destination 'platform=iOS Simulator,name=iPhone 17'`

