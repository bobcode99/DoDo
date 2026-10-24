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
      .accessibilityHidden(true)

      VStack(spacing: 0) {
        // Header
        HStack {
          Text("Up Next")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          Spacer()
          Button(action: onDismiss) {
            Label("Dismiss", systemImage: "xmark.circle.fill")
              .labelStyle(.iconOnly)
              .font(.title2)
              .foregroundStyle(.secondary)
              .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)

        Divider()

        if queue.isEmpty {
          ContentUnavailableView(
            "Queue is empty",
            systemImage: "list.bullet",
            description: Text("Add episodes using 'Play Next'")
          )
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
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play \(episode.title)")
              }
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
      .frame(maxWidth: 560, maxHeight: 400)
      .glassEffect(Glass.regular, in: .rect(cornerRadius: 16))
      .padding(.horizontal, 16)
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape, onDismiss)
  }
}
