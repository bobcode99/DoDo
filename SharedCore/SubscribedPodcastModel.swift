//
//  SubscribedPodcastModel.swift
//  PodcastAnalyzer
//
//  SwiftData model mirrored to the user's private CloudKit database so a
//  podcast subscribed on one device shows up on another signed into the
//  same Apple ID — without syncing the full episode blob (PodcastInfoModel
//  carries the whole RSS feed snapshot, which risks CloudKit's 1MB-per-record
//  cap for large back-catalogs). Deliberately minimal: just enough to
//  re-subscribe (fetch the feed fresh) on the receiving device.
//

import Foundation
import SwiftData

@Model
final class SubscribedPodcastModel {
  #Index<SubscribedPodcastModel>([\.rssUrl])

  /// Matching key — same `PodcastInfoModel.rssUrl` used for local dedup.
  var rssUrl: String = ""
  var title: String = ""
  var dateSubscribed: Date = Date()

  /// Artwork URL, carried so the watch can draw its shows list without
  /// fetching every feed first. A URL string, not image data — CloudKit's
  /// per-record cap is the reason this model stays small.
  var imageURL: String = ""

  init(rssUrl: String, title: String, imageURL: String = "", dateSubscribed: Date = Date()) {
    self.rssUrl = rssUrl
    self.title = title
    self.imageURL = imageURL
    self.dateSubscribed = dateSubscribed
  }
}
