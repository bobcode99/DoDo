## DoDo

DoDo is an iOS and macOS podcast player for organizing, transcribing, and listening to episodes. It focuses on smarter discovery, on-device transcription, AI-assisted insights, and a polished SwiftUI experience.

> The Xcode project and repository are named `PodcastAnalyzer`; the app ships to the App Store as **DoDo**.

### Features

- **Library**: Subscribe to shows via RSS, browse and manage saved episodes.
- **Player**: Background audio, lock-screen controls, SRT captions synced to playback.
- **Downloads**: Background episode downloads for offline listening.
- **On-device transcription**: Generate transcripts with Apple SpeechAnalyzer or WhisperKit — runs locally, with optional long-audio splitting and per-podcast context bias.
- **AI analysis**: Per-episode insights and transcript-driven features.
- **Search**: Find shows and episodes by title or metadata.
- **SwiftUI + SwiftData**: Modern, responsive interface across iOS and macOS.

### Architecture

`View → ViewModel → Service → SwiftData Model` (MVVM). Built with SwiftUI and SwiftData, Swift 6 concurrency. See `CLAUDE.md` for service responsibilities and conventions.

### Requirements

- **Xcode**: 26 or later.
- **Platforms**: iOS 26+ and macOS 26+.

### Getting started

1. Clone the repository:

```bash
git clone https://github.com/bobcode99/PodcastAnalyzer.git
cd PodcastAnalyzer/PodcastAnalyzer
```

2. Open the Xcode project:

```bash
open PodcastAnalyzer.xcodeproj
```

3. Select the `PodcastAnalyzer` scheme and an iOS Simulator (or device).

4. Build and run (`⌘R`).

### Building from the command line

```bash
# iOS Simulator
xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# macOS
xcodebuild -project PodcastAnalyzer.xcodeproj -scheme PodcastAnalyzer \
  -destination 'platform=macOS' build
```

### Running tests

```bash
xcodebuild test \
  -scheme PodcastAnalyzer \
  -project PodcastAnalyzer.xcodeproj \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PodcastAnalyzerTests
```

GitHub Actions runs the `PodcastAnalyzerTests` unit tests by default.

### Packages

- **FeedKit** — RSS/Atom parsing
- **WhisperKit** — on-device speech-to-text
- **Nuke** — image loading and caching
- **ZMarkupParser** — HTML description rendering

### Contributing

Improvements and bug fixes welcome. Open an issue or pull request with a clear description and, where possible, tests covering your changes.

Useful link: https://castos.com/tools/find-podcast-rss-feed/
