//
//  MacExpandedPlayerView.swift
//  PodcastAnalyzer
//
//  Full-window expanded player — Apple Podcasts style two-column layout
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacExpandedPlayerView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var viewModel = ExpandedPlayerViewModel()
  @State private var isDraggingProgress = false
  @State private var dragProgress: Double = 0

  var body: some View {
    ZStack {
      Color(.clear)
        .background(.background)
        .ignoresSafeArea()

      HStack(spacing: 0) {
        // Left panel — artwork + controls
        leftPanel
          .frame(maxWidth: .infinity)
          .padding(32)

        Divider()

        // Right panel — queue
        rightPanel
          .frame(width: 340)
      }
    }
    .frame(minWidth: 800, minHeight: 560)
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

  // MARK: - Left Panel

  private var leftPanel: some View {
    VStack(spacing: 0) {
      // Top toolbar
      HStack {
        Button(action: { dismiss() }) {
          Image(systemName: "chevron.down")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
        .help("Close player")

        Spacer()

        // More menu
        if viewModel.currentEpisode != nil {
          moreMenu
        }
      }

      Spacer()

      // Artwork
      if let episode = viewModel.currentEpisode {
        CachedArtworkImage(urlString: episode.imageURL, size: 280, cornerRadius: 16)
          .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
      }

      // Episode info
      VStack(spacing: 6) {
        if let date = viewModel.episodeDate {
          Text(date, format: .dateTime.month(.wide).day().year())
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text(viewModel.episodeTitle)
          .font(.title3)
          .bold()
          .lineLimit(2)
          .multilineTextAlignment(.center)

        Text(viewModel.podcastTitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.top, 20)

      // Progress
      progressSection
        .padding(.top, 16)
        .padding(.horizontal, 20)

      // Playback controls (shared with iOS via PlayerControlsView)
      PlayerControlsView(viewModel: viewModel, style: .expanded)
        .padding(.top, 20)

      Spacer()
    }
  }

  // MARK: - Progress Section

  private var progressSection: some View {
    VStack(spacing: 6) {
      GeometryReader { geometry in
        let currentProgress = isDraggingProgress ? dragProgress : viewModel.progress

        ZStack(alignment: .leading) {
          // Track
          Capsule()
            .fill(Color.gray.opacity(0.25))
            .frame(height: 4)

          // Fill
          Capsule()
            .fill(Color.accentColor)
            .frame(width: max(0, geometry.size.width * currentProgress), height: 4)
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              isDraggingProgress = true
              dragProgress = max(0, min(1, value.location.x / geometry.size.width))
            }
            .onEnded { value in
              let finalProgress = max(0, min(1, value.location.x / geometry.size.width))
              viewModel.seekToProgress(finalProgress)
              isDraggingProgress = false
            }
        )
      }
      .frame(height: 4)

      HStack {
        Text(viewModel.currentTimeString)
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()

        Spacer()

        Text(viewModel.remainingTimeString)
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
  }

  // MARK: - More Menu

  private var moreMenu: some View {
    Menu {
      Button(action: viewModel.toggleStar) {
        Label(
          viewModel.isStarred ? "Unsave" : "Save",
          systemImage: viewModel.isStarred ? "star.fill" : "star"
        )
      }

      Button(action: viewModel.shareEpisode) {
        Label("Share Episode", systemImage: "square.and.arrow.up")
      }
    } label: {
      Image(systemName: "ellipsis.circle")
        .font(.title3)
        .foregroundStyle(.secondary)
    }
    .menuStyle(.borderlessButton)
    .frame(width: 32)
  }

  // MARK: - Right Panel (Queue)

  private var rightPanel: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Continue Playing")
          .font(.headline)
        Spacer()
        Text("\(viewModel.queue.count)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      if viewModel.queue.isEmpty {
        ContentUnavailableView(
          "Queue Empty",
          systemImage: "list.bullet",
          description: Text("Episodes you add to queue will appear here")
        )
      } else {
        List {
          ForEach(viewModel.queue.enumerated().map { $0 }, id: \.element.id) { index, episode in
            MacQueueRow(episode: episode)
              .contentShape(Rectangle())
              .onTapGesture {
                viewModel.skipToQueueItem(at: index)
              }
              .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                  viewModel.removeFromQueue(at: index)
                } label: {
                  Label("Remove", systemImage: "trash")
                }
              }
          }
          .onMove(perform: viewModel.moveInQueue)
        }
        .listStyle(.plain)
      }
    }
  }
}

// MARK: - Queue Row

private struct MacQueueRow: View {
  let episode: PlaybackEpisode

  var body: some View {
    HStack(spacing: 12) {
      CachedArtworkImage(urlString: episode.imageURL, size: 44, cornerRadius: 6)

      VStack(alignment: .leading, spacing: 2) {
        Text(episode.title)
          .font(.subheadline)
          .lineLimit(1)

        HStack(spacing: 4) {
          if let date = episode.pubDate {
            Text(date, format: .dateTime.month().day())
          }
          if let dur = episode.duration {
            Text("·")
            Text(Formatters.formatPlaybackTime(TimeInterval(dur)))
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      Image(systemName: "line.3.horizontal")
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
  }
}

#Preview {
  MacExpandedPlayerView()
    .frame(width: 900, height: 600)
}

#endif

