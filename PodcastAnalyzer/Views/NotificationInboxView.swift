//
//  NotificationInboxView.swift
//  PodcastAnalyzer
//
//  In-app inbox for new-episode notifications: the system banner is easy to
//  miss/dismiss, so every notified episode is also recorded here. The app icon
//  badge mirrors this inbox's unread count — opening the inbox clears both.
//

import SwiftUI
import UserNotifications

// MARK: - Store

@MainActor
@Observable
final class NotificationInbox {
  static let shared = NotificationInbox()

  struct Item: Codable, Identifiable, Equatable {
    var id = UUID()
    let date: Date
    let podcastTitle: String
    let episodeTitle: String
    let audioURL: String
    let imageURL: String
    var isRead = false
  }

  private(set) var items: [Item] = []
  var unreadCount: Int { items.count(where: { !$0.isRead }) }

  private static let storageKey = "notificationInboxItems"
  private static let capacity = 50  // ponytail: fixed cap; page it if anyone hoards more

  private init() {
    if let data = UserDefaults.standard.data(forKey: Self.storageKey),
       let decoded = try? JSONDecoder().decode([Item].self, from: data) {
      items = decoded
    }
  }

  func add(podcastTitle: String, episodeTitle: String, audioURL: String, imageURL: String) {
    items.insert(
      Item(date: Date(), podcastTitle: podcastTitle, episodeTitle: episodeTitle,
           audioURL: audioURL, imageURL: imageURL),
      at: 0
    )
    if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
    save()
    syncBadge()
  }

  func markAllRead() {
    guard unreadCount > 0 else { return }
    for index in items.indices { items[index].isRead = true }
    save()
    syncBadge()
  }

  func clear() {
    items.removeAll()
    save()
    syncBadge()
  }

  /// Make the app icon badge mirror the unread count. Also the fix for badges
  /// stuck at a stale number: nothing ever cleared them before this existed.
  func syncBadge() {
    UNUserNotificationCenter.current().setBadgeCount(unreadCount)
  }

  private func save() {
    if let data = try? JSONEncoder().encode(items) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }
}

// MARK: - View

struct NotificationInboxView: View {
  @Environment(\.dismiss) private var dismiss
  private var inbox = NotificationInbox.shared

  var body: some View {
    NavigationStack {
      Group {
        if inbox.items.isEmpty {
          ContentUnavailableView {
            Label("No Notifications", systemImage: "bell.slash")
          } description: {
            Text("New episodes from your subscriptions will show up here.")
          }
        } else {
          List {
            ForEach(inbox.items) { item in
              Button {
                NotificationNavigationManager.shared.navigateToEpisodeDetail(
                  title: item.episodeTitle,
                  podcastTitle: item.podcastTitle,
                  audioURL: item.audioURL,
                  imageURL: item.imageURL
                )
                dismiss()
              } label: {
                HStack(alignment: .top, spacing: 10) {
                  Circle()
                    .fill(item.isRead ? Color.clear : Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(item.podcastTitle)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                    Text(item.episodeTitle)
                      .font(.subheadline)
                      .lineLimit(2)
                    Text(item.date, format: .relative(presentation: .named))
                      .font(.caption2)
                      .foregroundStyle(.tertiary)
                  }
                }
              }
              .buttonStyle(.plain)
            }
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Notifications")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        if !inbox.items.isEmpty {
          ToolbarItem(placement: .destructiveAction) {
            Button("Clear") { inbox.clear() }
          }
        }
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .onAppear { inbox.markAllRead() }
    }
  }
}

#Preview {
  NotificationInboxView()
}
