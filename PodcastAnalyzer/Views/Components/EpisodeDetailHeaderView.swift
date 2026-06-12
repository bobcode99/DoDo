
import SwiftData
import SwiftUI

struct EpisodeDetailHeaderView: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    /// Hosts that present their own combined action row (e.g. iOS detail page
    /// with merged Play / Download / Transcript / AI Analysis) pass `false`
    /// to suppress the in-header Play + Download row.
    var showsPlaybackButtons: Bool = true
    @Environment(\.modelContext) private var modelContext
    @State private var cachedPodcastModel: PodcastInfoModel?
    @State private var browseCollectionId: String?

    // Platform-tuned sizing. macOS windows are wide; the phone-sized 80pt
    // artwork and `.subheadline` title leave the header feeling cramped.
    #if os(macOS)
    private let artworkSize: CGFloat = 160
    private let artworkCornerRadius: CGFloat = 14
    private let topSpacing: CGFloat = 18
    private let titleFont: Font = .title3
    private let podcastTitleFont: Font = .subheadline
    private let metadataFont: Font = .footnote
    private let statusIconSize: CGFloat = 14
    #else
    private let artworkSize: CGFloat = 80
    private let artworkCornerRadius: CGFloat = 10
    private let topSpacing: CGFloat = 12
    private let titleFont: Font = .subheadline
    private let podcastTitleFont: Font = .caption
    private let metadataFont: Font = .caption
    private let statusIconSize: CGFloat = 12
    #endif

    /// Value-based navigation route built lazily.
    /// Uses the SwiftData model if available, otherwise falls back to an unsubscribed
    /// browse route so trending/unsubscribed episodes can still navigate to the show.
    private var podcastBrowseRoute: PodcastBrowseRoute? {
        if let model = cachedPodcastModel {
            return PodcastBrowseRoute(podcastModel: model)
        }
        if let collectionId = browseCollectionId {
            return PodcastBrowseRoute(
                podcastName: viewModel.podcastTitle,
                artworkURL: viewModel.imageURLString,
                artistName: "",
                collectionId: collectionId,
                applePodcastURL: nil
            )
        }
        return nil
    }

    var body: some View {
        #if os(macOS)
        macHeader
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task { await performBrowseLookup() }
        #else
        compactHeader
            .padding(.horizontal)
            .padding(.vertical, 10)
            .task { await performBrowseLookup() }
        #endif
    }

    // MARK: - Compact (iOS) Header

    @ViewBuilder
    private var compactHeader: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                artwork
                metadataColumn
                Spacer()
            }
            if showsPlaybackButtons {
                playbackRow
            }
            streamingIndicator
        }
    }

    // MARK: - Wide (macOS) Header

    @ViewBuilder
    private var macHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            artwork
            VStack(alignment: .leading, spacing: 10) {
                metadataColumn
                if showsPlaybackButtons {
                    playbackRow
                }
                streamingIndicator
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var artwork: some View {
        CachedArtworkImage(
            urlString: viewModel.imageURLString,
            size: artworkSize,
            cornerRadius: artworkCornerRadius
        )
        .shadow(radius: 3, y: 2)
    }

    @ViewBuilder
    private var metadataColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleView
            podcastTitleLink
            metadataRow
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if let translatedTitle = viewModel.translation.translatedEpisodeTitle {
            VStack(alignment: .leading, spacing: 4) {
                Text(translatedTitle)
                    .font(titleFont)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup("Original") {
                    Text(viewModel.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
                .font(.caption2)
                .foregroundStyle(.blue)
            }
        } else {
            Text(viewModel.title)
                .font(titleFont)
                .fontWeight(.semibold)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var podcastTitleLink: some View {
        NavigationLink(value: podcastBrowseRoute) {
            HStack(spacing: 4) {
                if let translatedTitle = viewModel.translation.translatedPodcastTitle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(translatedTitle)
                            .font(podcastTitleFont)
                            .foregroundStyle(.blue)
                        Text(viewModel.podcastTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(viewModel.podcastTitle)
                        .font(podcastTitleFont)
                        .foregroundStyle(.blue)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.blue)
            }
        }
        .buttonStyle(.plain)
        .disabled(podcastBrowseRoute == nil)
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 8) {
            if let dateString = viewModel.pubDateString {
                Text(dateString)
                    .font(metadataFont)
                    .foregroundStyle(.secondary)
            }
            statusIcons
        }
    }

    @ViewBuilder
    private var statusIcons: some View {
        HStack(spacing: 6) {
            if viewModel.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: statusIconSize))
                    .foregroundStyle(.yellow)
            }

            if viewModel.hasLocalAudio {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: statusIconSize))
                    .foregroundStyle(.green)
            }

            switch viewModel.transcript.transcriptState {
            case .idle, .error:
                if viewModel.hasTranscript {
                    Image(systemName: "captions.bubble.fill")
                        .font(.system(size: statusIconSize))
                        .foregroundStyle(.purple)
                }
            case .downloadingModel, .transcribing:
                HStack(spacing: 2) { ProgressView().scaleEffect(0.5) }
            case .completed:
                Image(systemName: "captions.bubble.fill")
                    .font(.system(size: statusIconSize))
                    .foregroundStyle(.purple)
            }

            if viewModel.aiAnalysis.hasAIAnalysis {
                Image(systemName: "sparkles")
                    .font(.system(size: statusIconSize))
                    .foregroundStyle(.orange)
            }

            if viewModel.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: statusIconSize))
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var playbackRow: some View {
        HStack(spacing: 8) {
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

            Spacer()
        }
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        if !viewModel.hasLocalAudio && viewModel.audioURL != nil {
            HStack(spacing: 4) {
                Image(systemName: "wifi")
                Text("Streaming")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Async work

    private func performBrowseLookup() async {
        let title = viewModel.podcastTitle
        let descriptor = FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.title == title }
        )
        // Multiple rows can share a title (an old browsed row from
        // EpisodeListView.loadBrowsePodcast plus a later subscribed row from
        // HomeViewModel.subscribeToPodcast). `.first` is unordered, so it can
        // return the stale browsed copy whose `podcastInfo.episodes` was never
        // refreshed — surfacing the old episode list when the header link
        // pushes a new EpisodeListView. Prefer the subscribed, freshest row.
        if let results = try? modelContext.fetch(descriptor), !results.isEmpty {
            let best = results.max { a, b in
                if a.isSubscribed != b.isSubscribed {
                    return !a.isSubscribed && b.isSubscribed
                }
                return a.lastUpdated < b.lastUpdated
            }
            if let best {
                cachedPodcastModel = best
                return
            }
        }
        let service = ApplePodcastService()
        if let results = try? await service.searchPodcasts(term: title, limit: 5),
           let match = results.first(where: {
               $0.collectionName.lowercased() == title.lowercased()
           }) ?? results.first {
            browseCollectionId = String(match.collectionId)
        }
    }
}
