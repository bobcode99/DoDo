import SwiftData
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "ExpandedPlayerView")

struct ExpandedPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ExpandedPlayerViewModel()
    @State private var showQueue = false

    var onNavigateToEpisodeDetail: ((PodcastEpisodeInfo, String, String?, String?) -> Void)?
    var onNavigateToPodcast: ((PodcastInfoModel) -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                ArtworkBackgroundView(imageURL: viewModel.imageURL)

                ExpandedPlayerContent(
                    viewModel: viewModel,
                    onNavigateToEpisodeDetail: navigateToEpisodeDetail,
                    onNavigateToPodcast: navigateToPodcast,
                    onOpenQueue: openQueue
                )
                .blur(radius: showQueue ? 3 : 0)

                if showQueue {
                    QueueOverlay(
                        queue: viewModel.queue,
                        onPlayItem: { index in
                            viewModel.skipToQueueItem(at: index)
                            withAnimation { showQueue = false }
                        },
                        onRemoveItem: { index in
                            viewModel.removeFromQueue(at: index)
                        },
                        onMoveItems: { source, destination in
                            viewModel.moveInQueue(from: source, to: destination)
                        },
                        onDismiss: {
                            withAnimation { showQueue = false }
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
            }
            .onDisappear {
                viewModel.cleanup()
            }
            .onChange(of: viewModel.currentEpisode?.id) {
                viewModel.checkEpisodeChange()
            }
            // Immersive artwork background is always dark, so pin the whole
            // player to dark: .primary/.secondary and glassEffect resolve to
            // light, legible content regardless of the system appearance.
            .environment(\.colorScheme, .dark)
        }
    }

    private func openQueue() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showQueue = true
        }
    }

    private func navigateToEpisodeDetail() {
        guard let episode = viewModel.currentEpisode else { return }
        var description = episode.episodeDescription
        var pubDate = episode.pubDate
        var guid = episode.guid
        var duration = episode.duration
        if description == nil, let podcastModel = viewModel.podcastModel {
            if let fullEpisode = podcastModel.podcastInfo.episodes.first(where: { $0.title == episode.title }) {
                description = fullEpisode.podcastEpisodeDescription
                pubDate = pubDate ?? fullEpisode.pubDate
                guid = guid ?? fullEpisode.guid
                duration = duration ?? fullEpisode.duration
            }
        }
        let episodeInfo = PodcastEpisodeInfo(
            title: episode.title,
            podcastEpisodeDescription: description,
            pubDate: pubDate,
            audioURL: episode.audioURL,
            imageURL: episode.imageURL,
            duration: duration,
            guid: guid
        )
        let podcastLanguage = viewModel.podcastModel?.podcastInfo.language
        dismiss()
        onNavigateToEpisodeDetail?(episodeInfo, episode.podcastTitle, episode.imageURL, podcastLanguage)
    }

    private func navigateToPodcast() {
        if viewModel.podcastModel == nil {
            viewModel.loadPodcastModel()
        }
        guard let podcastModel = viewModel.podcastModel else {
            logger.warning("Podcast not found in library for navigation")
            return
        }
        dismiss()
        onNavigateToPodcast?(podcastModel)
    }
}

// Presented the same way the app does (sheet + page sizing) so the canvas
// shows real sizing on iPad/iPhone. Player chrome renders; episode text is
// empty here because the view model reads the live audio manager singleton.
#Preview {
    @Previewable @State var show = true
    Color.platformBackground
        .ignoresSafeArea()
        .sheet(isPresented: $show) {
            ExpandedPlayerView()
                .presentationSizing(.page)
        }
}
