//
//  AIAnalysisUIState.swift
//  PodcastAnalyzer
//
//  Shared transient UI state for EpisodeAIAnalysisView and its tab subviews.
//

import Foundation

@Observable
final class AIAnalysisUIState {
  var selectedTab: CloudAnalysisTab = .analysis
  var questionInput: String = ""
  var showSettingsSheet = false
  var formatHintDraft: String = ""
  var formatHintSaved: Bool = false
  var isRegenerating: Bool = false
  var promptCopied: Bool = false
  var showPromptPreview: Bool = false
}
