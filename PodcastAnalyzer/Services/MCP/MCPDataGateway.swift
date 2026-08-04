//
//  MCPDataGateway.swift
//  PodcastAnalyzer
//
//  MainActor-isolated bridge between MCP tool handlers and SwiftData / managers.
//  Tool handlers call methods here; everything returns plain Sendable DTOs so
//  the MCP server can serialize them into JSON without touching SwiftData models
//  off the main actor.
//

#if os(macOS)
import Foundation
import SwiftData

// MARK: - DTOs
//
// All DTOs are explicitly `nonisolated` so their synthesized Codable / Sendable
// conformances don't get implicitly MainActor-isolated under
// `SWIFT_APPROACHABLE_CONCURRENCY`. They must be safely usable from the MCP
// server's @Sendable handler closures, which run off the main actor.

nonisolated struct MCPPodcastDTO: Sendable, Codable {
  let title: String
  let language: String
  let description: String?
  let imageURL: String
  let rssURL: String
  let episodeCount: Int
  let lastUpdated: Date?
  let dateAdded: Date?
  let autoTranscribeEnabled: Bool
}

nonisolated struct MCPEpisodeStubDTO: Sendable, Codable {
  let title: String
  let pubDate: Date?
  let durationSeconds: Int?
  let audioURL: String?
  let imageURL: String?
  let hasTranscript: Bool
  let hasAIAnalysis: Bool
  let isCompleted: Bool
  let lastPlaybackPosition: TimeInterval
  let hasLocalAudio: Bool
}

nonisolated struct MCPEpisodeDetailDTO: Sendable, Codable {
  let title: String
  let podcastTitle: String
  let pubDate: Date?
  let durationSeconds: Int?
  let description: String?
  let audioURL: String?
  let imageURL: String?
  let guid: String?
  let hasTranscript: Bool
  let hasAIAnalysis: Bool
  let hasLocalAudio: Bool
  let localAudioPath: String?
  let isCompleted: Bool
  let lastPlaybackPosition: TimeInterval
  let playCount: Int
  let isStarred: Bool
}

nonisolated struct MCPTranscriptDTO: Sendable, Codable {
  let format: String  // "srt" or "plain"
  let content: String
  let podcastTitle: String
  let episodeTitle: String
}

nonisolated struct MCPAIAnalysisDTO: Sendable, Codable {
  let podcastTitle: String
  let episodeTitle: String
  let provider: String?
  let model: String?
  let generatedAt: Date?
  /// Stringified JSON of the parsed analysis. Clients can re-parse if needed;
  /// keeping it as a single field avoids leaking internal struct shapes through MCP.
  let analysisJSON: String?
}

nonisolated struct MCPSearchHitDTO: Sendable, Codable {
  let podcastTitle: String
  let episodeTitle: String
  let snippet: String
  let timestampSeconds: TimeInterval
  let matchCount: Int
}

nonisolated struct MCPTranscriptJobDTO: Sendable, Codable {
  /// One of: "queued" | "downloading_model" | "transcribing" | "completed" | "failed" | "started"
  let status: String
  let progress: Double?
  let message: String
  let jobKey: String
  let error: String?
}

/// Errors thrown by the gateway. Mapped to MCP errors by the dispatcher.
nonisolated enum MCPGatewayError: Error, CustomStringConvertible {
  case podcastNotFound(String)
  case episodeNotFound(podcast: String, episode: String)
  case transcriptNotFound(podcast: String, episode: String)
  case aiAnalysisNotFound(podcast: String, episode: String)
  case audioUnavailable(podcast: String, episode: String, reason: String)
  case invalidArgument(String)

  var description: String {
    switch self {
    case .podcastNotFound(let t): return "Podcast not found: \(t)"
    case .episodeNotFound(let p, let e): return "Episode not found: \(p) — \(e)"
    case .transcriptNotFound(let p, let e):
      return "No transcript for \(p) — \(e). Call generate_transcript first."
    case .aiAnalysisNotFound(let p, let e):
      return "No AI analysis for \(p) — \(e)."
    case .audioUnavailable(let p, let e, let reason):
      return "Cannot transcribe \(p) — \(e): \(reason)"
    case .invalidArgument(let msg): return "Invalid argument: \(msg)"
    }
  }
}

// MARK: - Gateway

/// All methods on this type run on the main actor because SwiftData's
/// `ModelContext.mainContext` and `TranscriptManager.shared` are MainActor-bound.
@MainActor
final class MCPDataGateway {
  /// Ceilings enforced on client-supplied `limit` arguments. Kept in sync with
  /// the numbers the tool schemas advertise in `MCPTools.allTools`.
  static let maxEpisodeLimit = 500
  static let maxSearchHits = 100

  private let container: ModelContainer
  private var modelContext: ModelContext { container.mainContext }

  init(modelContainer: ModelContainer) {
    self.container = modelContainer
  }

  // MARK: list_subscribed_podcasts

  func listSubscribedPodcasts() async throws -> [MCPPodcastDTO] {
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.isSubscribed == true },
      sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
    )
    let models = try modelContext.fetch(descriptor)
    return models.map { model in
      MCPPodcastDTO(
        title: model.podcastInfo.title,
        language: model.podcastInfo.language,
        description: model.podcastInfo.podcastInfoDescription,
        imageURL: model.podcastInfo.imageURL,
        rssURL: model.podcastInfo.rssUrl,
        episodeCount: model.podcastInfo.episodes.count,
        lastUpdated: model.lastUpdated,
        dateAdded: model.dateAdded,
        autoTranscribeEnabled: model.autoTranscribeNewEpisodes
      )
    }
  }

  // MARK: get_podcast

  func getPodcast(title: String) async throws -> (podcast: MCPPodcastDTO, recentEpisodes: [MCPEpisodeStubDTO]) {
    let model = try fetchPodcast(title: title)
    let dto = MCPPodcastDTO(
      title: model.podcastInfo.title,
      language: model.podcastInfo.language,
      description: model.podcastInfo.podcastInfoDescription,
      imageURL: model.podcastInfo.imageURL,
      rssURL: model.podcastInfo.rssUrl,
      episodeCount: model.podcastInfo.episodes.count,
      lastUpdated: model.lastUpdated,
      dateAdded: model.dateAdded,
      autoTranscribeEnabled: model.autoTranscribeNewEpisodes
    )
    let sorted = model.podcastInfo.episodes.sorted {
      ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast)
    }
    var recent: [MCPEpisodeStubDTO] = []
    for episode in sorted.prefix(10) {
      recent.append(await mapEpisodeStub(episode, podcastTitle: model.podcastInfo.title))
    }
    return (dto, recent)
  }

  // MARK: list_episodes

  func listEpisodes(
    podcastTitle: String,
    limit: Int?,
    offset: Int?,
    since: Date?
  ) async throws -> [MCPEpisodeStubDTO] {
    let model = try fetchPodcast(title: podcastTitle)
    var episodes = model.podcastInfo.episodes
    if let since {
      episodes = episodes.filter { ($0.pubDate ?? .distantPast) >= since }
    }
    episodes.sort { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
    let start = max(0, offset ?? 0)
    // Clamped to the ceiling the tool schema advertises — a client asking for
    // 100_000 episodes shouldn't get a response no LLM can read.
    let requested = min(Self.maxEpisodeLimit, max(1, limit ?? 50))
    let end = min(episodes.count, start + requested)
    guard start < end else { return [] }
    var stubs: [MCPEpisodeStubDTO] = []
    for episode in episodes[start..<end] {
      stubs.append(await mapEpisodeStub(episode, podcastTitle: podcastTitle))
    }
    return stubs
  }

  // MARK: get_episode

  func getEpisode(podcastTitle: String, episodeTitle: String) async throws -> MCPEpisodeDetailDTO {
    let model = try fetchPodcast(title: podcastTitle)
    guard let episode = model.podcastInfo.episodes.first(where: { $0.title == episodeTitle })
    else { throw MCPGatewayError.episodeNotFound(podcast: podcastTitle, episode: episodeTitle) }
    let download = try fetchDownload(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
    let hasTranscriptFlag = hasTranscript(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
    return MCPEpisodeDetailDTO(
      title: episode.title,
      podcastTitle: podcastTitle,
      pubDate: episode.pubDate,
      durationSeconds: episode.duration,
      description: episode.podcastEpisodeDescription,
      audioURL: episode.audioURL,
      imageURL: episode.imageURL ?? model.podcastInfo.imageURL,
      guid: episode.guid,
      hasTranscript: hasTranscriptFlag,
      hasAIAnalysis: hasAIAnalysis(podcastTitle: podcastTitle, episodeTitle: episodeTitle),
      hasLocalAudio: download?.hasLocalAudioFile ?? false,
      localAudioPath: download?.hasLocalAudioFile == true ? download?.localAudioPath : nil,
      isCompleted: download?.isCompleted ?? false,
      lastPlaybackPosition: download?.lastPlaybackPosition ?? 0,
      playCount: download?.playCount ?? 0,
      isStarred: download?.isStarred ?? false
    )
  }

  // MARK: get_transcript

  func getTranscript(
    podcastTitle: String,
    episodeTitle: String,
    format: String
  ) async throws -> MCPTranscriptDTO {
    guard let srt = TranscriptStore.shared.loadSRT(episodeTitle: episodeTitle, podcastTitle: podcastTitle) else {
      throw MCPGatewayError.transcriptNotFound(podcast: podcastTitle, episode: episodeTitle)
    }
    let normalized = format.lowercased() == "srt" ? "srt" : "plain"
    let content = normalized == "srt" ? srt : Self.srtToPlain(srt)
    return MCPTranscriptDTO(
      format: normalized,
      content: content,
      podcastTitle: podcastTitle,
      episodeTitle: episodeTitle
    )
  }

  // MARK: get_ai_analysis

  func getAIAnalysis(podcastTitle: String, episodeTitle: String) throws -> MCPAIAnalysisDTO {
    let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate {
        $0.episodeTitle == episodeTitle && $0.podcastTitle == podcastTitle
      }
    )
    guard let analysis = try modelContext.fetch(descriptor).first, analysis.hasAnalysis else {
      throw MCPGatewayError.aiAnalysisNotFound(podcast: podcastTitle, episode: episodeTitle)
    }
    return MCPAIAnalysisDTO(
      podcastTitle: analysis.podcastTitle,
      episodeTitle: analysis.episodeTitle,
      provider: analysis.provider,
      model: analysis.model,
      generatedAt: analysis.generatedAt,
      analysisJSON: analysis.analysisJSON
    )
  }

  // MARK: search_transcripts

  func searchTranscripts(query: String, limit: Int?) async throws -> [MCPSearchHitDTO] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }

    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.isSubscribed == true }
    )
    let podcasts = try modelContext.fetch(descriptor)

    let vm = TranscriptSearchViewModel()
    await vm.performSearch(query: trimmed, podcasts: podcasts)
    let cap = min(Self.maxSearchHits, max(1, limit ?? 20))

    var hits: [MCPSearchHitDTO] = []
    for result in vm.results.prefix(cap) {
      for snippet in result.snippets.prefix(3) {
        hits.append(
          MCPSearchHitDTO(
            podcastTitle: result.podcastTitle,
            episodeTitle: result.episode.title,
            snippet: snippet.text,
            timestampSeconds: snippet.timestamp,
            matchCount: result.matchCount
          )
        )
        if hits.count >= cap { return hits }
      }
    }
    return hits
  }

  // MARK: generate_transcript

  func generateTranscript(
    podcastTitle: String,
    episodeTitle: String,
    engineRaw: String?,
    language: String?
  ) async throws -> MCPTranscriptJobDTO {
    let jobKey = "\(podcastTitle)\u{1F}\(episodeTitle)"

    let manager = TranscriptManager.shared

    // Already in-flight or recently completed → return current status without re-queueing.
    if let existing = manager.activeJobs[jobKey] {
      return Self.jobDTO(from: existing.status, jobKey: jobKey, message: "Job already exists.")
    }

    // Already has a transcript on disk → no-op.
    if hasTranscript(podcastTitle: podcastTitle, episodeTitle: episodeTitle) {
      return MCPTranscriptJobDTO(
        status: "completed",
        progress: 1.0,
        message: "Transcript already exists. Use get_transcript to read it.",
        jobKey: jobKey,
        error: nil
      )
    }

    // Resolve engine selection.
    let engine: TranscriptEngine?
    if let raw = engineRaw?.lowercased(), !raw.isEmpty {
      engine = TranscriptEngine(rawValue: raw)
      guard engine != nil else {
        throw MCPGatewayError.invalidArgument("Unknown engine '\(raw)'. Valid: appleSpeech, whisper, yapServer.")
      }
    } else {
      engine = nil  // Use global default.
    }

    // Look up audio path / URL.
    let model = try fetchPodcast(title: podcastTitle)
    guard let episode = model.podcastInfo.episodes.first(where: { $0.title == episodeTitle })
    else { throw MCPGatewayError.episodeNotFound(podcast: podcastTitle, episode: episodeTitle) }

    let download = try fetchDownload(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
    let localPath = download?.hasLocalAudioFile == true ? (download?.localAudioPath ?? "") : ""
    let remoteURL = episode.audioURL ?? download?.audioURL

    // Validate inputs by engine.
    let effectiveEngine = engine ?? Self.resolveDefaultEngine()
    let supportsRemoteAudio = effectiveEngine == .yapServer
    if localPath.isEmpty && !supportsRemoteAudio {
      throw MCPGatewayError.audioUnavailable(
        podcast: podcastTitle,
        episode: episodeTitle,
        reason: "No local audio. Download the episode first, or use engine 'yapServer' if a YAP server is configured."
      )
    }
    if localPath.isEmpty && (remoteURL?.isEmpty ?? true) {
      throw MCPGatewayError.audioUnavailable(
        podcast: podcastTitle,
        episode: episodeTitle,
        reason: "No audio URL available for this episode."
      )
    }

    manager.queueTranscript(
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle,
      audioPath: localPath,
      audioRemoteURL: remoteURL,
      language: language ?? model.podcastInfo.language,
      engine: engine
    )

    let queued = manager.activeJobs[jobKey]?.status ?? .queued
    return Self.jobDTO(
      from: queued,
      jobKey: jobKey,
      message: "Transcript job queued."
    )
  }

  // MARK: - Helpers

  private func fetchPodcast(title: String) throws -> PodcastInfoModel {
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == title }
    )
    guard let model = try modelContext.fetch(descriptor).first else {
      throw MCPGatewayError.podcastNotFound(title)
    }
    return model
  }

  private func fetchDownload(podcastTitle: String, episodeTitle: String) throws -> EpisodeDownloadModel? {
    let id = "\(podcastTitle)\u{1F}\(episodeTitle)"
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == id }
    )
    return try modelContext.fetch(descriptor).first
  }

  private func mapEpisodeStub(_ episode: PodcastEpisodeInfo, podcastTitle: String) async -> MCPEpisodeStubDTO {
    let download = try? fetchDownload(podcastTitle: podcastTitle, episodeTitle: episode.title)
    let hasTranscriptFlag = hasTranscript(podcastTitle: podcastTitle, episodeTitle: episode.title)
    return MCPEpisodeStubDTO(
      title: episode.title,
      pubDate: episode.pubDate,
      durationSeconds: episode.duration,
      audioURL: episode.audioURL,
      imageURL: episode.imageURL,
      hasTranscript: hasTranscriptFlag,
      hasAIAnalysis: hasAIAnalysis(podcastTitle: podcastTitle, episodeTitle: episode.title),
      isCompleted: download?.isCompleted ?? false,
      lastPlaybackPosition: download?.lastPlaybackPosition ?? 0,
      hasLocalAudio: download?.hasLocalAudioFile ?? false
    )
  }

  private func hasTranscript(podcastTitle: String, episodeTitle: String) -> Bool {
    TranscriptStore.shared.exists(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
  }

  private func hasAIAnalysis(podcastTitle: String, episodeTitle: String) -> Bool {
    let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate {
        $0.episodeTitle == episodeTitle && $0.podcastTitle == podcastTitle
      }
    )
    return (try? modelContext.fetch(descriptor).first?.hasAnalysis) ?? false
  }

  private static func jobDTO(
    from status: TranscriptJobStatus,
    jobKey: String,
    message: String
  ) -> MCPTranscriptJobDTO {
    switch status {
    case .queued:
      return MCPTranscriptJobDTO(status: "queued", progress: nil, message: message, jobKey: jobKey, error: nil)
    case .downloadingModel(let progress):
      return MCPTranscriptJobDTO(
        status: "downloading_model", progress: progress,
        message: "Downloading transcription model.", jobKey: jobKey, error: nil)
    case .transcribing(let progress):
      return MCPTranscriptJobDTO(
        status: "transcribing", progress: progress,
        message: "Transcribing audio.", jobKey: jobKey, error: nil)
    case .completed:
      return MCPTranscriptJobDTO(
        status: "completed", progress: 1.0,
        message: "Transcript completed.", jobKey: jobKey, error: nil)
    case .failed(let err):
      return MCPTranscriptJobDTO(
        status: "failed", progress: nil,
        message: "Transcription failed.", jobKey: jobKey, error: err)
    }
  }

  private static func resolveDefaultEngine() -> TranscriptEngine {
    if let raw = UserDefaults.standard.string(forKey: "transcriptEngine"),
       let engine = TranscriptEngine(rawValue: raw) {
      return engine
    }
    return .appleSpeech
  }

  /// Strip SRT timing/index lines, return only the dialog text.
  static func srtToPlain(_ srt: String) -> String {
    let lines = srt.components(separatedBy: .newlines)
    var out: [String] = []
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty { continue }
      if Int(trimmed) != nil { continue }  // segment index
      if trimmed.contains(" --> ") { continue }  // timing line
      out.append(trimmed)
    }
    return out.joined(separator: "\n")
  }
}

#endif
