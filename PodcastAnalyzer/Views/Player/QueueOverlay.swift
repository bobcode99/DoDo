//
//  QueueOverlay.swift
//  PodcastAnalyzer
//
//  Queue overlay for the expanded player using closure/callback pattern.
//

import SwiftUI

struct QueueOverlay: View {
  let queue: [PlaybackEpisode]
  let onPlayItem: (Int) -> Void
  let onRemoveItem: (Int) -> Void
  let onMoveItems: (IndexSet, Int) -> Void
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      Button {
        onDismiss()
      } label: {
        Color.black.opacity(0.4)
          .ignoresSafeArea()
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss")

      VStack(spacing: 0) {
        // Header
        HStack {
          Text("Up Next")
            .font(.headline)
          Spacer()
          Button("Dismiss", systemImage: "xmark.circle.fill", action: onDismiss)
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(.secondary)
        }
        .padding()

        Divider()

        if queue.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "list.bullet")
              .font(.system(size: 40))
              .foregroundStyle(.secondary)
            Text("Queue is empty")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Text("Add episodes using 'Play Next'")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding()
        } else {
          List {
            ForEach(queue.enumerated(), id: \.element.id) { index, episode in
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(episode.title)
                    .font(.subheadline)
                    .lineLimit(1)
                  Text(episode.podcastTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()

                Button(action: { onPlayItem(index) }) {
                  Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(episode.title)")
              }
              .padding(.vertical, 4)
            }
            .onMove(perform: onMoveItems)
            .onDelete { offsets in
              for index in offsets.sorted(by: >) { onRemoveItem(index) }
            }
          }
          .listStyle(.plain)
          #if os(iOS)
          .environment(\.editMode, .constant(.active))
          #endif
        }
      }
      .frame(maxHeight: 400)
      .glassEffect(Glass.regular, in: .rect(cornerRadius: 16))
      .padding(.horizontal, 16)
    }
  }
}
