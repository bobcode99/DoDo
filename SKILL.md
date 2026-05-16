---
name: podcast-analyzer-mcp
description: Use the PodcastAnalyzer MCP server to read a user's podcast library, episode metadata, transcripts, and AI analyses on macOS — and to ask the app to transcribe an episode. Loopback HTTP + Bearer token.
---

# PodcastAnalyzer MCP — agent guide

You are talking to the user's **local macOS app**. The server runs on
`http://127.0.0.1:<port>/mcp` (default port `7842`) and requires
`Authorization: Bearer <token>`. The user pastes the URL and token into
your client config from Preferences → MCP.

## When to use which tool

| Goal | Call |
|------|------|
| "What podcasts do I follow?" | `list_subscribed_podcasts` |
| "Tell me about X podcast" | `get_podcast` |
| "What's new on X / list episodes" | `list_episodes` |
| "Summarize / pull facts from episode Y" | `get_transcript`, then summarize yourself; or `get_ai_analysis` if the user already ran AI on it |
| "Find episodes that mention Z" | `search_transcripts` |
| "Transcribe episode Y for me" | `generate_transcript`, then **poll** the same call until `status == "completed"`, then `get_transcript` |

## Hard rules — read before calling

1. **Exact titles.** `podcast_title` and `episode_title` must be the literal
   strings returned by `list_subscribed_podcasts` / `list_episodes`. No
   trimming, case-folding, or "did you mean". If you didn't get the title
   from a list call this session, **call the list first** — don't guess.
2. **No fuzzy resolution.** If `get_episode` or `get_transcript` returns
   "not found", the title is wrong. Re-list and pick the exact match;
   don't retry with variations.
3. **Transcripts may not exist.** `get_transcript` errors when the episode
   has no transcript. Check `has_transcript` on the episode stub first,
   or fall back to `generate_transcript`.
4. **AI analyses are user-triggered.** `get_ai_analysis` returns the
   stored result if the user ran AI inside the app. There is **no** tool
   to start an AI analysis remotely. If `has_ai_analysis` is false, tell
   the user it needs to be generated in-app.
5. **`generate_transcript` is fire-and-forget.** It returns immediately
   with a status, never waits for completion. Poll by **calling the same
   tool again** with the same arguments. Don't spam — wait 5–15s between
   polls. Long episodes can take minutes.
6. **Local audio gate.** For `engine: "appleSpeech"` or `"whisper"`, the
   episode must already be downloaded in the app. If you get
   `"No local audio"`, tell the user to download it (you can't do that
   remotely) — or retry with `engine: "yapServer"` if you know they have
   YAP configured.

## Common workflows

### Summarize a recent episode

```
list_subscribed_podcasts                       → pick exact podcast_title
list_episodes  {podcast_title, limit: 10}      → pick exact episode_title
                                                  check has_transcript
if has_transcript:
  get_transcript {podcast_title, episode_title}  → summarize the text
else if has_ai_analysis:
  get_ai_analysis {…}                          → use stored summary
else:
  generate_transcript {…}                      → poll → get_transcript
```

### Cross-podcast topic search

```
search_transcripts {query: "vector databases", limit: 20}
   → list of hits with snippet + timestamp_seconds + podcast/episode titles
   → for each hit you want to expand: get_transcript for full text
```

Snippets are short; if the user asks for "more context", fetch the full
transcript and grep around the timestamp yourself.

### Transcribe on demand

```
get_episode {…}                                → confirm exists, check has_local_audio
generate_transcript {podcast_title, episode_title}
   → status: "queued" | "downloading_model" | "transcribing" | "completed" | "failed"
   → on "transcribing", `progress` is 0…1
wait 5–15s, call again, repeat until "completed"
get_transcript {…}                             → full text
```

Optional args:
- `engine`: `"appleSpeech"` | `"whisper"` | `"yapServer"` (default = user setting)
- `language`: BCP-47, e.g. `"en"`, `"zh-Hant"` (default = podcast language)

## Formats

- `get_transcript` default `format: "plain"` — clean text, one line per
  caption. Use `"srt"` only if the user explicitly wants timestamps in
  SRT form.
- `get_ai_analysis` returns `analysis_json` as a **stringified** JSON
  object (the app's `ParsedEpisodeAnalysisResponse`). Parse it before
  using fields.
- All dates ISO-8601, durations in seconds, IDs derived from titles.

## Error handling

| Error | What it means | Recovery |
|-------|---------------|----------|
| 401 Unauthorized | Missing/wrong Bearer | Ask user for a fresh token from Preferences → MCP |
| `invalidParams` "Podcast not found" | Wrong `podcast_title` | Re-call `list_subscribed_podcasts`, match exactly |
| `invalidParams` "No transcript for …" | Episode has no transcript | Call `generate_transcript`, then poll |
| `invalidParams` "No local audio" | `generate_transcript` with Apple/Whisper engine but episode not downloaded | Tell user to download in-app, or use `yapServer` |
| Connection refused | Server toggled off or app quit | Tell user to open the app and enable MCP in Preferences |

## What you cannot do

- Subscribe / unsubscribe from a podcast.
- Mark an episode played, change playback position, or queue.
- Delete a transcript, AI analysis, or download.
- Stream audio.
- Reach any data outside the user's subscribed library.
- Start an AI analysis remotely (only `generate_transcript` is mutating).

If the user asks for any of the above, say it's read-mostly v1 and they
need to do it inside the app.

## Tone

The user is on **their own Mac**. Treat results as authoritative ground
truth about their library — don't second-guess titles, dates, or counts
that come back. If something looks off, surface it instead of silently
"correcting" it.
