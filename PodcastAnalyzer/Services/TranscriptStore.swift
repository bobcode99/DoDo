//
//  TranscriptStore.swift
//  PodcastAnalyzer
//
//  MainActor owner of `EpisodeTranscriptModel` — the SwiftData replacement for
//  FileStorageManager's caption/word-timing/translated-caption file API.
//  Lives on MainActor (not inside FileStorageManager's background actor)
//  because it shares `container.mainContext` with every other SwiftData
//  writer in the app (PlaybackStateCoordinator, TranscriptCoordinator, etc.) —
//  a private context here would risk the same cross-context staleness a
//  separate ModelContext caused for PlaybackProgressSyncCoordinator earlier.
//

import Foundation
import SwiftData
import OSLog

@MainActor
final class TranscriptStore {
  static let shared = TranscriptStore()

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptStore")
  private var context: ModelContext?

  // Internal (not private) so tests can create an isolated instance against
  // an in-memory container instead of sharing app-wide singleton state.
  init() {}

  func setModelContainer(_ container: ModelContainer) {
    guard context == nil else { return }
    context = container.mainContext
  }

  private func makeId(episodeTitle: String, podcastTitle: String) -> String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
  }

  private func fetch(episodeTitle: String, podcastTitle: String) -> EpisodeTranscriptModel? {
    guard let context else { return nil }
    let id = makeId(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
    let descriptor = FetchDescriptor<EpisodeTranscriptModel>(predicate: #Predicate { $0.episodeId == id })
    return try? context.fetch(descriptor).first
  }

  // MARK: - Existence / metadata

  func exists(episodeTitle: String, podcastTitle: String) -> Bool {
    fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle) != nil
  }

  func generatedAt(episodeTitle: String, podcastTitle: String) -> Date? {
    fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle)?.generatedAt
  }

  func source(episodeTitle: String, podcastTitle: String) -> String {
    fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle)?.source ?? ""
  }

  // MARK: - Base transcript

  /// Parses raw SRT text once and stores the structured segments — every
  /// producer (Apple Speech, WhisperKit, YAP server, RSS download) hands us
  /// plain SRT text regardless of engine, so this is the single ingestion
  /// point. Clears any stale word-timing/translation data tied to the old
  /// segment boundaries.
  @discardableResult
  func saveTranscript(
    srtContent: String, episodeTitle: String, podcastTitle: String, source: String
  ) throws -> [TranscriptSegment] {
    guard let context else { return [] }
    let segments = SRTParser.parseSegments(from: srtContent)

    let model: EpisodeTranscriptModel
    if let existing = fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle) {
      model = existing
    } else {
      model = EpisodeTranscriptModel(episodeId: makeId(episodeTitle: episodeTitle, podcastTitle: podcastTitle))
      context.insert(model)
    }

    model.segmentsJSON = Self.encodeSegments(segments)
    model.plainText = segments.map(\.text).joined(separator: " ")
    model.source = source
    model.translationsJSON = nil
    model.wordTimingsJSON = nil
    model.generatedAt = Date()

    do {
      try context.save()
    } catch {
      logger.error("Failed to save transcript: \(error.localizedDescription, privacy: .public)")
      throw error
    }
    return segments
  }

  /// Plain transcript text (no timestamps) — powers search and Shortcuts.
  func plainText(episodeTitle: String, podcastTitle: String) -> String? {
    fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle)?.plainText
  }

  func loadSegments(episodeTitle: String, podcastTitle: String) -> [TranscriptSegment]? {
    guard let model = fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle) else { return nil }
    var segments = Self.decodeSegments(model.segmentsJSON)
    if let wordTimingsJSON = model.wordTimingsJSON,
       let data = wordTimingsJSON.data(using: .utf8),
       let timingsData = try? JSONDecoder().decode(TranscriptData.self, from: data) {
      segments = Self.mergingWordTimings(timingsData, into: segments)
    }
    // Fuse the diarization timeline onto each line by max overlap. Derived at
    // read time so re-diarizing never rewrites segmentsJSON.
    let turns = Self.decodeTurns(model.speakerTurnsJSON)
    if !turns.isEmpty {
      for index in segments.indices {
        segments[index].speakerId = SpeakerDiarization.speaker(
          forStart: segments[index].startTime, end: segments[index].endTime, turns: turns)
      }
    }
    return segments
  }

  // MARK: - Diarization (speaker layer)

  /// Stores a diarization timeline for an episode and seeds a default unnamed
  /// roster. Independent of the transcript text — safe to call before or after
  /// transcription exists.
  func saveDiarization(
    turns: [SpeakerTurn], episodeTitle: String, podcastTitle: String
  ) throws {
    guard let context else { return }
    let model: EpisodeTranscriptModel
    if let existing = fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle) {
      model = existing
    } else {
      model = EpisodeTranscriptModel(episodeId: makeId(episodeTitle: episodeTitle, podcastTitle: podcastTitle))
      context.insert(model)
    }
    model.speakerTurnsJSON = Self.encodeTurns(turns)
    model.speakerRosterJSON = Self.encodeRoster(SpeakerDiarization.defaultRoster(from: turns))
    do {
      try context.save()
    } catch {
      logger.error("Failed to save diarization: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  func loadSpeakerTurns(episodeTitle: String, podcastTitle: String) -> [SpeakerTurn] {
    Self.decodeTurns(fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle)?.speakerTurnsJSON)
  }

  func loadRoster(episodeTitle: String, podcastTitle: String) -> [SpeakerLabel] {
    Self.decodeRoster(fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle)?.speakerRosterJSON)
  }

  func hasDiarization(episodeTitle: String, podcastTitle: String) -> Bool {
    !loadSpeakerTurns(episodeTitle: episodeTitle, podcastTitle: podcastTitle).isEmpty
  }

  /// Reconstitutes standard SRT text — needed where an actual SRT string is
  /// required rather than structured segments (e.g. the MCP "srt" format).
  func loadSRT(episodeTitle: String, podcastTitle: String) -> String? {
    guard let segments = loadSegments(episodeTitle: episodeTitle, podcastTitle: podcastTitle) else { return nil }
    return SRTParser.serialize(segments: segments)
  }

  // MARK: - Translations

  /// Stores translated strings aligned by segment index (mirrors the old
  /// bilingual-SRT index-based merge) under `targetLanguage`, alongside any
  /// other languages already translated for this episode.
  func saveTranslation(
    _ segments: [TranscriptSegment], targetLanguage: String, episodeTitle: String, podcastTitle: String
  ) throws {
    guard let context, let model = fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle) else { return }
    var dict = Self.decodeTranslations(model.translationsJSON)
    dict[targetLanguage] = segments.map { $0.translatedText ?? "" }
    model.translationsJSON = Self.encodeTranslations(dict)
    do {
      try context.save()
    } catch {
      logger.error("Failed to save translation: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  /// Loads the base segments with `targetLanguage`'s translated text merged
  /// in, or nil if that language hasn't been translated for this episode.
  func loadTranslation(
    targetLanguage: String, episodeTitle: String, podcastTitle: String
  ) -> [TranscriptSegment]? {
    guard let model = fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle),
          let translated = Self.decodeTranslations(model.translationsJSON)[targetLanguage]
    else { return nil }

    var segments = loadSegments(episodeTitle: episodeTitle, podcastTitle: podcastTitle) ?? []
    for (index, text) in translated.enumerated() where index < segments.count && !text.isEmpty {
      segments[index].translatedText = text
    }
    return segments
  }

  func hasTranslation(targetLanguage: String, episodeTitle: String, podcastTitle: String) -> Bool {
    guard let model = fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle) else { return false }
    return Self.decodeTranslations(model.translationsJSON)[targetLanguage] != nil
  }

  func availableTranslationLanguages(episodeTitle: String, podcastTitle: String) -> Set<String> {
    guard let model = fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle) else { return [] }
    return Set(Self.decodeTranslations(model.translationsJSON).keys)
  }

  // MARK: - Sharing

  /// Portable transcript file (".dodotranscript") exchanged between DoDo
  /// installs. Carries the stored JSON columns verbatim — no re-encoding —
  /// so import reproduces the exact transcript (word timings + translations
  /// included) without regenerating.
  struct TranscriptExportFile: Codable {
    var version: Int = 1
    var podcastTitle: String
    var episodeTitle: String
    var source: String
    var segmentsJSON: String
    var wordTimingsJSON: String?
    var translationsJSON: String?
    // Optional so v1 files (no speaker layer) still decode as nil.
    var speakerTurnsJSON: String?
    var speakerRosterJSON: String?
    var generatedAt: Date
  }

  static let shareFileExtension = "dodotranscript"

  /// Writes a temp ".dodotranscript" file for the share sheet. Nil if the
  /// episode has no transcript.
  func exportShareFile(episodeTitle: String, podcastTitle: String) -> URL? {
    guard let model = fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle) else { return nil }
    let payload = TranscriptExportFile(
      podcastTitle: podcastTitle,
      episodeTitle: episodeTitle,
      source: model.source,
      segmentsJSON: model.segmentsJSON,
      wordTimingsJSON: model.wordTimingsJSON,
      translationsJSON: model.translationsJSON,
      speakerTurnsJSON: model.speakerTurnsJSON,
      speakerRosterJSON: model.speakerRosterJSON,
      generatedAt: model.generatedAt
    )
    guard let data = try? JSONEncoder().encode(payload) else { return nil }
    return writeTempFile(data: data, episodeTitle: episodeTitle, ext: Self.shareFileExtension)
  }

  /// Writes a temp ".srt" file for sharing to non-DoDo apps (WhatsApp, mail…).
  func exportSRTFile(episodeTitle: String, podcastTitle: String) -> URL? {
    guard let srt = loadSRT(episodeTitle: episodeTitle, podcastTitle: podcastTitle),
          let data = srt.data(using: .utf8) else { return nil }
    return writeTempFile(data: data, episodeTitle: episodeTitle, ext: "srt")
  }

  /// Imports a ".dodotranscript" file received from another install, upserting
  /// the row keyed by the sender's podcast/episode titles (same composite key
  /// both apps derive from the RSS feed). Returns the episode it landed on.
  @discardableResult
  func importShareFile(data: Data) throws -> (podcastTitle: String, episodeTitle: String) {
    let payload = try JSONDecoder().decode(TranscriptExportFile.self, from: data)
    guard let context else { throw CocoaError(.fileReadUnknown) }

    let model: EpisodeTranscriptModel
    if let existing = fetch(episodeTitle: payload.episodeTitle, podcastTitle: payload.podcastTitle) {
      model = existing
    } else {
      model = EpisodeTranscriptModel(
        episodeId: makeId(episodeTitle: payload.episodeTitle, podcastTitle: payload.podcastTitle))
      context.insert(model)
    }
    model.segmentsJSON = payload.segmentsJSON
    model.wordTimingsJSON = payload.wordTimingsJSON
    model.translationsJSON = payload.translationsJSON
    model.speakerTurnsJSON = payload.speakerTurnsJSON
    model.speakerRosterJSON = payload.speakerRosterJSON
    model.source = payload.source
    model.generatedAt = payload.generatedAt
    model.plainText = Self.decodeSegments(payload.segmentsJSON).map(\.text).joined(separator: " ")
    try context.save()
    return (payload.podcastTitle, payload.episodeTitle)
  }

  private func writeTempFile(data: Data, episodeTitle: String, ext: String) -> URL? {
    let safeName = episodeTitle
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: "_")
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(safeName.isEmpty ? "transcript" : safeName)
      .appendingPathExtension(ext)
    do {
      try data.write(to: url, options: .atomic)
      return url
    } catch {
      logger.error("Failed to write share file: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  // MARK: - Delete

  func delete(episodeTitle: String, podcastTitle: String) throws {
    guard let context, let model = fetch(episodeTitle: episodeTitle, podcastTitle: podcastTitle) else { return }
    context.delete(model)
    try context.save()
  }

  func deleteAll() throws {
    guard let context else { return }
    try context.delete(model: EpisodeTranscriptModel.self)
    try context.save()
  }

  /// Approximate on-disk footprint, for the Settings "Transcripts" size row —
  /// replaces summing file sizes under the old Captions folder.
  func totalStorageSize() -> Int64 {
    guard let context else { return 0 }
    let all = (try? context.fetch(FetchDescriptor<EpisodeTranscriptModel>())) ?? []
    return all.reduce(Int64(0)) { total, model in
      total + Int64(model.segmentsJSON.utf8.count)
        + Int64((model.wordTimingsJSON ?? "").utf8.count)
        + Int64((model.translationsJSON ?? "").utf8.count)
    }
  }

  // MARK: - Encoding helpers

  private static func encodeSegments(_ segments: [TranscriptSegment]) -> String {
    guard let data = try? JSONEncoder().encode(segments),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
  }

  private static func decodeSegments(_ json: String) -> [TranscriptSegment] {
    guard let data = json.data(using: .utf8),
          let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data) else { return [] }
    return segments
  }

  private static func encodeTranslations(_ dict: [String: [String]]) -> String? {
    guard let data = try? JSONEncoder().encode(dict),
          let json = String(data: data, encoding: .utf8) else { return nil }
    return json
  }

  private static func decodeTranslations(_ json: String?) -> [String: [String]] {
    guard let json, let data = json.data(using: .utf8),
          let dict = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
    return dict
  }

  private static func encodeTurns(_ turns: [SpeakerTurn]) -> String? {
    guard let data = try? JSONEncoder().encode(turns) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func decodeTurns(_ json: String?) -> [SpeakerTurn] {
    guard let json, let data = json.data(using: .utf8),
          let turns = try? JSONDecoder().decode([SpeakerTurn].self, from: data) else { return [] }
    return turns
  }

  private static func encodeRoster(_ roster: [SpeakerLabel]) -> String? {
    guard let data = try? JSONEncoder().encode(roster) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func decodeRoster(_ json: String?) -> [SpeakerLabel] {
    guard let json, let data = json.data(using: .utf8),
          let roster = try? JSONDecoder().decode([SpeakerLabel].self, from: data) else { return [] }
    return roster
  }

  private static func mergingWordTimings(
    _ data: TranscriptData, into segments: [TranscriptSegment]
  ) -> [TranscriptSegment] {
    var result = segments
    for index in result.indices {
      let segment = result[index]
      if let match = data.segments.first(where: { $0.id == segment.id })
        ?? data.segments.first(where: {
          abs($0.startTime - segment.startTime) < 0.5 && abs($0.endTime - segment.endTime) < 0.5
        }) {
        result[index].wordTimings = match.wordTimings.map {
          WordTiming(word: $0.word, startTime: $0.startTime, endTime: $0.endTime)
        }
      }
    }
    return result
  }
}
