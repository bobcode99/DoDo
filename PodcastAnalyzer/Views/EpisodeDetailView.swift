//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  iOS episode landing page. Single ScrollView containing the episode
//  header, a merged action row (Play / Download / Transcript / AI Analysis),
//  and the episode summary — the header scrolls with the content.
//
//  Aliased to MacEpisodeDetailView on macOS so shared iOS-leaning files
//  (HomeView, SearchView, etc.) keep compiling on macOS even though they
//  are never displayed there at runtime.
//

import SwiftData
#if os(macOS)
typealias EpisodeDetailView = MacEpisodeDetailView
#endif

#if os(iOS)
import SwiftUI

struct EpisodeDetailView: View {
    @State private var viewModel: EpisodeDetailViewModel

    @State private var showDeleteConfirmation = false
    @State private var showSubtitleSettings = false
    @State private var showTranslationLanguagePicker = false
    @State private var showRegenerateConfirmation = false

    // Inline timestamp tap handling (description timestamp links).
    @State private var tappedTimestampSeconds: TimeInterval?
    @State private var timestampTapX: CGFloat = 0
    @State private var timestampTapY: CGFloat = 200
    @Environment(\.zoomNamespace) private var zoomNamespace

    init(
        episode: PodcastEpisodeInfo,
        podcastTitle: String,
        fallbackImageURL: String?,
        podcastLanguage: String = "en"
    ) {
        _viewModel = State(
            initialValue: EpisodeDetailViewModel(
                episode: episode,
                podcastTitle: podcastTitle,
                fallbackImageURL: fallbackImageURL,
                podcastLanguage: podcastLanguage
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EpisodeDetailHeaderView(
                    viewModel: viewModel,
                    showsPlaybackButtons: false
                )

                actionRow
                    .padding(.horizontal)

                EpisodeSummaryView(
                    viewModel: viewModel,
                    tappedTimestampSeconds: $tappedTimestampSeconds
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        // SpatialTapGesture, not `DragGesture(minimumDistance: 0)`: a zero
        // distance drag claims every touch from the first pixel, so the edge
        // swipe back never reached the navigation stack once this page was
        // pushed with a zoom transition. EpisodeListView has no such gesture,
        // which is why the library grid's zoom always swiped back fine.
        .simultaneousGesture(
            SpatialTapGesture()
                .onEnded {
                    timestampTapX = $0.location.x
                    timestampTapY = $0.location.y
                }
        )
        .timestampPopup(
            viewModel: viewModel,
            tappedSeconds: $tappedTimestampSeconds,
            tapX: timestampTapX,
            tapY: timestampTapY
        )
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EpisodeDetailToolbarItems(
                    viewModel: viewModel,
                    selectedTab: 0, // Summary — translate button shown (acts on description)
                    showTranslationLanguagePicker: $showTranslationLanguagePicker,
                    showDeleteConfirmation: $showDeleteConfirmation
                )
            }
        }
        .episodeDetailSheetsAndAlerts(
            viewModel: viewModel,
            showDeleteConfirmation: $showDeleteConfirmation,
            showSubtitleSettings: $showSubtitleSettings,
            showRegenerateConfirmation: $showRegenerateConfirmation,
            showTranslationLanguagePicker: $showTranslationLanguagePicker
        )
    }

    /// Shown when the transcript ends well before the audio does, so a reader
    /// who reaches the end knows the rest is missing rather than assuming the
    /// episode simply went quiet.
    private var transcriptTruncatedNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(
                "Transcript covers only \(Int(viewModel.transcriptCoveredFraction * 100))% of this episode. Timings may not line up with the audio."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Action row (Play / Download + Transcript / AI Analysis rows)

    private var actionRow: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                LivePlaybackButton(
                    episodeTitle: viewModel.title,
                    podcastTitle: viewModel.podcastTitle,
                    duration: viewModel.savedDuration,
                    formattedDuration: viewModel.formattedDuration,
                    lastPlaybackPosition: viewModel.lastPlaybackPosition,
                    playbackProgress: viewModel.playbackProgress,
                    isCompleted: viewModel.isCompleted,
                    onPlay: { viewModel.playAction() },
                    style: .iconOnly,
                    isDisabled: viewModel.isPlayDisabled
                )

                EpisodeDownloadButton(viewModel: viewModel)

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                NavigationLink(
                    value: EpisodeTranscriptRoute(
                        episode: viewModel.episode,
                        podcastTitle: viewModel.podcastTitle,
                        fallbackImageURL: viewModel.imageURLString,
                        podcastLanguage: viewModel.podcastLanguage
                    )
                ) {
                    NavRowLabel(
                        icon: "captions.bubble",
                        tint: .purple,
                        title: "Transcript",
                        subtitle: "Synced · tap a line to seek"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open the transcript for this episode")

                if viewModel.transcriptIsTruncated {
                    transcriptTruncatedNotice
                }

                Divider().padding(.leading, 52)

                let aiRoute = EpisodeAIAnalysisRoute(
                    episode: viewModel.episode,
                    podcastTitle: viewModel.podcastTitle,
                    fallbackImageURL: viewModel.imageURLString,
                    podcastLanguage: viewModel.podcastLanguage,
                    zoomsFromSource: true
                )
                NavigationLink(value: aiRoute) {
                    NavRowLabel(
                        icon: "sparkles",
                        tint: .orange,
                        title: "AI Insights",
                        subtitle: "Summary, takeaways & quotes"
                    )
                }
                .buttonStyle(.plain)
                .zoomSource(id: aiRoute.id, in: zoomNamespace)
                .accessibilityHint("Open the AI analysis for this episode")
            }
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }

}

#Preview {
    NavigationStack {
        EpisodeDetailView(
            episode: PodcastEpisodeInfo(
                title: "The On-Device AI Revolution",
                podcastEpisodeDescription: "Maya sits down with three engineers shipping speech models that run entirely on the phone — why latency, privacy, and battery all point the same direction.",
                pubDate: .now,
                audioURL: "https://example.com/ep.mp3",
                duration: 4320
            ),
            podcastTitle: "Signal & Noise",
            fallbackImageURL: nil,
            podcastLanguage: "en"
        )
    }
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}

#endif
