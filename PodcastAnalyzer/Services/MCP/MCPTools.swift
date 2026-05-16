//
//  MCPTools.swift
//  PodcastAnalyzer
//
//  Tool registry, schemas, and dispatch for the in-app MCP server.
//

#if os(macOS)
import Foundation
import MCP

/// Stateless catalogue + dispatcher for all MCP tools exposed by the app.
///
/// Marked `nonisolated` so MCP server handler closures (which run on the SDK's
/// internal actor) can reference it without hopping to MainActor. The dispatcher
/// itself hops to MainActor only when it needs to touch SwiftData via the
/// gateway.
nonisolated enum MCPTools {

  // MARK: - Tool catalogue

  static let allTools: [Tool] = [
    Tool(
      name: "list_subscribed_podcasts",
      description: "Lists every podcast the user has subscribed to in this app, with metadata such as title, language, description, image URL, and episode count.",
      inputSchema: objectSchema(properties: [:], required: [])
    ),
    Tool(
      name: "get_podcast",
      description: "Returns full metadata for a single subscribed podcast plus its 10 most recent episodes.",
      inputSchema: objectSchema(
        properties: [
          "podcast_title": stringSchema("Exact podcast title as returned by list_subscribed_podcasts.")
        ],
        required: ["podcast_title"]
      )
    ),
    Tool(
      name: "list_episodes",
      description: "Lists episodes for a podcast, newest first. Supports paging via limit/offset and an optional `since` ISO-8601 cutoff.",
      inputSchema: objectSchema(
        properties: [
          "podcast_title": stringSchema("Exact podcast title."),
          "limit": intSchema("Maximum episodes to return. Default 50, max 500."),
          "offset": intSchema("Number of episodes to skip from the most recent. Default 0."),
          "since": stringSchema("ISO-8601 datetime; only episodes published on or after this date are returned."),
        ],
        required: ["podcast_title"]
      )
    ),
    Tool(
      name: "get_episode",
      description: "Returns full metadata for a single episode, including local audio path if the user has downloaded it.",
      inputSchema: objectSchema(
        properties: [
          "podcast_title": stringSchema("Exact podcast title."),
          "episode_title": stringSchema("Exact episode title."),
        ],
        required: ["podcast_title", "episode_title"]
      )
    ),
    Tool(
      name: "get_transcript",
      description: "Returns the transcript of an episode. If no transcript exists, the call fails — call `generate_transcript` first.",
      inputSchema: objectSchema(
        properties: [
          "podcast_title": stringSchema("Exact podcast title."),
          "episode_title": stringSchema("Exact episode title."),
          "format": enumSchema(["plain", "srt"], description: "Output format. 'plain' (default) strips timestamps; 'srt' preserves them."),
        ],
        required: ["podcast_title", "episode_title"]
      )
    ),
    Tool(
      name: "get_ai_analysis",
      description: "Returns the cached AI analysis of an episode (provider, model, generated time, and the analysis JSON body).",
      inputSchema: objectSchema(
        properties: [
          "podcast_title": stringSchema("Exact podcast title."),
          "episode_title": stringSchema("Exact episode title."),
        ],
        required: ["podcast_title", "episode_title"]
      )
    ),
    Tool(
      name: "search_transcripts",
      description: "Searches all transcribed episodes across the user's subscriptions for a query string. Returns matching snippets with timestamps.",
      inputSchema: objectSchema(
        properties: [
          "query": stringSchema("Free-text search query."),
          "limit": intSchema("Maximum hits to return. Default 20."),
        ],
        required: ["query"]
      )
    ),
    Tool(
      name: "generate_transcript",
      description: "Queues a transcription job for the given episode. Returns immediately with the current job status. Subsequent calls report progress. Use get_transcript once status is 'completed'.",
      inputSchema: objectSchema(
        properties: [
          "podcast_title": stringSchema("Exact podcast title."),
          "episode_title": stringSchema("Exact episode title."),
          "engine": enumSchema(
            ["appleSpeech", "whisper", "yapServer"],
            description: "Optional engine override. Defaults to the user's configured engine. 'yapServer' works without locally downloaded audio if a YAP server URL is configured in Settings."
          ),
          "language": stringSchema("Optional BCP-47 language code (e.g. 'en', 'zh-Hant'). Defaults to the podcast's language."),
        ],
        required: ["podcast_title", "episode_title"]
      )
    ),
  ]

  // MARK: - Dispatch

  static func dispatch(
    _ params: CallTool.Parameters,
    gateway: MCPDataGateway
  ) async -> CallTool.Result {
    do {
      let args = params.arguments ?? [:]
      switch params.name {
      case "list_subscribed_podcasts":
        let list = try await gateway.listSubscribedPodcasts()
        return try jsonResult(list)

      case "get_podcast":
        let title = try requiredString(args, "podcast_title")
        let (dto, recent) = try await gateway.getPodcast(title: title)
        struct Wrapper: Codable { let podcast: MCPPodcastDTO; let recent_episodes: [MCPEpisodeStubDTO] }
        return try jsonResult(Wrapper(podcast: dto, recent_episodes: recent))

      case "list_episodes":
        let title = try requiredString(args, "podcast_title")
        let limit = optionalInt(args, "limit")
        let offset = optionalInt(args, "offset")
        let since = try optionalDate(args, "since")
        let list = try await gateway.listEpisodes(
          podcastTitle: title, limit: limit, offset: offset, since: since
        )
        return try jsonResult(list)

      case "get_episode":
        let p = try requiredString(args, "podcast_title")
        let e = try requiredString(args, "episode_title")
        let dto = try await gateway.getEpisode(podcastTitle: p, episodeTitle: e)
        return try jsonResult(dto)

      case "get_transcript":
        let p = try requiredString(args, "podcast_title")
        let e = try requiredString(args, "episode_title")
        let format = optionalString(args, "format") ?? "plain"
        let dto = try await gateway.getTranscript(
          podcastTitle: p, episodeTitle: e, format: format
        )
        return try jsonResult(dto)

      case "get_ai_analysis":
        let p = try requiredString(args, "podcast_title")
        let e = try requiredString(args, "episode_title")
        let dto = try await gateway.getAIAnalysis(podcastTitle: p, episodeTitle: e)
        return try jsonResult(dto)

      case "search_transcripts":
        let query = try requiredString(args, "query")
        let limit = optionalInt(args, "limit")
        let hits = try await gateway.searchTranscripts(query: query, limit: limit)
        return try jsonResult(hits)

      case "generate_transcript":
        let p = try requiredString(args, "podcast_title")
        let e = try requiredString(args, "episode_title")
        let engine = optionalString(args, "engine")
        let language = optionalString(args, "language")
        let dto = try await gateway.generateTranscript(
          podcastTitle: p, episodeTitle: e, engineRaw: engine, language: language
        )
        return try jsonResult(dto)

      default:
        return errorResult("Unknown tool: \(params.name)")
      }
    } catch let gatewayError as MCPGatewayError {
      return errorResult(gatewayError.description)
    } catch {
      return errorResult("Internal error: \(error)")
    }
  }

  // MARK: - Schema helpers

  private static func objectSchema(properties: [String: Value], required: [String]) -> Value {
    var obj: [String: Value] = [
      "type": .string("object"),
      "properties": .object(properties),
    ]
    if !required.isEmpty {
      obj["required"] = .array(required.map { .string($0) })
    }
    return .object(obj)
  }

  private static func stringSchema(_ description: String) -> Value {
    .object([
      "type": .string("string"),
      "description": .string(description),
    ])
  }

  private static func intSchema(_ description: String) -> Value {
    .object([
      "type": .string("integer"),
      "description": .string(description),
    ])
  }

  private static func enumSchema(_ values: [String], description: String) -> Value {
    .object([
      "type": .string("string"),
      "description": .string(description),
      "enum": .array(values.map { .string($0) }),
    ])
  }

  // MARK: - Argument parsing

  private static func requiredString(_ args: [String: Value], _ key: String) throws -> String {
    guard let value = args[key], let str = value.stringValue, !str.isEmpty else {
      throw MCPGatewayError.invalidArgument("Missing required string argument: \(key)")
    }
    return str
  }

  private static func optionalString(_ args: [String: Value], _ key: String) -> String? {
    guard let value = args[key] else { return nil }
    let str = value.stringValue
    return (str?.isEmpty ?? true) ? nil : str
  }

  private static func optionalInt(_ args: [String: Value], _ key: String) -> Int? {
    guard let value = args[key] else { return nil }
    if let i = value.intValue { return i }
    if let d = value.doubleValue { return Int(d) }
    if let s = value.stringValue, let i = Int(s) { return i }
    return nil
  }

  private static func optionalDate(_ args: [String: Value], _ key: String) throws -> Date? {
    guard let raw = optionalString(args, key) else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: raw) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    if let date = formatter.date(from: raw) { return date }
    throw MCPGatewayError.invalidArgument("\(key) must be an ISO-8601 datetime")
  }

  // MARK: - Result formatting

  private static func jsonResult<T: Codable>(_ value: T) throws -> CallTool.Result {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    let text = String(decoding: data, as: UTF8.self)
    return CallTool.Result(
      content: [.text(text: text, annotations: nil, _meta: nil)],
      isError: false
    )
  }

  private static func errorResult(_ message: String) -> CallTool.Result {
    CallTool.Result(
      content: [.text(text: message, annotations: nil, _meta: nil)],
      isError: true
    )
  }
}

#endif
