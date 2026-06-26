---
name: Remote Transcription Backend Integration
description: Two new remote transcript engines (Scriberr self-hosted, ElevenLabs Scribe cloud) wired into the existing TranscriptEngine/TranscriptManager pipeline
type: project
---

Added remote transcription backends in the `ui-fixes-transcript-enhance` branch.

New files:
- `Models/RemoteTranscriptSettings.swift` — `@MainActor @Observable` singleton persisting credentials (scriberBaseURL, scriberAPIKey, elevenLabsAPIKey) to UserDefaults via `didSet`
- `Services/ScriberTranscriptService.swift` — actor; POSTs multipart audio to `/api/v1/transcription/submit`, polls `/api/v1/transcription/{id}/status` every 3 s (max 200 polls), converts WhisperX segment JSON to SRT
- `Services/ElevenLabsTranscriptService.swift` — actor; POSTs to `https://api.elevenlabs.io/v1/speech-to-text` with `scribe_v2`, prefers `source_url` (RSS URL) over file upload; fake progress Task runs concurrently

Modified files:
- `Models/TranscriptEngineSettings.swift` — added `.scriberr` and `.elevenLabsScribe` cases to `TranscriptEngine`
- `Services/TranscriptManager.swift` — added `remoteAudioURL: String?` to `TranscriptJob`, `queueTranscript`, and two new switch cases in `processJob()`
- `ViewModels/EpisodeDetailViewModel.swift` — passes `episode.audioURL` as `remoteAudioURL` in `generateTranscript()`
- `ViewModels/SettingsViewModel.swift` — `locales(for:)` switch extended to handle new cases
- `Views/SettingsView.swift` — conditional `ScriberConfigSection` / `ElevenLabsConfigSection` views with connection test buttons; `footerText(for:)` helper; `ConnectionTestState: Equatable` enum

**Why:** actor-isolated `audioToSRTWithProgress` methods must be called with `await` even when iterating the returned `AsyncThrowingStream` — same pattern as existing `WhisperTranscriptService`. Any new `TranscriptEngine` case also requires updating `SettingsViewModel.locales(for:)` or the build will fail with "Switch must be exhaustive".
