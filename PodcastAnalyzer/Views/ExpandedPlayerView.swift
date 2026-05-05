//
//  ExpandedPlayerView.swift
//  PodcastAnalyzer
//
//  Redesigned to look like Apple Podcasts player
//

import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "ExpandedPlayerView")

#if os(iOS)
import MediaPlayer
import UIKit
#endif

struct ExpandedPlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var viewModel = ExpandedPlayerViewModel()
  @State private var showSpeedPicker = false
  @State private var showQueue = false
  @State private var showSleepTimerPicker = false

  // Scrubbing state for smooth slider interaction
  @State private var isScrubbing = false
  @State private var scrubbingProgress: Double = 0

  // Speed options matching Apple Podcasts
  private let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
  private let quickSpeeds: [Float] = [0.8, 1.0, 1.3, 1.5, 1.8, 2.0]

  @AppStorage("skipForwardInterval") private var skipForwardInterval: Int = 30
  @AppStorage("skipBackwardInterval") private var skipBackwardInterval: Int = 15

  // Navigation callbacks - dismiss sheet first, then navigate in parent
  var onNavigateToEpisodeDetail: ((PodcastEpisodeInfo, String, String?) -> Void)?
  var onNavigateToPodcast: ((PodcastInfoModel) -> Void)?

  var body: some View {
    NavigationStack {
      ZStack {
        // Background gradient
        LinearGradient(
            colors: [Color.gray.opacity(0.3), Color.platformBackground],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()

        ScrollView {
            VStack(spacing: 0) {
                // 1. Artwork & Info Group
                VStack(spacing: 0) {
                    artworkSection
                        .padding(.top, 16)

                    episodeInfoSection
                        .padding(.top, 24)
                }

                Spacer(minLength: 20)

                // 2. Playback Group (Progress + Controls + Volume)
                VStack(spacing: 32) {
                    progressSection
                        .padding(.horizontal, 32)

                    controlsSection

                    #if os(iOS)
                    // Volume slider (system MPVolumeView)
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

                // 3. Bottom Actions
                bottomActionsSection
                    .padding(.bottom, 40)
            }
            .containerRelativeFrame(.vertical, alignment: .center)
        }
        .blur(radius: showSpeedPicker || showQueue ? 3 : 0)

        // Speed picker overlay
        if showSpeedPicker {
          SpeedPickerOverlay(
            currentSpeed: viewModel.playbackSpeed,
            quickSpeeds: quickSpeeds,
            allSpeeds: playbackSpeeds,
            onSelectSpeed: { speed in
              viewModel.setPlaybackSpeed(speed)
              withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSpeedPicker = false
              }
            },
            onDismiss: {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSpeedPicker = false
              }
            }
          )
          .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        // Queue overlay
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

  // MARK: - Artwork Section
  private var artworkSection: some View {
    let baseSize: CGFloat = 280
    let playingScale: CGFloat = 1.08
    let isPlaying = viewModel.isPlaying

    return Group {
      if let imageURL = viewModel.imageURL {
        CachedAsyncImage(url: imageURL) { image in
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } placeholder: {
          artworkPlaceholder
        }
        .frame(width: baseSize, height: baseSize)
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: .black.opacity(isPlaying ? 0.4 : 0.25), radius: isPlaying ? 25 : 15, x: 0, y: isPlaying ? 12 : 8)
        .scaleEffect(isPlaying ? playingScale : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: isPlaying)
      } else {
        artworkPlaceholder
          .frame(width: baseSize, height: baseSize)
          .clipShape(.rect(cornerRadius: 16))
          .scaleEffect(isPlaying ? playingScale : 1.0)
          .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: isPlaying)
      }
    }
  }

  private var artworkPlaceholder: some View {
    Color.gray.opacity(0.3)
      .overlay(
        Image(systemName: "music.note")
          .font(.system(size: 60))
          .foregroundStyle(.white.opacity(0.5))
      )
  }

  // MARK: - Episode Info Section
  private var episodeInfoSection: some View {
    VStack(spacing: 12) {
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .center, spacing: 4) {
          Text(viewModel.episodeTitle)
            .font(.title3)
            .fontWeight(.bold)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)

          Button(action: { navigateToPodcast() }) {
            Text(viewModel.podcastTitle)
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundStyle(.blue)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.leading, 44)

        Menu {
          ellipsisMenuContent
        } label: {
          Image(systemName: "ellipsis.circle.fill")
            .font(.system(size: 28))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
        }
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
      }
      .padding(.horizontal, 20)

      if let date = viewModel.episodeDate {
        Text(date.formatted(date: .abbreviated, time: .omitted))
          .font(.caption2)
          .fontWeight(.bold)
          .foregroundStyle(.secondary)
          .textCase(.uppercase)
      }
    }
  }

  // MARK: - Ellipsis Menu Content (Apple Podcasts Style)
  @ViewBuilder
  private var ellipsisMenuContent: some View {
    Section {
      Button(action: { viewModel.playNextCurrentEpisode() }) {
        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
      }

      Button(action: { viewModel.shareEpisode() }) {
        Label("Share Episode...", systemImage: "square.and.arrow.up")
      }
    }

    Section {
      Button(action: { viewModel.toggleStar() }) {
        Label(
          viewModel.isStarred ? "Unstar Episode" : "Star Episode",
          systemImage: viewModel.isStarred ? "star.fill" : "star"
        )
      }

      if viewModel.hasLocalAudio {
        Button(role: .destructive, action: { viewModel.deleteDownload() }) {
          Label("Remove Download", systemImage: "minus.circle")
        }
      } else {
        Button(action: { viewModel.startDownload() }) {
          Label("Download Episode", systemImage: "arrow.down.circle")
        }
      }
    }

    Section {
      Button(action: { navigateToEpisodeDetail() }) {
        Label("View Episode Description", systemImage: "doc.text")
      }

      Button(action: { navigateToPodcast() }) {
        Label("Go to Show", systemImage: "square.stack")
      }
    }

  }

  // MARK: - Progress Section
  private var progressSection: some View {
    let displayProgress = isScrubbing ? scrubbingProgress : viewModel.progress
    let displayCurrentTime = isScrubbing ? scrubbingProgress * viewModel.duration : viewModel.currentTime
    let displayRemainingTime = viewModel.duration - displayCurrentTime

    return VStack(spacing: 8) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 6)

          Capsule()
            .fill(Color.primary)
            .frame(
              width: geometry.size.width * CGFloat(displayProgress),
              height: 6
            )
            .animation(isScrubbing ? nil : .linear(duration: 0.1), value: displayProgress)

          Circle()
            .fill(Color.primary)
            .frame(width: isScrubbing ? 18 : 14, height: isScrubbing ? 18 : 14)
            .offset(
              x: max(
                0,
                min(geometry.size.width * CGFloat(displayProgress) - (isScrubbing ? 9 : 7), geometry.size.width - (isScrubbing ? 18 : 14))
              )
            )
            .animation(isScrubbing ? nil : .easeOut(duration: 0.15), value: displayProgress)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isScrubbing)
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              guard !viewModel.isDurationLoading else { return }
              if !isScrubbing {
                withAnimation(.easeOut(duration: 0.1)) {
                  isScrubbing = true
                }
                scrubbingProgress = viewModel.progress
              }
              let progress = value.location.x / geometry.size.width
              scrubbingProgress = min(max(0, progress), 1)
            }
            .onEnded { value in
              guard !viewModel.isDurationLoading else { return }
              let progress = value.location.x / geometry.size.width
              let finalProgress = min(max(0, progress), 1)
              viewModel.seekToProgress(finalProgress)
              withAnimation(.easeOut(duration: 0.2)) {
                isScrubbing = false
              }
            }
        )
        .opacity(viewModel.isDurationLoading ? 0.5 : 1.0)
      }
      .frame(height: 18)

      HStack {
        Text(Formatters.formatPlaybackTime(displayCurrentTime))
          .font(.caption)
          .foregroundStyle(isScrubbing ? .primary : .secondary)
          .monospacedDigit()
          .animation(.easeOut(duration: 0.15), value: isScrubbing)

        Spacer()

        Text("-" + Formatters.formatPlaybackTime(displayRemainingTime))
          .font(.caption)
          .foregroundStyle(isScrubbing ? .primary : .secondary)
          .monospacedDigit()
          .animation(.easeOut(duration: 0.15), value: isScrubbing)
      }
    }
  }

  // MARK: - Controls Section
  private var controlsSection: some View {
    HStack(spacing: 0) {
      Button(action: openSpeedPicker) {
        Text(Formatters.formatSpeed(viewModel.playbackSpeed))
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(.primary)
          .frame(width: 48, height: 48)
          .glassEffect(.regular, in: .circle)
      }
      .frame(width: 56, height: 56)
      .contentShape(Rectangle())

      Spacer()

      HStack(spacing: 28) {
        Button(action: { viewModel.skipBackward() }) {
          Image(systemName: "gobackward.\(skipBackwardInterval)")
            .font(.system(size: 32))
            .foregroundStyle(.primary)
        }
        .frame(width: 60)
        .accessibilityLabel("Skip back \(skipBackwardInterval) seconds")

        Button(action: { viewModel.togglePlayPause() }) {
          Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 72))
            .foregroundStyle(.primary)
        }
        .frame(width: 80)
        .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

        Button(action: { viewModel.skipForward() }) {
          Image(systemName: "goforward.\(skipForwardInterval)")
            .font(.system(size: 32))
            .foregroundStyle(.primary)
        }
        .frame(width: 60)
        .accessibilityLabel("Skip forward \(skipForwardInterval) seconds")
      }

      Spacer()

      // Sleep timer button
      Menu {
        ForEach(SleepTimerOption.allCases, id: \.self) { option in
          Button(action: { viewModel.setSleepTimer(option) }) {
            HStack {
              Label(option.displayName, systemImage: option.systemImage)
              if viewModel.sleepTimerOption == option {
                Spacer()
                Image(systemName: "checkmark")
              }
            }
          }
        }
      } label: {
        Group {
          if viewModel.isSleepTimerActive {
            if viewModel.sleepTimerOption == .endOfEpisode {
              Image(systemName: "stop.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
            } else {
              Text(viewModel.sleepTimerRemainingFormatted)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
            }
          } else {
            Image(systemName: "moon.zzz")
              .font(.system(size: 22))
              .foregroundStyle(.primary)
          }
        }
        .frame(width: 48, height: 48)
        .glassEffect(viewModel.isSleepTimerActive ? .regular.tint(.blue) : .regular, in: .circle)
        .frame(width: 56, height: 56)
        .contentShape(Rectangle())
      }
    }
    .padding(.horizontal, 24)
  }

  // MARK: - Bottom Actions Section
  private var bottomActionsSection: some View {
    HStack {
      AirPlayButton()
        .frame(width: 44, height: 44)

      Spacer()

      Button(action: { navigateToEpisodeDetail() }) {
        HStack(spacing: 4) {
          Image(systemName: "text.bubble")
          Text("Detail")
        }
        .font(.subheadline)
        .foregroundStyle(.blue)
      }

      Spacer()

      Button(action: openQueue) {
        HStack(spacing: 4) {
          Image(systemName: "list.bullet")
          if !viewModel.queue.isEmpty {
            Text("\(viewModel.queue.count)")
              .font(.caption)
              .fontWeight(.medium)
          }
        }
        .font(.title3)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 40)
  }

  // MARK: - Action Helpers

  private func openSpeedPicker() {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      showSpeedPicker = true
    }
  }

  private func openQueue() {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      showQueue = true
    }
  }

  // MARK: - Navigation Helpers

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
    dismiss()
    onNavigateToEpisodeDetail?(episodeInfo, episode.podcastTitle, episode.imageURL)
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

// MARK: - Transcript Full Screen View

struct TranscriptFullScreenView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var viewModel: ExpandedPlayerViewModel
  @AppStorage("skipForwardInterval") private var skipForwardInterval: Int = 30
  @AppStorage("skipBackwardInterval") private var skipBackwardInterval: Int = 15

  private var toolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
    return .topBarTrailing
    #else
    return .confirmationAction
    #endif
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        miniPlayerBar
          .padding(.horizontal, 16)
          .padding(.top, 10)
          .padding(.bottom, 8)

        Divider()

        FullTranscriptContent(
          sentences: viewModel.groupedSentences,
          currentTime: viewModel.isPlaying ? viewModel.currentTime : nil,
          searchQuery: $viewModel.transcriptSearchQuery,
          onSegmentTap: { segment in
            viewModel.seekToSegment(segment)
          }
        )
      }
      .navigationTitle("Transcript")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: toolbarPlacement) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }

  private var miniPlayerBar: some View {
    HStack(spacing: 12) {
      if let imageURL = viewModel.imageURL {
        CachedAsyncImage(url: imageURL) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          Color.gray.opacity(0.3)
        }
        .frame(width: 44, height: 44)
        .clipShape(.rect(cornerRadius: 6))
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(viewModel.episodeTitle)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)
        Text(viewModel.currentTimeString)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      HStack(spacing: 16) {
        Button(action: { viewModel.skipBackward() }) {
          Image(systemName: "gobackward.\(skipBackwardInterval)")
            .font(.system(size: 20))
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Skip back \(skipBackwardInterval) seconds")

        Button(action: { viewModel.togglePlayPause() }) {
          Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 24))
            .foregroundStyle(.primary)
        }
        .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

        Button(action: { viewModel.skipForward() }) {
          Image(systemName: "goforward.\(skipForwardInterval)")
            .font(.system(size: 20))
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Skip forward \(skipForwardInterval) seconds")
      }
    }
    .padding(12)
    .glassEffect(.regular, in: .rect(cornerRadius: 12))
  }
}

// MARK: - System Volume Slider

#if os(iOS)
/// Wraps MPVolumeView for system volume control in SwiftUI.
/// Route button is hidden — AirPlayButton (AVRoutePickerView) is used separately.
struct SystemVolumeSlider: UIViewRepresentable {
  func makeUIView(context: Context) -> MPVolumeView {
    MPVolumeView(frame: .zero)
  }

  func updateUIView(_ uiView: MPVolumeView, context: Context) {
    // Hide the route button subview (avoids deprecated showsRouteButton API)
    for subview in uiView.subviews where subview is UIButton {
      subview.isHidden = true
    }
  }
}
#endif

// MARK: - Preview

#Preview {
  ExpandedPlayerView()
}
