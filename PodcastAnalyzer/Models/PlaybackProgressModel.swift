//
//  PlaybackProgressModel.swift
//  PodcastAnalyzer
//
//  SwiftData model mirrored to the user's private CloudKit database so
//  playback progress follows them across iPhone/iPad/Mac on the same Apple ID.
//

import Foundation
import SwiftData

/// Kept deliberately separate from `EpisodeDownloadModel`: that model also
/// carries device-local state (`localAudioPath`, `captionPath`) that must
/// never sync — a synced file path from one device is meaningless on
/// another. This model mirrors only the small, sync-safe slice of playback
/// state. CloudKit mirroring requires every attribute to be optional or have
/// a default, forbids `#Unique`, and forbids relationships — this type
/// satisfies all three.
@Model
final class PlaybackProgressModel {
  #Index<PlaybackProgressModel>([\.id])

  /// Matches `EpisodeDownloadModel.id` ("podcastTitle\u{1F}episodeTitle") so the
  /// two rows can be joined without a relationship (CloudKit-synced models
  /// can't have relationships to non-synced models).
  var id: String = ""

  var lastPlaybackPosition: TimeInterval = 0
  var duration: TimeInterval = 0
  var isCompleted: Bool = false
  var playCount: Int = 0
  var lastPlayedDate: Date?

  /// Stamped on every local write; used to resolve which of two devices'
  /// updates is newer when applying an incoming CloudKit change.
  var updatedAt: Date = Date()

  /// Name of the device that produced this row (e.g. "Bob's iPhone").
  /// Diagnostic only — never used for merge decisions.
  var deviceName: String = ""

  init(
    id: String,
    lastPlaybackPosition: TimeInterval = 0,
    duration: TimeInterval = 0,
    isCompleted: Bool = false,
    playCount: Int = 0,
    lastPlayedDate: Date? = nil,
    updatedAt: Date = Date(),
    deviceName: String = ""
  ) {
    self.id = id
    self.lastPlaybackPosition = lastPlaybackPosition
    self.duration = duration
    self.isCompleted = isCompleted
    self.playCount = playCount
    self.lastPlayedDate = lastPlayedDate
    self.updatedAt = updatedAt
    self.deviceName = deviceName
  }
}
