import SwiftData
import SwiftUI

struct PodcastTranscriptManagementView: View {
  @Query(filter: #Predicate<PodcastInfoModel> { $0.isSubscribed == true })
  private var subscribedPodcasts: [PodcastInfoModel]

  @State private var podcastTranscriptCounts: [String: Int] = [:]
  @State private var isLoading = true
  @State private var deleteTarget: String?

  var body: some View {
    List {
      if isLoading {
        HStack {
          Spacer()
          ProgressView("Scanning transcripts...")
          Spacer()
        }
      } else if podcastTranscriptCounts.isEmpty {
        Text("No transcripts found")
          .foregroundStyle(.secondary)
      } else {
        ForEach(sortedPodcasts, id: \.self) { title in
          HStack {
            Image(systemName: "text.bubble")
              .foregroundStyle(.blue)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text(title)
                .font(.subheadline)
              Text("\(podcastTranscriptCounts[title] ?? 0) transcripts")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
          }
          .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
              deleteTarget = title
            }
          }
        }
      }
    }
    .navigationTitle("Manage Transcripts")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .task {
      await scanTranscripts()
    }
    .confirmationDialog(
      "Delete Transcripts",
      isPresented: Binding(
        get: { deleteTarget != nil },
        set: { if !$0 { deleteTarget = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Delete All Transcripts for \(deleteTarget ?? "")", role: .destructive) {
        if let target = deleteTarget {
          Task { await deleteTranscriptsForPodcast(target) }
        }
      }
    } message: {
      Text("This will delete all transcripts for this podcast. You can regenerate them later.")
    }
  }

  private var sortedPodcasts: [String] {
    podcastTranscriptCounts.keys.sorted()
  }

  private func scanTranscripts() async {
    isLoading = true
    let storage = FileStorageManager.shared
    var counts: [String: Int] = [:]

    for podcast in subscribedPodcasts {
      let title = podcast.podcastInfo.title
      var count = 0
      for episode in podcast.podcastInfo.episodes {
        if await storage.captionFileExists(for: episode.title, podcastTitle: title) {
          count += 1
        }
      }
      if count > 0 {
        counts[title] = count
      }
    }

    podcastTranscriptCounts = counts
    isLoading = false
  }

  private func deleteTranscriptsForPodcast(_ podcastTitle: String) async {
    let storage = FileStorageManager.shared
    guard let podcast = subscribedPodcasts.first(where: { $0.podcastInfo.title == podcastTitle }) else { return }

    for episode in podcast.podcastInfo.episodes {
      if await storage.captionFileExists(for: episode.title, podcastTitle: podcastTitle) {
        try? await storage.deleteCaptionFile(for: episode.title, podcastTitle: podcastTitle)
      }
    }

    podcastTranscriptCounts.removeValue(forKey: podcastTitle)
  }
}
