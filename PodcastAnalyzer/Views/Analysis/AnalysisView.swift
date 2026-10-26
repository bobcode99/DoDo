//
//  AnalysisView.swift
//  PodcastAnalyzer
//
//  Top-level tab/destination listing every episode that has a stored
//  transcript and/or EpisodeAIAnalysis, one row per episode. Tap a row to push
//  the per-episode AI page where the user can run or review the analysis and
//  keep asking questions.
//

import SwiftData
import SwiftUI

struct AnalysisView: View {
  @Query(sort: \EpisodeAIAnalysis.updatedAt, order: .reverse)
  private var analyses: [EpisodeAIAnalysis]

  @Query(Self.transcriptDescriptor)
  private var transcripts: [EpisodeTranscriptModel]

  /// Browsed (unsubscribed) shows are cached too, and their snapshot still
  /// carries each episode's description, artwork, and pubDate.
  @Query private var podcasts: [PodcastInfoModel]

  @AppStorage("analysisFilter") private var filter: Filter = .all
  @AppStorage("analysisSort") private var sort: Sort = .recent
  @State private var searchText: String = ""
  @Environment(\.zoomNamespace) private var zoomNamespace

  enum Filter: String, CaseIterable { case all, analyzed, transcribed }
  enum Sort: String, CaseIterable { case recent, show, title }

  /// Only the columns the list needs — `segmentsJSON` is a whole transcript
  /// and must not be materialized for every row.
  private static var transcriptDescriptor: FetchDescriptor<EpisodeTranscriptModel> {
    var descriptor = FetchDescriptor<EpisodeTranscriptModel>()
    descriptor.propertiesToFetch = [\.episodeId, \.generatedAt]
    return descriptor
  }

  private var podcastByTitle: [String: PodcastInfoModel] {
    Dictionary(podcasts.map { ($0.title, $0) }, uniquingKeysWith: { $0.isSubscribed ? $0 : $1 })
  }

  private var allEntries: [AnalysisEntry] {
    AnalysisEntry.merge(transcripts: transcripts, analyses: analyses)
  }

  private func visibleEntries(from entries: [AnalysisEntry]) -> [AnalysisEntry] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let filtered = entries.filter { entry in
      let matchesFilter = switch filter {
      case .all: true
      case .analyzed: entry.analysis != nil
      case .transcribed: entry.transcriptDate != nil
      }
      return matchesFilter && (trimmed.isEmpty
        || entry.episodeTitle.localizedStandardContains(trimmed)
        || entry.podcastTitle.localizedStandardContains(trimmed))
    }
    return switch sort {
    case .recent: filtered.sorted { $0.updatedAt > $1.updatedAt }
    case .show: filtered.sorted { ($0.podcastTitle, $1.updatedAt) < ($1.podcastTitle, $0.updatedAt) }
    case .title: filtered.sorted { $0.episodeTitle.localizedStandardCompare($1.episodeTitle) == .orderedAscending }
    }
  }

  var body: some View {
    let entries = allEntries
    let visible = visibleEntries(from: entries)
    Group {
      if entries.isEmpty {
        ContentUnavailableView {
          Label("Nothing Here Yet", systemImage: Constants.analysisIconName)
        } description: {
          Text("Generate a transcript or run AI analysis on an episode and it will show up here for quick browsing and follow-up questions.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(spacing: 12) {
            Picker("Filter", selection: $filter) {
              ForEach(Filter.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue.capitalized)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if visible.isEmpty {
              ContentUnavailableView.search(text: searchText)
            }
            ForEach(AnalysisRow.make(for: visible, podcastByTitle: podcastByTitle)) { row(for: $0) }
          }
          .padding(16)
        }
      }
    }
    .navigationTitle(Constants.analysisString)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
    .searchable(text: $searchText, prompt: "Search episodes")
    .toolbar {
      Menu {
        Picker("Sort By", selection: $sort) {
          Text("Recently Updated").tag(Sort.recent)
          Text("Show").tag(Sort.show)
          Text("Episode Title").tag(Sort.title)
        }
      } label: {
        Label("Sort", systemImage: "arrow.up.arrow.down")
      }
    }
  }

  private func row(for row: AnalysisRow) -> some View {
    NavigationLink(value: row.aiRoute) {
      AnalysisRowCard(entry: row.entry, artworkURL: row.artworkURL)
    }
    .buttonStyle(.plain)
    .zoomSource(id: row.aiRoute.id, in: zoomNamespace)
    .contextMenu {
      NavigationLink(value: row.detailRoute) {
        Label("View Episode", systemImage: "doc.text")
      }
      if row.entry.transcriptDate != nil {
        NavigationLink(value: row.transcriptRoute) {
          Label("View Transcript", systemImage: "text.quote")
        }
      }
      if let podcast = podcastByTitle[row.entry.podcastTitle] {
        NavigationLink(value: PodcastBrowseRoute(podcastModel: podcast)) {
          Label("View Show", systemImage: "list.bullet")
        }
      }
    }
  }
}

#if DEBUG
  private enum AnalysisPreviewData {
    /// Every non-optional field of `ParsedEpisodeAnalysisResponse`, so the
    /// card's overview snippet decodes.
    static let analysisJSON = """
      {"overview": "Maya and Ravi walk through why incremental builds regressed and the two flags that fixed it.",
       "mainTopics": [], "keyTakeaways": [], "keyInsights": [], "targetAudience": "",
       "engagementLevel": "", "people": [], "organizations": [], "products": [],
       "locations": [], "resources": [], "highlights": [], "notableQuotes": [],
       "actionItems": [], "conclusion": ""}
      """

    static let qaJSON = """
      [{"question": "Which flag mattered most?", "answer": "Explicit modules.",
        "confidence": "high", "providerRawValue": "Claude", "model": "preview", "timestamp": 0}]
      """

    // Static so a preview re-render can't free the store while @Query holds it.
    static let populated = makeContainer(populated: true)
    static let empty = makeContainer(populated: false)

    private static func makeContainer(populated: Bool) -> ModelContainer {
      do {
        let container = try ModelContainer(
          for: EpisodeAIAnalysis.self, EpisodeTranscriptModel.self, PodcastInfoModel.self,
          // Distinct names: two unnamed in-memory stores in one process collide.
          configurations: ModelConfiguration(
            populated ? "AnalysisPreviewPopulated" : "AnalysisPreviewEmpty",
            isStoredInMemoryOnly: true)
        )
        guard populated else { return container }
        let context = container.mainContext

        // Analysis + transcript + Q&A on one episode.
        let full = EpisodeAIAnalysis(
          episodeAudioURL: "https://example.com/ep1.mp3",
          episodeTitle: "Why Your Build Is Slow", podcastTitle: "Signal & Noise")
        full.analysisJSON = analysisJSON
        full.qaHistoryJSON = qaJSON
        context.insert(full)
        context.insert(transcript("Signal & Noise", "Why Your Build Is Slow", daysAgo: 1))

        // Analysis only.
        let analysisOnly = EpisodeAIAnalysis(
          episodeAudioURL: "https://example.com/ep2.mp3",
          episodeTitle: "Everything Is a Cache", podcastTitle: "Signal & Noise")
        analysisOnly.analysisJSON = analysisJSON
        analysisOnly.updatedAt = .now.addingTimeInterval(-3 * 86_400)
        context.insert(analysisOnly)

        // Transcript only — the rows this redesign added.
        context.insert(transcript("Signal & Noise", "Reading the Crash Log", daysAgo: 0))
        context.insert(transcript("Deep Dish", "A Brief History of Pizza Ovens", daysAgo: 5))
        return container
      } catch {
        fatalError("Preview container failed to build: \(error)")
      }
    }

    private static func transcript(
      _ podcastTitle: String, _ episodeTitle: String, daysAgo: Double
    ) -> EpisodeTranscriptModel {
      let model = EpisodeTranscriptModel(
        episodeId: EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle))
      model.generatedAt = .now.addingTimeInterval(-daysAgo * 86_400)
      return model
    }
  }

  #Preview("Analyses and transcripts") {
    NavigationStack {
      AnalysisView()
    }
    .modelContainer(AnalysisPreviewData.populated)
  }

  #Preview("Empty") {
    NavigationStack {
      AnalysisView()
    }
    .modelContainer(AnalysisPreviewData.empty)
  }
#endif
