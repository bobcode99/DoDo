//
//  ShortcutsDebugView.swift
//  PodcastAnalyzer
//
//  Debug-only view to validate the SaveAnalysisResultIntent App Intent
//  end-to-end. Fires the intent locally and observes the notification
//  it posts so we can confirm the round-trip works without leaving the app.
//

import AppIntents
import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ShortcutsDebugView: View {
  @State private var service = ShortcutsAIService.shared
  @State private var events: [DebugEvent] = []
  @State private var testPayload: String = "Test analysis result from ShortcutsDebugView at \(Date().formatted(date: .omitted, time: .standard))."
  @State private var isFiring = false
  @State private var lastError: String?
  @State private var observerToken: NSObjectProtocol?

  var body: some View {
    List {
      fireIntentSection
      endToEndSection
      eventLogSection
      serviceStateSection
    }
    .navigationTitle("Shortcuts Debug")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear { startObserving() }
    .onDisappear { stopObserving() }
  }

  // MARK: - Sections

  @ViewBuilder
  private var fireIntentSection: some View {
    Section {
      TextField("Test payload", text: $testPayload, axis: .vertical)
        .lineLimit(3...8)
        .font(.system(.body, design: .monospaced))

      Button {
        fireIntentLocally()
      } label: {
        HStack {
          Image(systemName: "play.circle.fill")
            .foregroundStyle(.purple)
          Text("Run SaveAnalysisResultIntent")
          Spacer()
          if isFiring {
            ProgressView().scaleEffect(0.8)
          }
        }
      }
      .disabled(isFiring || testPayload.isEmpty)

      if let lastError {
        Text(lastError)
          .font(.caption)
          .foregroundStyle(.red)
      }
    } header: {
      Text("Fire Intent Locally")
    } footer: {
      Text("Invokes SaveAnalysisResultIntent.perform() in-process. If the App Intent is wired correctly it posts .shortcutsAnalysisCompleted, which both ShortcutsAIService and this view observe. Watch the event log below.")
    }
  }

  @ViewBuilder
  private var endToEndSection: some View {
    Section {
      Button {
        openShortcutsApp()
      } label: {
        HStack {
          Image(systemName: "square.on.square")
            .foregroundStyle(.blue)
          Text("Open Shortcuts App")
        }
      }
    } header: {
      Text("End-to-End Test")
    } footer: {
      Text("Edit your “\(service.shortcutName)” shortcut, add “Save Analysis Result” (provided by PodcastAnalyzer) as the final action, then run it. Successful results show up in the event log below.")
    }
  }

  @ViewBuilder
  private var eventLogSection: some View {
    Section {
      if events.isEmpty {
        Text("No notifications received yet")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(events) { event in
          eventRow(event)
        }
        Button("Clear", role: .destructive) {
          events.removeAll()
        }
      }
    } header: {
      Text("Event Log")
    } footer: {
      Text("Every .shortcutsAnalysisCompleted notification appears here with its payload preview.")
    }
  }

  @ViewBuilder
  private func eventRow(_ event: DebugEvent) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: event.icon)
          .foregroundStyle(event.color)
        Text(event.title)
          .font(.caption)
          .fontWeight(.semibold)
        Spacer()
        Text(event.timestamp.formatted(date: .omitted, time: .standard))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Text(event.preview)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(6)
    }
  }

  @ViewBuilder
  private var serviceStateSection: some View {
    Section {
      LabeledContent("Selected shortcut", value: service.shortcutName)
      LabeledContent("Is processing", value: service.isProcessing ? "Yes" : "No")
      if let last = service.lastResult, !last.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Last result (\(last.count) chars)")
            .font(.caption)
            .fontWeight(.semibold)
          Text(last.prefix(300))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(6)
        }
      }
      if let err = service.lastError, !err.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Last error")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.red)
          Text(err)
            .font(.caption2)
            .foregroundStyle(.red)
        }
      }
    } header: {
      Text("ShortcutsAIService State")
    }
  }

  // MARK: - Observation

  private func startObserving() {
    guard observerToken == nil else { return }
    observerToken = NotificationCenter.default.addObserver(
      forName: .shortcutsAnalysisCompleted,
      object: nil,
      queue: .main
    ) { notification in
      let result = (notification.userInfo?["result"] as? String) ?? "<no result>"
      let episodeURL = (notification.userInfo?["episodeURL"] as? String) ?? ""
      let type = (notification.userInfo?["analysisType"] as? String) ?? ""
      Task { @MainActor in
        let preview = "result \(result.count) chars • episodeURL=\(episodeURL.isEmpty ? "(empty)" : episodeURL) • type=\(type)\n\(result.prefix(200))"
        events.insert(
          DebugEvent(
            title: ".shortcutsAnalysisCompleted",
            preview: preview,
            timestamp: Date(),
            icon: "bell.fill",
            color: .green
          ),
          at: 0
        )
      }
    }
  }

  private func stopObserving() {
    if let token = observerToken {
      NotificationCenter.default.removeObserver(token)
      observerToken = nil
    }
  }

  // MARK: - Actions

  private func fireIntentLocally() {
    isFiring = true
    lastError = nil
    let payload = testPayload
    Task {
      do {
        let intent = SaveAnalysisResultIntent()
        intent.analysisResult = payload
        intent.episodeAudioURL = "debug://local-test"
        intent.analysisType = AnalysisTypeEntity(type: .summary)
        _ = try await intent.perform()
        await MainActor.run {
          events.insert(
            DebugEvent(
              title: "perform() completed",
              preview: "Fired with \(payload.count)-char payload. Notification should appear above this entry.",
              timestamp: Date(),
              icon: "checkmark.circle.fill",
              color: .blue
            ),
            at: 0
          )
          isFiring = false
        }
      } catch {
        await MainActor.run {
          lastError = error.localizedDescription
          isFiring = false
        }
      }
    }
  }

  private func openShortcutsApp() {
    guard let url = URL(string: "shortcuts://") else { return }
    #if os(iOS)
    UIApplication.shared.open(url)
    #else
    NSWorkspace.shared.open(url)
    #endif
  }
}

// MARK: - DebugEvent

private struct DebugEvent: Identifiable {
  let id = UUID()
  let title: String
  let preview: String
  let timestamp: Date
  let icon: String
  let color: Color
}

#Preview {
  NavigationStack {
    ShortcutsDebugView()
  }
}
