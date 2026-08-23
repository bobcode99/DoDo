//
//  AnalysisTabView.swift
//  PodcastAnalyzer
//
//  "Episode Analysis" tab of EpisodeAIAnalysisView: one-shot summary,
//  entities, highlights, quotes, and takeaways.
//

import SwiftUI

struct AnalysisTabView: View {
  let viewModel: EpisodeDetailViewModel
  @Bindable var uiState: AIAnalysisUIState
  @FocusState private var isFormatFieldFocused: Bool

  private let settings = AISettingsManager.shared

  private var canAnalyze: Bool {
    settings.hasConfiguredProvider && viewModel.hasTranscript
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      AIAnalysisTabHeader(
        title: "Episode Analysis",
        description: "One-shot analysis with summary, entities, highlights, quotes, and takeaways"
      )

      if viewModel.aiAnalysis.isStreaming && viewModel.aiAnalysis.currentStreamingType == .analysis {
        // Currently streaming — reset regenerating flag and show progress
        streamingResponseView
          .onAppear { uiState.isRegenerating = false }

      } else if uiState.isRegenerating, let result = viewModel.aiAnalysis.cloudAnalysisCache.analysis {
        // User tapped Regenerate — show hint editor above the existing result
        shortcutPickerRow
        formatHintField

        generateButton(
          title: "Run Analysis",
          action: {
            uiState.isRegenerating = false
            isFormatFieldFocused = false
            viewModel.aiAnalysis.generateCloudAnalysis(
              type: .analysis,
              formatHint: uiState.formatHintDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : uiState.formatHintDraft
            )
          }
        )

        Button("Cancel") {
          uiState.isRegenerating = false
          isFormatFieldFocused = false
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .foregroundStyle(.secondary)

        Divider()
          .padding(.vertical, 4)

        Text("Current Result")
          .font(.caption)
          .foregroundStyle(.secondary)

        AnalysisResultCardView(result: result, viewModel: viewModel, uiState: uiState)

      } else if case .error(let errorMsg) = viewModel.aiAnalysis.cloudAnalysisState,
                let result = viewModel.aiAnalysis.cloudAnalysisCache.analysis {
        // Regeneration failed — show inline warning + keep old result
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .font(.subheadline)
          VStack(alignment: .leading, spacing: 3) {
            Text("Analysis failed — showing previous result")
              .font(.caption)
              .fontWeight(.semibold)
              .foregroundStyle(.orange)
            Text(errorMsg)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))

        AnalysisResultCardView(result: result, viewModel: viewModel, uiState: uiState)

      } else if let result = viewModel.aiAnalysis.cloudAnalysisCache.analysis {
        // Normal completed state
        AnalysisResultCardView(result: result, viewModel: viewModel, uiState: uiState)

      } else {
        // Show analysis error prominently at the top so it's not missed
        if case .error(let errorMsg) = viewModel.aiAnalysis.cloudAnalysisState {
          analysisErrorBanner(message: errorMsg, isRetry: viewModel.aiAnalysis.cloudAnalysisCache.analysis == nil)
        }

        // Show progress indicator while analyzing (no previous result to show)
        if case .analyzing = viewModel.aiAnalysis.cloudAnalysisState {
          analysisStateView(for: viewModel.aiAnalysis.cloudAnalysisState, type: .analysis)
        } else {
          // Finished with nothing to show: name it, instead of silently
          // resetting to the Analyze button as if the run never happened.
          if case .completed = viewModel.aiAnalysis.cloudAnalysisState {
            emptyResponseBanner
          }

          // No result yet — show hint field + analyze button
          shortcutPickerRow
          formatHintField

          generateButton(
            title: "Analyze Episode",
            action: {
              isFormatFieldFocused = false
              viewModel.aiAnalysis.generateCloudAnalysis(
                type: .analysis,
                formatHint: uiState.formatHintDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  ? nil : uiState.formatHintDraft
              )
            }
          )
        }
      }
    }
  }

  // MARK: - Shortcut Picker Row

  /// Quick-switch picker shown only when Shortcuts provider is active with ≥2 saved names.
  @ViewBuilder
  private var shortcutPickerRow: some View {
    let service = ShortcutsAIService.shared
    if settings.selectedProvider == .applePCC, service.shortcutNames.count > 1 {
      HStack(spacing: 10) {
        Label("Shortcut", systemImage: "square.on.square")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)

        Spacer()

        Menu {
          ForEach(service.shortcutNames, id: \.self) { name in
            Button {
              service.shortcutName = name
            } label: {
              HStack {
                Text(name)
                if service.shortcutName == name {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
        } label: {
          HStack(spacing: 4) {
            Text(service.shortcutName)
              .font(.caption)
              .fontWeight(.medium)
            Image(systemName: "chevron.up.chevron.down")
              .font(.system(size: 10))
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Color.blue.opacity(0.1))
          .foregroundStyle(.blue)
          .clipShape(.rect(cornerRadius: 8))
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
      }
    }
  }

  // MARK: - Format Hint Field

  private var formatHintField: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label("Show Format (optional)", systemImage: "text.alignleft")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
        Spacer()
        if !uiState.formatHintDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Button("Save as default") {
            settings.saveFormatHint(uiState.formatHintDraft, for: viewModel.podcastTitle)
            uiState.formatHintSaved = true
            Task {
              try? await Task.sleep(for: .seconds(1.5))
              uiState.formatHintSaved = false
            }
          }
          .font(.caption)
          .foregroundStyle(uiState.formatHintSaved ? .green : .blue)
          #if os(macOS)
          .buttonStyle(.plain)
          #endif
        }
      }

      HStack(alignment: .top, spacing: 0) {
        TextField(
          "e.g. Starts with sponsor, then market news, guest interview, listener Q&A, closing",
          text: $uiState.formatHintDraft,
          axis: .vertical
        )
        .font(.caption)
        .lineLimit(2...4)
        .textFieldStyle(.plain)
        .focused($isFormatFieldFocused)

        // Dismiss keyboard button — only visible while the field is focused
        if isFormatFieldFocused {
          Button {
            isFormatFieldFocused = false
          } label: {
            Image(systemName: "keyboard.chevron.compact.down")
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(4)
          }
          #if os(macOS)
          .buttonStyle(.plain)
          #endif
        }
      }
      .padding(10)
      .background(Color.platformSystemGray6)
      .clipShape(.rect(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(isFormatFieldFocused ? AnyShapeStyle(.tint.opacity(0.5)) : AnyShapeStyle(Color.clear), lineWidth: 1)
      )
    }
  }

  /// Pair of buttons shown together: primary "Analyze" + secondary "Copy prompt".
  /// Stacked so the secondary action is discoverable instead of buried behind a long-press.
  private func generateButton(title: String, action: @escaping () -> Void) -> some View {
    VStack(spacing: 10) {
      Button(action: action) {
        HStack {
          Image(systemName: "sparkles")
          Text(title)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(canAnalyze ? Color.blue : Color.gray)
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 12))
      }
      .disabled(!canAnalyze)

      if viewModel.hasTranscript {
        copyPromptLink
      }
    }
  }

  /// Visible secondary action: opens the prompt preview sheet. Independent of
  /// `canAnalyze` (a configured provider isn't required) — the entire purpose is
  /// to let users paste the prompt into their own external LLM.
  private var copyPromptLink: some View {
    Button {
      uiState.showPromptPreview = true
    } label: {
      HStack(spacing: 6) {
        Image(systemName: uiState.promptCopied ? "checkmark.circle.fill" : "doc.on.doc")
        Text(uiState.promptCopied ? "Copied — paste into your LLM" : "Copy prompt for external LLM")
      }
      .font(.subheadline)
      .foregroundStyle(uiState.promptCopied ? .green : .blue)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background((uiState.promptCopied ? Color.green : Color.blue).opacity(0.1))
      .clipShape(.rect(cornerRadius: 10))
    }
    .buttonStyle(.plain)
  }

  // MARK: - In-Flight Affordances

  /// Elapsed time, ticking once a second. A slow model and a stalled request
  /// look identical without it.
  @ViewBuilder
  private var elapsedLabel: some View {
    if let startedAt = viewModel.aiAnalysis.analysisStartedAt {
      TimelineView(.periodic(from: startedAt, by: 1)) { context in
        Text(Formatters.formatPlaybackTime(max(0, context.date.timeIntervalSince(startedAt))))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
    }
  }

  /// Escape hatch from a running analysis. Keeps any previously saved result.
  private var stopButton: some View {
    Button(role: .destructive) {
      viewModel.aiAnalysis.cancelCloudAnalysis()
    } label: {
      Label("Stop", systemImage: "stop.circle")
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.1))
        .foregroundStyle(.red)
        .clipShape(.rect(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Streaming Response View

  private var streamingResponseView: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header with streaming indicator
      HStack {
        Image(systemName: "sparkles")
          .foregroundStyle(.blue)
          .symbolEffect(.pulse)
        Text("Generating...")
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundStyle(.blue)
        Spacer()
        elapsedLabel
        ProgressView()
          .scaleEffect(0.8)
      }

      // Streaming text content
      if !viewModel.aiAnalysis.streamingText.isEmpty {
        Text(viewModel.aiAnalysis.streamingText)
          .font(.body)
          .textSelection(.enabled)
          .animation(.easeInOut(duration: 0.1), value: viewModel.aiAnalysis.streamingText)
      } else {
        HStack {
          Text("Waiting for response...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      stopButton

      // Metadata
      HStack {
        ProviderIconLabel(provider: settings.selectedProvider, iconSize: 13)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Text(settings.currentModel)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if viewModel.hasTranscript {
        Button {
          uiState.showPromptPreview = true
        } label: {
          Label("Copy Prompt for External LLM", systemImage: "doc.on.doc")
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .foregroundStyle(.blue)
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
      }
    }
    .padding()
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.blue.opacity(0.05))
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
        )
    )
  }

  /// The run finished but produced nothing to persist — rare now that raw
  /// replies are kept, but a silent reset to the Analyze button reads as
  /// "nothing happened", which is the exact confusion this replaces.
  private var emptyResponseBanner: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "questionmark.circle.fill")
        .foregroundStyle(.orange)
        .font(.subheadline)
      VStack(alignment: .leading, spacing: 3) {
        Text("Finished, but the model returned nothing")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.orange)
        Text("Tap Analyze Episode to try again.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(Color.orange.opacity(0.1))
    .clipShape(.rect(cornerRadius: 8))
  }

  /// Prominent error banner with optional retry messaging.
  /// `isRetry` = false means there's no previous result, so label as "Analysis failed".
  private func analysisErrorBanner(message: String, isRetry: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.red)
          .font(.subheadline)

        VStack(alignment: .leading, spacing: 3) {
          Text(isRetry ? "Analysis failed" : "Regeneration failed")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.red)

          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 0)
      }

      Text("Fix the issue above and tap Analyze to retry.")
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(12)
    .background(Color.red.opacity(0.08))
    .clipShape(.rect(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
    )
  }

  private func analysisStateView(for state: AnalysisState, type: CloudAnalysisType? = nil) -> some View {
    Group {
      switch state {
      case .idle, .completed:
        EmptyView()

      case .analyzing(let progress, let message):
        // Only show progress on the tab that owns the current analysis
        if let type, let streamingType = viewModel.aiAnalysis.currentStreamingType, type != streamingType {
          EmptyView()
        } else {
          VStack(spacing: 12) {
            if progress < 0 {
              ProgressView()
                .scaleEffect(1.2)
            } else {
              ProgressView(value: progress)
                .progressViewStyle(.linear)
            }

            HStack(spacing: 8) {
              Image(systemName: "sparkles")
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)

              Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            }

            HStack(spacing: 8) {
              if progress >= 0 {
                Text("\(Int(progress * 100))% complete")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              elapsedLabel
            }

            stopButton
          }
          .padding()
          .background(Color.blue.opacity(0.05))
          .clipShape(.rect(cornerRadius: 12))
        }

      case .error(let message):
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text(message)
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
      }
    }
  }
}
