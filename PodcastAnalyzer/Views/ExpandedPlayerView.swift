import OSLog
import SwiftData
import SwiftUI

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
                LinearGradient(
                    colors: [Color.gray.opacity(0.3), Color.platformBackground],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            PlayerArtworkView(imageURL: viewModel.imageURL, isPlaying: viewModel.isPlaying)
                                .padding(.top, 16)

                            PlayerEpisodeInfoView(
                                viewModel: viewModel,
                                onNavigateToEpisodeDetail: navigateToEpisodeDetail,
                                onNavigateToPodcast: navigateToPodcast
                            )
                            .padding(.top, 24)
                        }

                        Spacer(minLength: 20)

                        VStack(spacing: 32) {
                            SmoothScrubber(
                                currentTime: viewModel.currentTime,
                                duration: viewModel.duration,
                                isDurationLoading: viewModel.isDurationLoading,
                                onSeek: viewModel.seekToProgress
                            )
                            .padding(.horizontal, 32)

                            PlayerControlsView(viewModel: viewModel)

                            #if os(iOS)
                            HStack(spacing: 12) {
                                Image(systemName: "speaker.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                SystemVolumeSlider()
                                    .frame(height: 32)
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 32)
                            #endif
                        }

                        Spacer(minLength: 32)

                        PlayerBottomActionsView(
                            queueCount: viewModel.queue.count,
                            onNavigateToEpisodeDetail: navigateToEpisodeDetail,
                            onOpenQueue: openQueue
                        )
                        .padding(.bottom, 40)
                    }
                    .containerRelativeFrame(.vertical, alignment: .center)
                }
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

#Preview {
    ExpandedPlayerView()
}
