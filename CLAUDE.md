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

## Packages

- **FeedKit** 10.2.0 — RSS/Atom parsing
- **ZMarkupParser** 1.12.0 — HTML description rendering
- **Nuke** 12.9.0 — image caching (`NukeUI.LazyImage`)
- **WhisperKit** 0.15.0 — on-device speech-to-text

## File naming

- Audio: `{podcast_title}_{episode_title}.mp3` (spaces/special chars → `_`)
- Captions: `{episode_id}.srt`

---

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
