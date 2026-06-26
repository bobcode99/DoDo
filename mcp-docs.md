# PodcastAnalyzer MCP server

PodcastAnalyzer embeds an HTTP [Model Context Protocol][mcp] server inside
the macOS app. Once enabled, LLM clients running on the same Mac can query
your podcast library, read transcripts and AI analyses, and ask the app to
transcribe an episode.

The server:

- runs **only on macOS** (the iOS build doesn't include it),
- binds only to `127.0.0.1` (loopback — nothing on your network can reach it),
- requires a **Bearer token** on every request,
- only runs while the app is running (Preferences → MCP also includes a
  "Run as menubar app" mode + "Open at Login" so it can stay quietly available).

[mcp]: https://modelcontextprotocol.io/

---

## 1. Enable the server

Open **PodcastAnalyzer → Settings… → MCP**.

1. Flip **Enable MCP server** on.
2. The status row turns green: `● Running at http://127.0.0.1:7842/mcp`.
3. The bearer token is generated on first run and stored in the macOS
   Keychain. Click the eye icon to reveal it, or the copy icon to put it on
   the clipboard.

Default port is `7842`. Change it in the **Port** field; the server restarts
automatically.

### Smoke-test from the terminal

```bash
TOKEN=<paste from Settings>

# Health probe (no auth required)
curl -s http://127.0.0.1:7842/healthz
# → {"status":"ok","server":"PodcastAnalyzer-MCP"}

# tools/list
curl -s -X POST http://127.0.0.1:7842/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

A missing/invalid `Authorization` header returns **401 Unauthorized** with a
JSON-RPC error body.

---

## 2. Connect a client

The Settings tab has three buttons under **Connect a client** that copy
ready-to-paste configuration to your clipboard.

### Claude Code (native HTTP)

Fastest path: the **"Copy Claude Code CLI command"** button puts a
one-liner on your clipboard — paste it into a terminal:

```bash
claude mcp add --transport http pod-analyzer http://127.0.0.1:7842/mcp \
  --header "Authorization: Bearer <YOUR_TOKEN>"
```

Alternative: the **"Copy Claude Code config (HTTP)"** button gives you the
JSON form if you'd rather edit the config file directly:

```json
{
  "mcpServers": {
    "podcast-analyzer": {
      "url": "http://127.0.0.1:7842/mcp",
      "headers": {
        "Authorization": "Bearer <YOUR_TOKEN>"
      }
    }
  }
}
```

Restart Claude Code afterward. The `pod-analyzer` server appears with all
8 tools.

### Claude Desktop (stdio shim via `mcp-remote`)

Claude Desktop currently only speaks **stdio** MCP. The "Copy Claude Desktop
config" button emits a config that uses the open-source
[`mcp-remote`][mcp-remote] proxy to bridge stdio → this HTTP server:

```json
{
  "mcpServers": {
    "podcast-analyzer": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote",
        "http://127.0.0.1:7842/mcp",
        "--header",
        "Authorization: Bearer <YOUR_TOKEN>"
      ]
    }
  }
}
```

Paste it into `~/Library/Application Support/Claude/claude_desktop_config.json`
and restart Claude Desktop. Requires Node.js installed (Claude Desktop runs
`npx` to fetch `mcp-remote`).

[mcp-remote]: https://www.npmjs.com/package/mcp-remote

### ChatGPT / generic HTTP-capable MCP clients

Any client that supports streamable-HTTP MCP can connect using the same
URL + `Authorization: Bearer <token>` header. The Settings "Copy connection
URL" button gives you the URL alone.

---

## 3. Tools

All tools accept JSON inputs and return JSON outputs as MCP text content.
Dates are ISO-8601. All `*_title` fields require **exact** strings as
returned by `list_subscribed_podcasts` / `list_episodes`.

| Tool | Input | Output |
|------|-------|--------|
| `list_subscribed_podcasts` | `{}` | `[{ title, language, description, image_url, rss_url, episode_count, last_updated, date_added, auto_transcribe_enabled }]` |
| `get_podcast` | `{ podcast_title }` | `{ podcast, recent_episodes }` — full podcast DTO plus 10 most-recent episodes |
| `list_episodes` | `{ podcast_title, limit?, offset?, since? }` | `[{ title, pub_date, duration_seconds, audio_url, image_url, has_transcript, has_ai_analysis, is_completed, last_playback_position, has_local_audio }]` |
| `get_episode` | `{ podcast_title, episode_title }` | Full episode DTO incl. `local_audio_path` when downloaded |
| `get_transcript` | `{ podcast_title, episode_title, format? }` | `{ format, content, podcast_title, episode_title }`. `format` is `"plain"` (default) or `"srt"` |
| `get_ai_analysis` | `{ podcast_title, episode_title }` | `{ provider, model, generated_at, analysis_json }` (analysis JSON is a stringified `ParsedEpisodeAnalysisResponse`) |
| `search_transcripts` | `{ query, limit? = 20 }` | `[{ podcast_title, episode_title, snippet, timestamp_seconds, match_count }]` |
| `generate_transcript` | `{ podcast_title, episode_title, engine?, language? }` | `{ status, progress?, message, job_key, error? }` — fire-and-forget; repeat call reports current status |

### `generate_transcript` notes

- `engine` (optional): `"appleSpeech"`, `"whisper"`, or `"yapServer"`. Omitting it uses your current default from Preferences → Transcript.
- `language` (optional): BCP-47 code like `"en"` or `"zh-Hant"`. Defaults to the podcast's language.
- Returns immediately. Repeat the call to poll status:
  - `"queued"` → waiting in the queue
  - `"downloading_model"` → first-run model download (Apple Speech / Whisper)
  - `"transcribing"` → in progress; `progress` is `0…1`
  - `"completed"` → transcript is on disk; use `get_transcript` to read it
  - `"failed"` → see `error`
- For **Apple Speech** or **Whisper**, the episode must already be downloaded locally. The call returns `Invalid argument` otherwise.
- For **`yapServer`**, the call works without a local download if a YAP server URL is configured in Preferences → Transcript.

### Example: `tools/call`

```bash
curl -s -X POST http://127.0.0.1:7842/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "id": 42,
    "method": "tools/call",
    "params": {
      "name": "get_transcript",
      "arguments": {
        "podcast_title": "Acquired",
        "episode_title": "Costco",
        "format": "plain"
      }
    }
  }'
```

---

## 4. Headless / menubar / launch at login

Preferences → MCP includes three independent headless controls:

- **Run as menubar app (hide dock icon)** — flips
  `NSApp.activationPolicy` between `.regular` (dock app) and `.accessory`
  (menubar only). Works at runtime; no app restart needed.
- **Open at Login** — registers the app with `SMAppService.mainApp` so
  macOS launches it after login. Pairs naturally with menubar mode for a
  "quiet background" setup.
- **Menubar icon** — always present when the MCP server is running or
  when accessory mode is on. Provides:
  - Status line ("MCP server: 127.0.0.1:7842" / "stopped" / error)
  - Start / Stop MCP server
  - Open Main Window (re-shows the dock icon when in accessory mode)
  - Quit PodcastAnalyzer

---

## 5. Security

- **Loopback only.** The server binds to `127.0.0.1`, never `0.0.0.0`. Other
  devices on your Wi-Fi cannot reach it.
- **Bearer token required.** Every `POST /mcp` request must include
  `Authorization: Bearer <token>`. Comparison is constant-time. Missing or
  bad tokens get 401.
- **Token in Keychain.** The token is stored under service
  `com.jn.PodcastAnalyzer.mcp` / account `bearerToken` with
  `kSecAttrAccessibleAfterFirstUnlock`. macOS may show a Keychain dialog
  the first time the app reads it.
- **Regenerate any time.** "Regenerate token" mints a fresh 32-byte
  base64url token and restarts the server. Any client still holding the old
  token gets 401 until you update its config.

A locally-running process on the same Mac with the token can reach the
server. Treat the token as a password: don't paste it into chats, public
gists, or version control.

---

## 6. Architecture cheatsheet

```
LLM client
   │ HTTP POST /mcp + Bearer
   ▼
Hummingbird (127.0.0.1:7842)
   │ Request → MCP.HTTPRequest
   ▼
StatelessHTTPServerTransport       ← validation pipeline:
   │                                 OriginValidator.localhost()
   │                                 AcceptHeaderValidator(.jsonOnly)
   │                                 ContentTypeValidator
   │                                 ProtocolVersionValidator
   │                                 MCPBearerTokenValidator
   ▼
MCP.Server (actor)                 ← registered handlers:
   │                                 ListTools.self  → MCPTools.allTools
   │                                 CallTool.self   → MCPTools.dispatch
   ▼
MCPDataGateway (@MainActor)        ← SwiftData fetches via mainContext,
   │                                 returns nonisolated Codable DTOs
   ▼
PodcastInfoModel / EpisodeDownloadModel /
EpisodeAIAnalysis / FileStorageManager /
TranscriptManager
```

Key files (under `PodcastAnalyzer/`):

- `Services/MCP/MCPHTTPServer.swift` — Hummingbird ↔ MCP transport bridge
- `Services/MCP/MCPTools.swift` — schema + dispatch for all 8 tools
- `Services/MCP/MCPDataGateway.swift` — DTOs + SwiftData reads
- `Services/MCP/MCPAuth.swift` — Keychain token + bearer validator
- `Services/MCP/MCPServerManager.swift` — `@MainActor` lifecycle singleton
- `Services/MCP/MCPMenubarController.swift` — NSStatusItem owner
- `Views/macOS/MacMCPSettingsView.swift` — Preferences tab

---

## 7. Troubleshooting

**Status shows `Error: address already in use`.**
Another process is holding port 7842. Pick a different port in Settings,
or find the culprit with `lsof -i :7842`.

**401 Unauthorized in `curl`.**
The `Authorization` header is missing, malformed (must be exactly
`Bearer <token>`), or the token doesn't match. Copy it again from
Settings — it changes whenever you click "Regenerate token".

**406 Not Acceptable.**
Add `Accept: application/json` to the request. The stateless transport
expects JSON Accept; without it the validation pipeline rejects.

**`generate_transcript` returns "No local audio".**
The episode isn't downloaded. Either download it inside the app first, or
pass `"engine": "yapServer"` if you have YAP configured.

**`get_transcript` returns "No transcript for …".**
Call `generate_transcript` first, then poll until status is `"completed"`,
then call `get_transcript` again.

**Claude Desktop doesn't see the server after pasting the config.**
Make sure Node.js is installed (`node -v` works). Restart Claude Desktop
completely (quit from the dock, not just close the window). Check Claude
Desktop's MCP logs for `mcp-remote` errors.

**Menubar icon shows a warning triangle.**
Hover for the tooltip — it shows the underlying error. Common causes: port
conflict, Keychain access denied. Restart the app or check Console.app for
the `com.podcast.analyzer / MCPServerManager` log category.

---

## 8. What's out of scope (for now)

- **Mutating tools** beyond `generate_transcript` (no subscribe, no
  mark-played, no trigger-AI-analysis). v1 is read-mostly by design.
- **Streaming responses (SSE)** — the server uses the stateless transport.
  Tool responses fit in a single HTTP response; we'll add SSE only if a
  tool needs to stream.
- **Custom stdio sidecar binary** — Claude Desktop users go through
  `mcp-remote`. If that proves unreliable we'll ship our own helper later.
- **iOS** — the entire MCP stack is gated `#if os(macOS)`.

---

## 9. Versioning

The server reports `name: "PodcastAnalyzer"`, `version: "1.0.0"` in the MCP
`initialize` handshake. Bump the version in
`Services/MCP/MCPHTTPServer.swift` (`Server(...)` init) when the tool
surface changes in a way clients should notice.
