---
name: Yap Server transcript engine
description: YapTranscriptService actor + YapServerSettings added as a third TranscriptEngine case (.yapServer)
type: project
---

A `.yapServer` engine case was added to `TranscriptEngine` (in `TranscriptEngineSettings.swift`).

- `YapTranscriptService` actor is at `Services/YapTranscriptService.swift` — streams audio via `URLSession.upload(for:fromFile:)`, polls with exponential backoff (1s→5s cap), returns SRT string or throws `YapError`.
- `YapServerSettings` (`@MainActor @Observable`) lives at the bottom of `TranscriptEngineSettings.swift`, persists serverURL + apiKey to UserDefaults.
- `TranscriptManager.processJob(_:)` has a `.yapServer` case: skips model download, reads settings on `@MainActor` with `await MainActor.run { }`, then calls the actor.
- `YapServerSection` view at `Views/Settings/YapServerSection.swift` is shown in `SettingsView` when engine == `.yapServer`.
- Two other exhaustive switches needed updating when the new case was added: `SettingsViewModel.locales(for:)` and `EpisodeDetailViewModel` language switch expression.

**Why:** User built a local macOS yap HTTP server wrapping Apple Speech and wants to use it as a transcription backend from iOS.

**How to apply:** When adding future `TranscriptEngine` cases, search for exhaustive switches on `TranscriptEngine` — there are at least 4 sites that need updating.
