//
//  AIAnalysisCoordinator.swift
//  PodcastAnalyzer
//
//  Owns the AI lifecycle for a single episode: on-device quick tags (Apple
//  Foundation Models), cloud BYOK analysis + Q&A streaming, and SwiftData
//  persistence of both result types.
//
//  Extracted from EpisodeDetailViewModel so views observing AI state get
//  scoped @Observable invalidation — a quick-tags state change no longer
//  re-renders views that only read cloud streaming text, and vice versa.
//

import Foundation
import Observation
import OSLog
import SwiftData

#if os(iOS)
import UIKit
#endif

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "AIAnalysisCoordinator")

/// What an owner needs to expose so the coordinator can read transcript state
/// on demand without holding a strong back-reference (and without forcing the
/// owner to thread closures through init).
@MainActor
protocol AIAnalysisTranscriptSource: AnyObject {
  var transcriptText: String { get }
  var transcriptSegments: [TranscriptSegment] { get }
  var hasTranscript: Bool { get }
}

@MainActor @Observable
final class AIAnalysisCoordinator {

  // MARK: - On-Device State

  var onDeviceAIAvailability: FoundationModelsAvailability = .unavailable(reason: "Checking...")
  var quickTagsState: AnalysisState = .idle
  var quickTagsCache: CachedQuickTags = CachedQuickTags()

  // MARK: - Cloud State

  var cloudQuestionState: AnalysisState = .idle
  var cloudAnalysisCache: CachedCloudAnalysis = CachedCloudAnalysis()

  @ObservationIgnored
  private var _localCloudAnalysisState: AnalysisState = .idle

  /// Reads the `CloudAnalysisJobCoordinator` snapshot first so a re-opened
  /// detail view picks up the in-flight stream mid-flight; falls back to the
  /// local backing for validation errors and idle/cleared states.
  var cloudAnalysisState: AnalysisState {
    get {
      if let snap = CloudAnalysisJobCoordinator.shared.snapshot(for: cloudJobKey) {
        return snap.state
      }
      return _localCloudAnalysisState
    }
    set { _localCloudAnalysisState = newValue }
  }

  var streamingText: String {
    CloudAnalysisJobCoordinator.shared.snapshot(for: cloudJobKey)?.streamingText ?? ""
  }

  var isStreaming: Bool {
    CloudAnalysisJobCoordinator.shared.snapshot(for: cloudJobKey)?.isStreaming ?? false
  }

  var currentStreamingType: CloudAnalysisType? {
    CloudAnalysisJobCoordinator.shared.snapshot(for: cloudJobKey)?.currentType
  }

  /// Start time of the in-flight job, for the elapsed-time readout.
  var analysisStartedAt: Date? {
    CloudAnalysisJobCoordinator.shared.snapshot(for: cloudJobKey)?.startedAt
  }

  var hasAIAnalysis: Bool {
    cloudAnalysisCache.analysis != nil || !cloudAnalysisCache.questionAnswers.isEmpty
  }

  // MARK: - Inputs (set by owner)

  @ObservationIgnored let episode: PodcastEpisodeInfo
  @ObservationIgnored let podcastTitle: String
  @ObservationIgnored var podcastLanguage: String
  @ObservationIgnored private(set) var modelContext: ModelContext?

  /// Weak owner reference for on-demand transcript reads — avoids a back-cycle
  /// to the view model without forcing escaping closures through init.
  @ObservationIgnored private weak var transcriptSource: AIAnalysisTranscriptSource?

  // MARK: - Task Ownership

  @ObservationIgnored private var onDeviceAICheckTask: Task<Void, Never>?
  @ObservationIgnored private var quickTagsTask: Task<Void, Never>?
  @ObservationIgnored private var briefSummaryTask: Task<Void, Never>?
  @ObservationIgnored private var cloudQuestionTask: Task<Void, Never>?
  @ObservationIgnored private var cloudJobObserverTask: Task<Void, Never>?

  @ObservationIgnored private var aiAnalysisModel: EpisodeAIAnalysis?

  private var cloudJobKey: String { episode.audioURL ?? "" }

  // MARK: - Init

  init(
    episode: PodcastEpisodeInfo,
    podcastTitle: String,
    podcastLanguage: String
  ) {
    self.episode = episode
    self.podcastTitle = podcastTitle
    self.podcastLanguage = podcastLanguage
  }

  // MARK: - Setup

  /// Attach the owner *after* it is fully initialized. Holding the source as
  /// `weak` keeps the coordinator-↔-owner cycle GC-free.
  func attach(transcriptSource: AIAnalysisTranscriptSource) {
    self.transcriptSource = transcriptSource
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
  }

  func setPodcastLanguage(_ language: String) {
    self.podcastLanguage = language
  }

  /// Listen for `.cloudAnalysisJobFinished` so a re-opened detail view picks
  /// up the freshly-saved SwiftData row from a job that completed while the
  /// view was off-screen.
  func observeCloudAnalysisJobFinished() {
    cloudJobObserverTask?.cancel()
    cloudJobObserverTask = Task { [weak self] in
      guard let self else { return }
      let myAudioURL = self.cloudJobKey
      let stream = NotificationCenter.default.notifications(named: .cloudAnalysisJobFinished)
      for await note in stream {
        if Task.isCancelled { break }
        guard
          let finishedURL = note.userInfo?["audioURL"] as? String,
          finishedURL == myAudioURL
        else { continue }
        self.loadAIAnalysisFromSwiftData()
      }
    }
  }

  // MARK: - On-Device AI (Quick Tags from Metadata)

  /// Check if on-device Foundation Models are available
  func checkOnDeviceAIAvailability() {
    if #available(iOS 26.0, macOS 26.0, *) {
      onDeviceAICheckTask?.cancel()
      onDeviceAICheckTask = Task { [weak self] in
        let service = AppleFoundationModelsService()
        let availability = await service.checkAvailability()
        guard !Task.isCancelled, let self else { return }
        self.onDeviceAIAvailability = availability
      }
    } else {
      onDeviceAIAvailability = .unavailable(reason: "Requires iOS 26 or later")
    }
  }

  /// Generate quick tags from episode metadata (on-device, fast)
  func generateQuickTags() {
    guard #available(iOS 26.0, macOS 26.0, *) else {
      quickTagsState = .error("Requires iOS 26 or later")
      return
    }

    guard onDeviceAIAvailability.isAvailable else {
      quickTagsState = .error(onDeviceAIAvailability.message ?? "On-device AI unavailable")
      return
    }

    quickTagsTask?.cancel()
    quickTagsTask = Task { [weak self] in
      guard let self else { return }
      do {
        self.quickTagsState = .analyzing(progress: 0, message: "Generating tags...")

        let service = AppleFoundationModelsService()
        let tags = try await service.generateQuickTags(
          title: self.episode.title,
          description: self.episode.podcastEpisodeDescription ?? "",
          podcastTitle: self.podcastTitle,
          duration: self.episode.duration.map { TimeInterval($0) },
          releaseDate: self.episode.pubDate,
          progressCallback: { [weak self] message, progress in
            Task { @MainActor in
              self?.quickTagsState = .analyzing(progress: progress, message: message)
            }
          }
        )

        guard !Task.isCancelled else { return }
        self.quickTagsCache.tags = tags
        self.quickTagsCache.generatedAt = Date()
        self.quickTagsState = .completed

        self.saveQuickTagsToSwiftData(tags: tags)

        logger.info("Quick tags generated successfully")
      } catch {
        self.quickTagsState = .error("Failed: \(error.localizedDescription)")
        logger.error("Quick tags generation failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Generate brief summary from metadata (on-device, fast)
  func generateBriefSummary() {
    guard #available(iOS 26.0, macOS 26.0, *) else {
      quickTagsState = .error("Requires iOS 26 or later")
      return
    }

    guard onDeviceAIAvailability.isAvailable else {
      quickTagsState = .error(onDeviceAIAvailability.message ?? "On-device AI unavailable")
      return
    }

    briefSummaryTask?.cancel()
    briefSummaryTask = Task { [weak self] in
      guard let self else { return }
      do {
        self.quickTagsState = .analyzing(progress: 0, message: "Creating summary...")

        let service = AppleFoundationModelsService()
        let summary = try await service.generateBriefSummary(
          title: self.episode.title,
          description: self.episode.podcastEpisodeDescription ?? "",
          progressCallback: { [weak self] message, progress in
            Task { @MainActor in
              self?.quickTagsState = .analyzing(progress: progress, message: message)
            }
          }
        )

        guard !Task.isCancelled else { return }
        self.quickTagsCache.briefSummary = summary
        self.quickTagsCache.generatedAt = Date()
        self.quickTagsState = .completed
        logger.info("Brief summary generated successfully")
      } catch {
        self.quickTagsState = .error("Failed: \(error.localizedDescription)")
        logger.error("Brief summary generation failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  // MARK: - Cloud AI (BYOK)

  /// Generate cloud-based transcript analysis with streaming.
  ///
  /// Delegates the actual work to `CloudAnalysisJobCoordinator.shared`, which
  /// owns the in-flight Task and the live snapshot. The computed properties
  /// `cloudAnalysisState` / `streamingText` / `isStreaming` /
  /// `currentStreamingType` are computed against that snapshot, so popping
  /// the detail view does not interrupt the request, and reopening the same
  /// episode resumes the streaming UI mid-flight.
  func generateCloudAnalysis(type: CloudAnalysisType, formatHint: String? = nil) {
    let settings = AISettingsManager.shared

    guard settings.hasConfiguredProvider else {
      cloudAnalysisState = .error("No API key configured. Go to Settings > AI Settings.")
      return
    }

    guard transcriptSource?.hasTranscript ?? false else {
      cloudAnalysisState = .error("No transcript available. Generate transcript first.")
      return
    }

    guard let audioURL = episode.audioURL, !audioURL.isEmpty else {
      cloudAnalysisState = .error("Episode has no audio URL — cannot key the analysis job.")
      return
    }

    guard let context = modelContext else {
      cloudAnalysisState = .error("Model context not available.")
      return
    }

    _localCloudAnalysisState = .idle

    let segments = (transcriptSource?.transcriptSegments ?? []).map { segment in
      QuotesFinder.Segment(startTime: segment.startTime, text: segment.text)
    }

    CloudAnalysisJobCoordinator.shared.startAnalysis(
      audioURL: audioURL,
      transcript: (transcriptSource?.transcriptText ?? ""),
      transcriptSegments: segments,
      episodeTitle: episode.title,
      podcastTitle: podcastTitle,
      type: type,
      podcastLanguage: podcastLanguage,
      formatHint: formatHint,
      modelContext: context
    )
  }

  /// Ask a question about the episode using cloud AI
  func askCloudQuestion(_ question: String) {
    let settings = AISettingsManager.shared

    guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    guard settings.hasConfiguredProvider else {
      cloudQuestionState = .error("No API key configured. Go to Settings > AI Settings.")
      return
    }

    guard transcriptSource?.hasTranscript ?? false else {
      cloudQuestionState = .error("No transcript available. Generate transcript first.")
      return
    }

    let transcriptSnapshot = (transcriptSource?.transcriptText ?? "")
    let podcastLanguageSnapshot = podcastLanguage

    let episodeTitle = episode.title

    cloudQuestionTask?.cancel()
    cloudQuestionTask = Task { [weak self] in
      guard let self else { return }
      #if os(iOS)
      var bgTaskID: UIBackgroundTaskIdentifier = .invalid
      bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "CloudQA") {
        if bgTaskID != .invalid {
          UIApplication.shared.endBackgroundTask(bgTaskID)
          bgTaskID = .invalid
        }
      }
      defer {
        if bgTaskID != .invalid {
          UIApplication.shared.endBackgroundTask(bgTaskID)
        }
      }
      #endif

      do {
        self.cloudQuestionState = .analyzing(progress: 0, message: "Processing question...")

        let service = CloudAIService.shared

        let result = try await service.askQuestion(
          question,
          transcript: transcriptSnapshot,
          episodeTitle: episodeTitle,
          podcastLanguage: podcastLanguageSnapshot,
          progressCallback: { [weak self] message, progress in
            Task { @MainActor in
              self?.cloudQuestionState = .analyzing(progress: progress, message: message)
            }
          }
        )

        guard !Task.isCancelled else { return }
        self.cloudAnalysisCache.questionAnswers.append(result)
        self.cloudQuestionState = .completed

        self.saveQAToSwiftData(result)

        logger.info("Cloud Q&A completed successfully - Provider: \(result.provider.displayName), Model: \(result.model)")
      } catch {
        self.cloudQuestionState = .error(error.localizedDescription)
        logger.error("Cloud Q&A failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Stop an in-flight analysis without discarding an already-saved result.
  func cancelCloudAnalysis() {
    CloudAnalysisJobCoordinator.shared.cancel(audioURL: cloudJobKey)
    cloudAnalysisState = .idle
  }

  /// Clear a specific cloud analysis result
  func clearCloudAnalysis(type: CloudAnalysisType) {
    switch type {
    case .analysis:
      cloudAnalysisCache.analysis = nil
    }
    CloudAnalysisJobCoordinator.shared.cancel(audioURL: cloudJobKey)
    cloudAnalysisState = .idle
  }

  /// Clear all AI results
  func clearAllAIResults() {
    quickTagsCache.clear()
    quickTagsState = .idle
    cloudAnalysisCache.clearAll()
    CloudAnalysisJobCoordinator.shared.cancel(audioURL: cloudJobKey)
    cloudAnalysisState = .idle
    cloudQuestionState = .idle
  }

  // MARK: - SwiftData Persistence

  /// Load AI analysis from SwiftData on attach.
  ///
  /// Looks up by `episodeAudioURL` (fast path), then falls back to
  /// `episodeTitle + podcastTitle` to survive podcast-host CDN URL drift
  /// (Megaphone/Libsyn/Anchor rewrite tracking URLs over time, so the
  /// stored URL on an old analysis row may no longer equal the current
  /// `episode.audioURL`). When a fallback hits, the stale row's URL is
  /// re-linked so future lookups take the fast path.
  func loadAIAnalysisFromSwiftData() {
    guard let context = modelContext else { return }

    let audioURL = episode.audioURL ?? ""
    let episodeTitle = episode.title
    let podcast = podcastTitle

    // Load cloud analysis
    let cloudDescriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )
    var cloudModel = (try? context.fetch(cloudDescriptor))?.first
    if cloudModel == nil, !episodeTitle.isEmpty {
      let titleDescriptor = FetchDescriptor<EpisodeAIAnalysis>(
        predicate: #Predicate {
          $0.episodeTitle == episodeTitle && $0.podcastTitle == podcast
        }
      )
      if let fallback = (try? context.fetch(titleDescriptor))?.first {
        cloudModel = fallback
        if !audioURL.isEmpty, fallback.episodeAudioURL != audioURL {
          fallback.episodeAudioURL = audioURL
          context.saveOrLog()
        }
      }
    }
    if let cloudModel {
      aiAnalysisModel = cloudModel
      restoreCloudAnalysisFromModel(cloudModel)
    }

    // Load quick tags (same fallback pattern; EpisodeQuickTagsModel only
    // carries episodeTitle, so the fallback key is title-only).
    let tagsDescriptor = FetchDescriptor<EpisodeQuickTagsModel>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )
    var tagsModel = (try? context.fetch(tagsDescriptor))?.first
    if tagsModel == nil, !episodeTitle.isEmpty {
      let titleDescriptor = FetchDescriptor<EpisodeQuickTagsModel>(
        predicate: #Predicate { $0.episodeTitle == episodeTitle }
      )
      if let fallback = (try? context.fetch(titleDescriptor))?.first {
        tagsModel = fallback
        if !audioURL.isEmpty, fallback.episodeAudioURL != audioURL {
          fallback.episodeAudioURL = audioURL
          context.saveOrLog()
        }
      }
    }
    if let tagsModel {
      restoreQuickTagsFromModel(tagsModel)
    }
  }

  /// Restore cloud analysis cache from SwiftData model
  private func restoreCloudAnalysisFromModel(_ model: EpisodeAIAnalysis) {
    if let parsed = model.parsedAnalysis {
      cloudAnalysisCache.analysis = CloudAnalysisResult(
        type: .analysis,
        content: model.analysisJSON ?? formatAnalysisAsText(parsed),
        parsedAnalysis: parsed,
        provider: CloudAIProvider(rawValue: model.provider ?? "") ?? .openai,
        model: model.model ?? "",
        timestamp: model.generatedAt ?? model.updatedAt
      )
    } else if let raw = model.rawResponse, !raw.isEmpty {
      // Undecodable reply: show it verbatim with a warning rather than an
      // empty tab. `AnalysisResultCardView` renders `content` when
      // `parsedAnalysis` is nil, and Regenerate stays one tap away.
      cloudAnalysisCache.analysis = CloudAnalysisResult(
        type: .analysis,
        content: raw,
        parsedAnalysis: nil,
        provider: CloudAIProvider(rawValue: model.provider ?? "") ?? .openai,
        model: model.model ?? "",
        timestamp: model.generatedAt ?? model.updatedAt,
        jsonParseWarning: CloudAIService.unstructuredResponseWarning
      )
    }
    cloudAnalysisCache.questionAnswers = model.qaHistory
  }

  /// Restore quick tags cache from SwiftData model
  private func restoreQuickTagsFromModel(_ model: EpisodeQuickTagsModel) {
    let tags = EpisodeQuickTags(
      tags: model.tags,
      primaryCategory: model.primaryCategory,
      secondaryCategory: model.secondaryCategory,
      contentType: model.contentType,
      difficulty: model.difficulty
    )
    quickTagsCache.tags = tags
    quickTagsCache.briefSummary = model.briefSummary
    quickTagsCache.generatedAt = model.generatedAt
  }

  /// Save quick tags to SwiftData
  private func saveQuickTagsToSwiftData(tags: EpisodeQuickTags) {
    guard let context = modelContext else { return }
    guard let audioURL = episode.audioURL else { return }

    let descriptor = FetchDescriptor<EpisodeQuickTagsModel>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )

    do {
      let results = try context.fetch(descriptor)
      if let existing = results.first {
        existing.tags = tags.tags
        existing.primaryCategory = tags.primaryCategory
        existing.secondaryCategory = tags.secondaryCategory
        existing.contentType = tags.contentType
        existing.difficulty = tags.difficulty
        existing.briefSummary = quickTagsCache.briefSummary
        existing.generatedAt = Date()
      } else {
        let model = EpisodeQuickTagsModel(
          episodeAudioURL: audioURL,
          episodeTitle: episode.title,
          tags: tags.tags,
          primaryCategory: tags.primaryCategory,
          secondaryCategory: tags.secondaryCategory,
          contentType: tags.contentType,
          difficulty: tags.difficulty,
          briefSummary: quickTagsCache.briefSummary
        )
        context.insert(model)
      }

      try context.save()
      logger.info("Quick tags saved to SwiftData")
    } catch {
      logger.error("Failed to save quick tags: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Save Q&A to SwiftData
  private func saveQAToSwiftData(_ result: CloudQAResult) {
    guard let context = modelContext else { return }
    guard let audioURL = episode.audioURL else { return }

    let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )

    do {
      let results = try context.fetch(descriptor)
      let model: EpisodeAIAnalysis
      if let existing = results.first {
        model = existing
      } else {
        model = EpisodeAIAnalysis(
          episodeAudioURL: audioURL,
          episodeTitle: episode.title,
          podcastTitle: podcastTitle
        )
        context.insert(model)
      }

      model.addQA(result)
      aiAnalysisModel = model

      try context.save()
      logger.info("Q&A saved to SwiftData - Provider: \(result.provider.displayName), Model: \(result.model)")
    } catch {
      logger.error("Failed to save Q&A: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Format Helpers

  private func formatAnalysisAsText(_ analysis: ParsedEpisodeAnalysisResponse) -> String {
    var parts: [String] = []
    if !analysis.overview.isEmpty { parts.append(analysis.overview) }
    if !analysis.keyTakeaways.isEmpty { parts.append("Key Takeaways:\n• " + analysis.keyTakeaways.joined(separator: "\n• ")) }
    if !analysis.people.isEmpty { parts.append("People: \(analysis.people.joined(separator: ", "))") }
    if !analysis.organizations.isEmpty { parts.append("Organizations: \(analysis.organizations.joined(separator: ", "))") }
    if !analysis.products.isEmpty { parts.append("Products: \(analysis.products.joined(separator: ", "))") }
    if !analysis.locations.isEmpty { parts.append("Locations: \(analysis.locations.joined(separator: ", "))") }
    if !analysis.resources.isEmpty { parts.append("Resources: \(analysis.resources.joined(separator: ", "))") }
    if !analysis.highlights.isEmpty { parts.append("Highlights:\n• " + analysis.highlights.joined(separator: "\n• ")) }
    if !analysis.actionItems.isEmpty { parts.append("Action Items:\n• " + analysis.actionItems.joined(separator: "\n• ")) }
    if let controversial = analysis.controversialPoints, !controversial.isEmpty {
      parts.append("Controversial Points:\n• " + controversial.joined(separator: "\n• "))
    }
    if let entertaining = analysis.entertainingMoments, !entertaining.isEmpty {
      parts.append("Entertaining Moments:\n• " + entertaining.joined(separator: "\n• "))
    }
    if !analysis.conclusion.isEmpty { parts.append("Conclusion: \(analysis.conclusion)") }
    return parts.joined(separator: "\n\n")
  }

  // MARK: - Cleanup

  /// Cancel coordinator-owned tasks. Note: `cloudQuestionTask` is intentionally
  /// not cancelled so an in-flight answer can finish and persist; the
  /// background-task wrapping inside `askCloudQuestion` bounds suspension on iOS.
  func cleanup() {
    onDeviceAICheckTask?.cancel()
    onDeviceAICheckTask = nil
    quickTagsTask?.cancel()
    quickTagsTask = nil
    briefSummaryTask?.cancel()
    briefSummaryTask = nil
    cloudJobObserverTask?.cancel()
    cloudJobObserverTask = nil
  }
}
