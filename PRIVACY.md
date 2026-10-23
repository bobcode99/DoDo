# DoDo Privacy Policy

_Last updated: October 23, 2026_

DoDo ("the app") is a podcast player for iPhone, iPad and Apple Watch. This policy explains what data the app handles and where it goes.

## Summary

- No account is required.
- No ads, no analytics, no tracking.
- The developer does not operate any server and does not collect your data.

## Data stored on your device

Your subscriptions, episodes, playback progress, queue, downloads, transcripts, AI summaries and settings are stored locally on your device.

If iCloud is enabled for DoDo, this data syncs between your devices through your private iCloud account. Apple handles that storage under the [Apple Privacy Policy](https://www.apple.com/legal/privacy/). The developer cannot access it.

The Apple Watch app gets your shows, queue and playback progress directly from your paired iPhone.

## Network requests the app makes

- **Podcast feeds and audio** are downloaded directly from the podcast publishers' servers you subscribe to. Those publishers may see your IP address, as with any podcast app.
- **Search and charts** use Apple's public Apple Podcasts / iTunes APIs.

## Transcripts

- **Publisher transcripts.** If a podcast's feed includes a transcript, the app downloads it from the publisher's server, the same way it downloads the audio.
- **Generated transcripts are made on your device.** With Apple Speech or Whisper, audio is transcribed on your device and is not sent anywhere. Before the first use, the app downloads the speech model: Apple Speech language files come from Apple, and Whisper models come from Hugging Face. If an episode isn't downloaded yet, the app fetches its audio from the publisher to transcribe it.
- **Optional yap server.** If you enter the address of your own yap transcription server, the episode's audio file, or its audio link, is sent only to that address.

## AI

- **AI summaries use the provider you choose.** AI features are off until you set up a provider. Nothing is sent anywhere until you do.
- **Apple Intelligence via Shortcuts.** If you route AI requests through a Shortcut, the text is handled by the Shortcuts app and the actions you build, under Apple's privacy terms.
- **Cloud AI providers.** If you choose to enter your own API key for OpenAI, Anthropic, Google Gemini, Groq or xAI, the episode text you ask about (such as transcript excerpts and show notes) is sent to that provider to generate a response. Your use is governed by that provider's privacy policy. API keys are stored in your device's Keychain.
- **Optional self-hosted servers and connectors.** If you configure your own model server or MCP connector, text is sent only to the address you enter.

## Clipboard

The app reads the clipboard only when you choose to paste a podcast RSS feed or episode link.

## Children

The app does not knowingly collect any personal information from anyone, including children.

## Changes

Updates to this policy will be posted on this page with a new "Last updated" date.

## Contact

Questions: open an issue at <https://github.com/bobcode99/DoDo/issues>.
