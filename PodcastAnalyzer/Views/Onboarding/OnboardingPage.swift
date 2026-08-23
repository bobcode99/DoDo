//
//  OnboardingPage.swift
//  PodcastAnalyzer
//
//  Pages of the first-launch guide, in order.
//

#if os(iOS)
import Foundation

enum OnboardingPage: Hashable, CaseIterable {
  case welcome
  case region
  case permissions
  case transcription
  /// Either "Bring Your Podcasts" or the iCloud restore, depending on whether
  /// this Apple ID already has subscriptions synced.
  case finish
}

#endif
