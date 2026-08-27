import SwiftData
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "ExpandedPlayerView")

struct ExpandedPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var viewModel = ExpandedPlayerViewModel()
    @State private var showQueue = false

    var onNavigateToEpisodeDetail: ((PodcastEpisodeInfo, String, String?, String?) -> Void)?
    var onNavigateToPodcast: ((PodcastInfoModel) -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.gray.opacity(0.3), Color.platformBackground],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()

                if hSizeClass == .regular {
                    ExpandedPlayerPadContent(
                        viewModel: viewModel,
                        onNavigateToEpisodeDetail: navigateToEpisodeDetail,
                        onNavigateToPodcast: navigateToPodcast,
                        onOpenQueue: openQueue
                    )
                } else {
                    ExpandedPlayerContent(
                        viewModel: viewModel,
                        onNavigateToEpisodeDetail: navigateToEpisodeDetail,
                        onNavigateToPodcast: navigateToPodcast,
                        onOpenQueue: openQueue
                    )
                }

                // Dim rather than blur. `.blur` is installed unconditionally even
                // at radius 0, which forced the whole player subtree — artwork
                // shadow, glass controls, scrubber — into an offscreen buffer that
                // re-rasterized on every playback tick.
                if showQueue {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)

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
        var podcastLanguage: String?
        if let podcastModel = viewModel.podcastModel {
            // One decode for both the episode lookup and the language below.
            let info = podcastModel.podcastInfo
            podcastLanguage = info.language
            if description == nil,
               let fullEpisode = info.episodes.first(where: { $0.title == episode.title }) {
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
