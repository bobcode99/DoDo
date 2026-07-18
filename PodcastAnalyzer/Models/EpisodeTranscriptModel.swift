//
//  EpisodeTranscriptModel.swift
//  PodcastAnalyzer
//
//  SwiftData model for transcript storage — replaces the old Documents/Captions/
//  {podcastTitle}/ file tree (.srt + _wordtimings.json + per-language _{lang}.srt).
//  One atomic row per episode instead of up to 5 loose files: no user-visible
//  folder, no dangling paths, and — regardless of which engine produced it
//  (Apple Speech, WhisperKit, YAP server) or whether it came from the RSS feed —
//  the raw SRT text is parsed into segments exactly once, at save time, instead
//  of being re-parsed from a string on every transcript view open.
//

import Foundation
import SwiftData

@Model
final class EpisodeTranscriptModel {
  #Index<EpisodeTranscriptModel>([\.episodeId])

  /// Matches `EpisodeDownloadModel.id` ("podcastTitle\u{1F}episodeTitle").
  var episodeId: String = ""

  /// "rss" | "local" | "yapServer" — same provenance values as the old
  /// `EpisodeDownloadModel.transcriptSource`.
  var source: String = ""

  /// JSON-encoded `[TranscriptSegment]` — the parsed transcript.
  var segmentsJSON: String = ""

  /// JSON-encoded `TranscriptData` (word-level timings), when the engine
  /// provides them. No current engine populates this, but the read path
  /// (segment highlighting) already supports merging it in when present.
  var wordTimingsJSON: String?

  /// JSON-encoded `[String: [String]]` — target language code to translated
  /// strings, aligned by segment index (mirrors the old bilingual-SRT
  /// index-based merge). Cleared whenever the base transcript is regenerated,
  /// since a new transcription can shift segment boundaries and translations
  /// keyed by the old indices would silently misalign.
  var translationsJSON: String?

  /// Denormalized full-text mirror (segments joined), enabling future
  /// `#Predicate` full-text search without decoding `segmentsJSON`.
  var plainText: String = ""

  var generatedAt: Date = Date()

  init(episodeId: String) {
    self.episodeId = episodeId
  }
}
