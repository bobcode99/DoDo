//
//  PromptPreviewSheet.swift
//  PodcastAnalyzer
//
//  Shows the assembled (system + user) prompt before copying. Lets the user
//  see exactly what would be sent to an LLM and copy it for use in external tools.
//

import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct PromptPreviewSheet: View {
  let podcastTitle: String
  let episodeTitle: String
  let podcastLanguage: String?
  let transcript: String
  let formatHint: String?
  let onCopied: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var didCopy = false
  @State private var systemPrompt: String = ""
  @State private var userPrompt: String = ""
  @State private var combined: String = ""
  @State private var isBuilding: Bool = true
  @State private var includeTimestamps: Bool = false
  @State private var transcriptOnly: Bool = false
  @State private var plainTextReply: Bool = false

  // SwiftUI `Text` lays out synchronously on the main thread; a 50–100 KB
  // monospaced prompt freezes the UI. Truncate the preview — copy carries the
  // full content.
  private static let previewCharLimit = 4_000

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text(episodeTitle)
              .font(.headline)
              .lineLimit(2)
            Text(podcastTitle)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          HStack(spacing: 12) {
            if isBuilding {
              Label("Building…", systemImage: "hourglass")
            } else {
              Label("\(combined.count) chars", systemImage: "textformat.size")
            }
            if formatHint != nil {
              Label("Custom format", systemImage: "text.append")
                .foregroundStyle(.blue)
            }
            if transcript.isEmpty {
              Label("No transcript", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)

          if !transcript.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Toggle(isOn: $includeTimestamps) {
                Label {
                  Text("Include timestamps")
                  Text("Prefix each line with [MM:SS] from the transcript")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } icon: {
                  Image(systemName: "clock")
                }
              }
              Toggle(isOn: $transcriptOnly) {
                Label {
                  Text("Transcript only")
                  Text("Copy just the transcript text, without the analysis instructions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } icon: {
                  Image(systemName: "text.alignleft")
                }
              }
              Toggle(isOn: $plainTextReply) {
                Label {
                  Text("Plain-text answer")
                  Text("Ask for a readable reply instead of app JSON — for chatting with an LLM about this episode")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } icon: {
                  Image(systemName: "text.bubble")
                }
              }
              .disabled(transcriptOnly)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.08))
            .clipShape(.rect(cornerRadius: 10))
          }

          if transcript.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Text("Heads up")
                .font(.caption.bold())
                .foregroundStyle(.orange)
              Text("This episode has no transcript yet, so the prompt below has no source text. Generate or fetch a transcript first to get a complete prompt.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1))
            .clipShape(.rect(cornerRadius: 10))
          }

          if isBuilding {
            HStack(spacing: 8) {
              ProgressView()
              Text("Preparing prompt preview…")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
          } else if transcriptOnly {
            promptSection(title: "Transcript", body: userPrompt)
          } else {
            promptSection(title: "System", body: systemPrompt)
            promptSection(title: "User", body: userPrompt)
          }
        }
        .padding()
        .padding(.bottom, 80)
      }
      .safeAreaInset(edge: .bottom) {
        Button(action: copy) {
          HStack {
            Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc.fill")
            Text(didCopy ? "Copied to Clipboard" : "Copy Prompt")
              .fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity)
          .padding()
          .background(isBuilding ? Color.gray : (didCopy ? Color.green : Color.blue))
          .foregroundStyle(.white)
          .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isBuilding)
        .padding()
        .background(.regularMaterial)
      }
      .navigationTitle("Prompt Preview")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task(id: transcript) {
        await buildPrompts()
      }
      .onChange(of: includeTimestamps) { _, _ in
        Task { await buildPrompts() }
      }
      .onChange(of: transcriptOnly) { _, _ in
        Task { await buildPrompts() }
      }
      .onChange(of: plainTextReply) { _, _ in
        Task { await buildPrompts() }
      }
    }
  }

  @ViewBuilder
  private func promptSection(title: String, body: String) -> some View {
    let truncated = body.count > Self.previewCharLimit
    let displayed: String = {
      guard truncated else { return body }
      let head = body.prefix(Self.previewCharLimit)
      let omitted = body.count - Self.previewCharLimit
      return "\(head)\n\n… [\(omitted) more characters — full prompt is copied to clipboard]"
    }()

    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title.uppercased())
          .font(.caption2.bold())
          .foregroundStyle(.secondary)
          .tracking(0.5)
        Spacer()
        if truncated {
          Text("preview truncated")
            .font(.caption2)
            .foregroundStyle(.orange)
        }
      }
      Text(displayed)
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.12))
        .clipShape(.rect(cornerRadius: 10))
    }
  }

  private func buildPrompts() async {
    isBuilding = true
    // Yield once so SwiftUI gets a chance to paint the sheet (with the
    // "Preparing…" spinner) before we run string work on the main actor.
    await Task.yield()

    let format: TranscriptFormatForAI = includeTimestamps ? .segmentBased : .sentenceBased

    if transcriptOnly {
      // No system/user wrapper — just the transcript body, optionally with timestamps.
      let formatted = format.formatTranscript(transcript)
      systemPrompt = ""
      userPrompt = formatted
      combined = formatted
    } else {
      let pair = CloudAIService.shared.buildPrompt(
        type: .analysis,
        transcript: transcript,
        episodeTitle: episodeTitle,
        podcastTitle: podcastTitle,
        podcastLanguage: podcastLanguage,
        formatHint: formatHint,
        transcriptFormatOverride: format,
        plainText: plainTextReply
      )
      systemPrompt = pair.system
      userPrompt = pair.user
      combined = "## System\n\(pair.system)\n\n## User\n\(pair.user)"
    }
    isBuilding = false
  }

  private func copy() {
    guard !combined.isEmpty else { return }

    #if os(iOS)
    UIPasteboard.general.string = combined
    #else
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(combined, forType: .string)
    #endif

    didCopy = true
    onCopied()

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      didCopy = false
    }
  }
}
