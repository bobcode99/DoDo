//
//  EpisodeAIAnalysisView.swift
//  PodcastAnalyzer
//
//  Cloud-based AI analysis view using user-provided API keys (BYOK)
//  Uses CloudAIService for transcript analysis
//

import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// View for cloud-based AI transcript analysis
struct EpisodeAIAnalysisView: View {
  private var toolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
    return .topBarTrailing
    #else
    return .primaryAction
    #endif
  }
  @Bindable var viewModel: EpisodeDetailViewModel
  var embedsOwnScroll: Bool = true  // When false, parent provides scrolling (for embedded mode)
  @Binding var isHeaderVisible: Bool
  @Binding var lastScrollOffset: CGFloat
  @Binding var isUserScrolling: Bool
  @Binding var scrollToTopTrigger: Bool

  @State private var selectedTab: CloudAnalysisTab = .analysis
  @State private var questionInput: String = ""
  @State private var showSettingsSheet = false
  @State private var formatHintDraft: String = ""
  @State private var formatHintSaved: Bool = false
  @State private var isRegenerating: Bool = false
  @State private var promptCopied: Bool = false
  @State private var showPromptPreview: Bool = false
  @FocusState private var isFormatFieldFocused: Bool

  private let settings = AISettingsManager.shared

  var body: some View {
    VStack(spacing: 0) {
      // Configuration banner
      configurationBanner

      // Tab selection
      ScrollView(.horizontal) {
        HStack(spacing: 12) {
          ForEach(CloudAnalysisTab.allCases) { tab in
            tabButton(for: tab)
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
      }
      .scrollIndicators(.hidden)

      Divider()

      // Content area - conditionally wrap in ScrollView based on embedsOwnScroll
      if embedsOwnScroll {
        ScrollViewReader { proxy in
          ScrollView {
            Color.clear.frame(height: 0).id("aiTop")
            aiContentView
          }
          .trackScrollForHeaderCollapse(
              isHeaderVisible: $isHeaderVisible,
              lastOffset: $lastScrollOffset,
              isUserScrolling: isUserScrolling
          )
          .onScrollPhaseChange { _, newPhase in
              isUserScrolling = newPhase == .interacting || newPhase == .decelerating
          }
          .onChange(of: scrollToTopTrigger) { _, _ in
              withAnimation(.easeInOut(duration: 0.3)) {
                  proxy.scrollTo("aiTop", anchor: .top)
              }
              isHeaderVisible = true
          }
        }
      } else {
        aiContentView
      }
    }
    .onAppear {
      formatHintDraft = settings.formatHint(for: viewModel.podcastTitle)
      isRegenerating = false
    }
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: toolbarPlacement) {
        Button(action: { showSettingsSheet = true }) {
          Image(systemName: "gear")
        }
      }
    }
    .sheet(isPresented: $showSettingsSheet) {
      NavigationStack {
        AISettingsView()
          #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
          #endif
          .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
              Button("Done") { showSettingsSheet = false }
            }
          }
      }
    }
    .sheet(isPresented: $showPromptPreview) {
      PromptPreviewSheet(
        podcastTitle: viewModel.podcastTitle,
        episodeTitle: viewModel.episode.title,
        podcastLanguage: viewModel.podcastLanguage,
        transcript: viewModel.transcriptText,
        formatHint: formatHintDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : formatHintDraft,
        onCopied: {
          promptCopied = true
          Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            promptCopied = false
          }
        }
      )
    }
  }

  // MARK: - AI Content View (shared between scrolled and non-scrolled modes)

  private var aiContentView: some View {
    VStack(alignment: .leading, spacing: 16) {
      switch selectedTab {
      case .analysis: analysisTab
      case .askQuestion: questionAnswerTab
      }
    }
    .padding()
  }

  // MARK: - Configuration Banner

  @ViewBuilder
  private var configurationBanner: some View {
    if !settings.hasConfiguredProvider {
      // No API key configured
      HStack {
        Image(systemName: "key.fill")
          .foregroundStyle(.orange)

        VStack(alignment: .leading, spacing: 2) {
          Text("API Key Required")
            .font(.subheadline)
            .fontWeight(.medium)
          Text("Configure your cloud AI provider to analyze transcripts")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button("Setup") {
          showSettingsSheet = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(minHeight: 60)
      .background(Color.orange.opacity(0.1))
    } else if !viewModel.hasTranscript {
      // No transcript available
      HStack {
        Image(systemName: "doc.text")
          .foregroundStyle(.blue)

        Text("Generate a transcript first to enable AI analysis")
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(minHeight: 60)
      .background(Color.blue.opacity(0.1))
    }
  }

  // MARK: - Tab Button

  private func tabButton(for tab: CloudAnalysisTab) -> some View {
    Button {
      selectedTab = tab
    } label: {
      HStack(spacing: 6) {
        Image(systemName: tab.icon)
          .font(.system(size: 12))
        Text(tab.rawValue)
          .font(.subheadline)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(selectedTab == tab ? Color.accentColor : Color.clear)
      )
      .foregroundStyle(selectedTab == tab ? .white : .primary)
    }
    #if os(macOS)
    .buttonStyle(.plain)      // 🔑 THIS fixes the weird macOS behavior
    #endif
  }


  // MARK: - Analysis Tab

  private var analysisTab: some View {
    VStack(alignment: .leading, spacing: 16) {
      tabHeader(
        title: "Episode Analysis",
        description: "One-shot analysis with summary, entities, highlights, quotes, and takeaways"
      )

      if viewModel.isStreaming && viewModel.currentStreamingType == .analysis {
        // Currently streaming — reset regenerating flag and show progress
        streamingResponseView
          .onAppear { isRegenerating = false }

      } else if isRegenerating, let result = viewModel.cloudAnalysisCache.analysis {
        // User tapped Regenerate — show hint editor above the existing result
        shortcutPickerRow
        formatHintField

        generateButton(
          title: "Run Analysis",
          action: {
            isRegenerating = false
            isFormatFieldFocused = false
            viewModel.generateCloudAnalysis(
              type: .analysis,
              formatHint: formatHintDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : formatHintDraft
            )
          }
        )

        Button("Cancel") {
          isRegenerating = false
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

        analysisResultCard(result)

      } else if case .error(let errorMsg) = viewModel.cloudAnalysisState,
                let result = viewModel.cloudAnalysisCache.analysis {
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

        analysisResultCard(result)

      } else if let result = viewModel.cloudAnalysisCache.analysis {
        // Normal completed state
        analysisResultCard(result)

      } else {
        // Show analysis error prominently at the top so it's not missed
        if case .error(let errorMsg) = viewModel.cloudAnalysisState {
          analysisErrorBanner(message: errorMsg, isRetry: viewModel.cloudAnalysisCache.analysis == nil)
        }

        // Show progress indicator while analyzing (no previous result to show)
        if case .analyzing = viewModel.cloudAnalysisState {
          analysisStateView(for: viewModel.cloudAnalysisState, type: .analysis)
        } else {
          // No result yet — show hint field + analyze button
          shortcutPickerRow
          formatHintField

          generateButton(
            title: "Analyze Episode",
            action: {
              isFormatFieldFocused = false
              viewModel.generateCloudAnalysis(
                type: .analysis,
                formatHint: formatHintDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  ? nil : formatHintDraft
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
        if !formatHintDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Button("Save as default") {
            settings.saveFormatHint(formatHintDraft, for: viewModel.podcastTitle)
            formatHintSaved = true
            Task {
              try? await Task.sleep(for: .seconds(1.5))
              formatHintSaved = false
            }
          }
          .font(.caption)
          .foregroundStyle(formatHintSaved ? .green : .blue)
          #if os(macOS)
          .buttonStyle(.plain)
          #endif
        }
      }

      HStack(alignment: .top, spacing: 0) {
        TextField(
          "e.g. Starts with sponsor, then market news, guest interview, listener Q&A, closing",
          text: $formatHintDraft,
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
          .strokeBorder(isFormatFieldFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
      )
    }
  }

  // MARK: - Q&A Tab

  private var questionAnswerTab: some View {
    VStack(alignment: .leading, spacing: 16) {
      tabHeader(
        title: "Ask Questions",
        description: "Ask any question about the episode content"
      )

      // Question input with X button and Enter to send
      HStack(spacing: 8) {
        HStack {
          TextField("Enter your question...", text: $questionInput)
            .textFieldStyle(.plain)
            .onSubmit {
              submitQuestion()
            }

          // X button to clear input
          if !questionInput.isEmpty {
            Button(action: {
              questionInput = ""
              #if os(iOS)
              // Hide keyboard when clearing
              UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
              #endif
            }) {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.platformSystemGray6)
        .clipShape(.rect(cornerRadius: 10))

        Button(action: submitQuestion) {
          Image(systemName: "paperplane.fill")
            .font(.system(size: 18))
        }
        .disabled(
          questionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canAnalyze)
      }
      #if os(iOS)
      .submitLabel(.send)
      #endif

      // Q&A error — show above history so it's immediately visible
      if case .error(let errorMsg) = viewModel.cloudQuestionState {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.red)
            .font(.subheadline)
          VStack(alignment: .leading, spacing: 3) {
            Text("Question failed")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.red)
            Text(errorMsg)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
        )
      }

      // Progress indicator while waiting for answer
      if case .analyzing = viewModel.cloudQuestionState {
        analysisStateView(for: viewModel.cloudQuestionState)
      }

      // Previous Q&A history
      if !viewModel.cloudAnalysisCache.questionAnswers.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("Previous Questions")
            .font(.headline)

          ForEach(
            Array(viewModel.cloudAnalysisCache.questionAnswers.enumerated().reversed()),
            id: \.offset
          ) { _, qa in
            qaResultCard(qa)
          }
        }
      }
    }
  }

  // MARK: - Helper Views

  private func tabHeader(title: String, description: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.title2)
        .bold()
      Text(description)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var canAnalyze: Bool {
    settings.hasConfiguredProvider && viewModel.hasTranscript
  }

  private func submitQuestion() {
    let trimmed = questionInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, canAnalyze else { return }
    viewModel.askCloudQuestion(questionInput)
    questionInput = ""
    #if os(iOS)
    // Hide keyboard after submitting
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
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
      showPromptPreview = true
    } label: {
      HStack(spacing: 6) {
        Image(systemName: promptCopied ? "checkmark.circle.fill" : "doc.on.doc")
        Text(promptCopied ? "Copied — paste into your LLM" : "Copy prompt for external LLM")
      }
      .font(.subheadline)
      .foregroundStyle(promptCopied ? .green : .blue)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background((promptCopied ? Color.green : Color.blue).opacity(0.1))
      .clipShape(.rect(cornerRadius: 10))
    }
    .buttonStyle(.plain)
  }

  private func analysisResultCard(_ result: CloudAnalysisResult) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      // Show warning if JSON parsing failed
      if let warning = result.jsonParseWarning {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          VStack(alignment: .leading, spacing: 2) {
            Text("Response Format Warning")
              .font(.caption)
              .fontWeight(.semibold)
              .foregroundStyle(.orange)
            Text(warning)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
      }

      // Structured content based on type
      switch result.type {
      case .analysis:
        fullAnalysisResultView(result)
      }

      Divider()

      // Metadata
      HStack {
        Label(result.provider.displayName, systemImage: result.provider.iconName)
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        Text(result.model)
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Share & Regenerate buttons
      HStack {
        if let parsed = result.parsedAnalysis {
          Button(action: {
            let text = parsed.formatAsShareableText(
              episodeTitle: viewModel.episode.title,
              podcastTitle: viewModel.podcastTitle
            )
            PlatformShareSheet.share(items: [text])
          }) {
            Label("Share", systemImage: "square.and.arrow.up")
              .font(.caption)
          }
          .buttonStyle(.bordered)
        }

        Button(action: {
          isRegenerating = true
        }) {
          Label("Regenerate", systemImage: "arrow.clockwise")
            .font(.caption)
        }
        .buttonStyle(.bordered)
      }
    }
    .padding()
    .background(Color.platformSystemGray6)
    .clipShape(.rect(cornerRadius: 12))
  }

  // MARK: - Structured Result Views

  @ViewBuilder
  private func entitySection(title: String, icon: String, items: [String], color: Color)
    -> some View
  {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Label(title, systemImage: icon)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(color)

        FlowLayout(spacing: 8) {
          ForEach(items, id: \.self) { item in
            Text(item)
              .font(.caption)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(color.opacity(0.1))
              .foregroundStyle(color)
              .clipShape(.rect(cornerRadius: 16))
          }
        }
      }
    }
  }

  // MARK: - Analysis Result View

  @ViewBuilder
  private func fullAnalysisResultView(_ result: CloudAnalysisResult) -> some View {
    if let parsed = result.parsedAnalysis {
      VStack(alignment: .leading, spacing: 20) {
        // Overview
        VStack(alignment: .leading, spacing: 8) {
          Label("Overview", systemImage: "doc.text")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)

          timestampAwareText(parsed.overview)
        }

        if !parsed.keyTakeaways.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Key Takeaways", systemImage: "lightbulb.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.orange)

            ForEach(Array(parsed.keyTakeaways.enumerated()), id: \.offset) { _, takeaway in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
                  .font(.caption)
                selectableText(takeaway)
              }
            }
          }
        }

        if !parsed.targetAudience.isEmpty || !parsed.engagementLevel.isEmpty {
          HStack(spacing: 16) {
            if !parsed.targetAudience.isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                Text("Target Audience")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text(parsed.targetAudience)
                  .font(.caption)
                  .fontWeight(.medium)
              }
            }

            if !parsed.engagementLevel.isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                Text("Engagement")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                  engagementIcon(parsed.engagementLevel)
                  Text(parsed.engagementLevel.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                }
              }
            }
          }
        }

        // Main Topics
        if !parsed.mainTopics.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Label("Main Topics", systemImage: "list.bullet.rectangle")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.purple)

            ForEach(Array(parsed.mainTopics.enumerated()), id: \.offset) { _, topic in
              VStack(alignment: .leading, spacing: 6) {
                Text(topic.topic)
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .foregroundStyle(.primary)

                selectableText(topic.summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)

                ForEach(topic.keyPoints, id: \.self) { point in
                  HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                      .font(.system(size: 4))
                      .foregroundStyle(.purple)
                      .padding(.top, 6)
                    selectableText(point)
                      .font(.caption)
                  }
                }
              }
              .padding()
              .background(Color.purple.opacity(0.05))
              .clipShape(.rect(cornerRadius: 8))
            }
          }
        }

        VStack(alignment: .leading, spacing: 16) {
          entitySection(title: "People", icon: "person.fill", items: parsed.people, color: .blue)
          entitySection(title: "Organizations", icon: "building.2.fill", items: parsed.organizations, color: .purple)
          entitySection(title: "Products", icon: "shippingbox.fill", items: parsed.products, color: .orange)
          entitySection(title: "Locations", icon: "mappin.circle.fill", items: parsed.locations, color: .green)
          entitySection(title: "Resources", icon: "book.fill", items: parsed.resources, color: .red)
        }

        if !parsed.highlights.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Highlights", systemImage: "star.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.yellow)

            ForEach(Array(parsed.highlights.enumerated()), id: \.offset) { _, highlight in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "star.fill")
                  .foregroundStyle(.yellow)
                  .font(.caption)
                selectableText(highlight)
              }
            }
          }
        }

        // Key Insights
        if !parsed.keyInsights.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Key Insights", systemImage: "lightbulb.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.orange)

            ForEach(Array(parsed.keyInsights.enumerated()), id: \.offset) { _, insight in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                  .foregroundStyle(.orange)
                  .font(.caption)
                selectableText(insight)
              }
            }
          }
        }

        // Notable Quotes
        if !parsed.notableQuotes.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Notable Quotes", systemImage: "quote.opening")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.green)

            ForEach(Array(parsed.notableQuotes.enumerated()), id: \.offset) { _, quote in
              VStack(alignment: .leading, spacing: 6) {
                selectableText("\"\(quote.text)\"")
                  .font(.subheadline)
                  .italic()

                if let seconds = quote.timeInSeconds {
                  timestampBadge(quote.timestamp!, seconds: seconds)
                }
              }
              .padding()
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .fill(Color.green.opacity(0.1))
              )
              .overlay(
                Rectangle()
                  .fill(Color.green)
                  .frame(width: 4),
                alignment: .leading
              )
            }
          }
        }

        if !parsed.actionItems.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Action Items", systemImage: "checkmark.circle.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.teal)

            ForEach(Array(parsed.actionItems.enumerated()), id: \.offset) { _, item in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                  .foregroundStyle(.teal)
                  .font(.caption)
                selectableText(item)
              }
            }
          }
        }

        if let controversial = parsed.controversialPoints, !controversial.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Controversial Points", systemImage: "exclamationmark.triangle.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.orange)

            ForEach(Array(controversial.enumerated()), id: \.offset) { _, point in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.orange)
                  .font(.caption)
                selectableText(point)
              }
            }
          }
        }

        if let entertaining = parsed.entertainingMoments, !entertaining.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Entertaining Moments", systemImage: "face.smiling.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.pink)

            ForEach(Array(entertaining.enumerated()), id: \.offset) { _, moment in
              HStack(alignment: .top, spacing: 8) {
                Image(systemName: "face.smiling.fill")
                  .foregroundStyle(.pink)
                  .font(.caption)
                selectableText(moment)
              }
            }
          }
        }

        if let qaItems = parsed.qaHighlights, !qaItems.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Q&A Highlights", systemImage: "bubble.left.and.bubble.right.fill")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundStyle(.cyan)

            ForEach(Array(qaItems.enumerated()), id: \.offset) { _, item in
              VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                  Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.cyan)
                    .font(.caption)
                  selectableText(item.question)
                    .fontWeight(.medium)
                }
                HStack(alignment: .top, spacing: 8) {
                  Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.leading, 2)
                  selectableText(item.answer)
                    .foregroundStyle(.secondary)
                }
              }
              .padding()
              .background(Color.cyan.opacity(0.05))
              .clipShape(.rect(cornerRadius: 8))
            }
          }
        }

        // Conclusion
        VStack(alignment: .leading, spacing: 8) {
          Label("Conclusion", systemImage: "checkmark.seal.fill")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.indigo)

          VStack(alignment: .leading, spacing: 4) {
            timestampAwareText(parsed.conclusion)
          }
          .padding()
          .background(Color.indigo.opacity(0.1))
          .clipShape(.rect(cornerRadius: 8))
        }
      }
    } else {
      selectableText(result.content)
    }
  }

  private func engagementIcon(_ level: String) -> some View {
    let iconName: String
    let color: Color
    switch level.lowercased() {
    case "high":
      iconName = "flame.fill"
      color = .red
    case "medium":
      iconName = "circle.lefthalf.filled"
      color = .orange
    default:
      iconName = "circle"
      color = .gray
    }
    return Image(systemName: iconName)
      .foregroundStyle(color)
      .font(.caption)
  }

  // MARK: - Selectable Text with Context Menu

  /// Text view with selection enabled and context menu for copy, translate, search
  private func selectableText(_ content: String) -> some View {
    Text(content)
      .font(.body)
      .textSelection(.enabled)
      .contextMenu {
        Button {
          PlatformClipboard.string = content
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
          // Open in Safari for web search
          if let query = content.prefix(100).addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://www.google.com/search?q=\(query)")
          {
            #if os(iOS)
            UIApplication.shared.open(url)
            #else
            NSWorkspace.shared.open(url)
            #endif
          }
        } label: {
          Label("Search Web", systemImage: "magnifyingglass")
        }

        ShareLink(item: content) {
          Label("Share", systemImage: "square.and.arrow.up")
        }
      }
  }

  // MARK: - Timestamp Badge

  /// Tappable timestamp pill with Play and Share actions
  private func timestampBadge(_ timestamp: String, seconds: TimeInterval) -> some View {
    TimestampLink(
      text: timestamp,
      seconds: seconds,
      onPlay: { viewModel.seekToTime(seconds) },
      onShare: { viewModel.shareTimestampedLink(seconds: seconds) }
    )
  }

  // MARK: - Timestamp-Aware Text

  /// Text view that detects inline timestamps and shows tappable chips below
  @ViewBuilder
  private func timestampAwareText(_ content: String) -> some View {
    let timestamps = TimestampUtils.findTimestamps(in: content)
    selectableText(content)
    if !timestamps.isEmpty {
      FlowLayout(spacing: 6) {
        ForEach(timestamps.indices, id: \.self) { i in
          timestampBadge(timestamps[i].text, seconds: timestamps[i].seconds)
        }
      }
    }
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
        ProgressView()
          .scaleEffect(0.8)
      }

      // Streaming text content
      if !viewModel.streamingText.isEmpty {
        Text(viewModel.streamingText)
          .font(.body)
          .textSelection(.enabled)
          .animation(.easeInOut(duration: 0.1), value: viewModel.streamingText)
      } else {
        HStack {
          Text("Waiting for response...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      // Metadata
      HStack {
        Label(
          settings.selectedProvider.displayName, systemImage: settings.selectedProvider.iconName
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        Spacer()
        Text(settings.currentModel)
          .font(.caption)
          .foregroundStyle(.secondary)
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

  /// Beautiful Q&A result card with all parsed fields
  private func qaResultCard(_ result: CloudQAResult) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      // Warning if JSON parsing failed
      if let warning = result.jsonParseWarning {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(warning)
            .font(.caption)
            .foregroundStyle(.orange)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 6))
      }

      // Question with enhanced styling
      HStack(alignment: .top, spacing: 10) {
        ZStack {
          Circle()
            .fill(Color.blue.opacity(0.15))
            .frame(width: 32, height: 32)
          Image(systemName: "bubble.left.fill")
            .font(.system(size: 14))
            .foregroundStyle(.blue)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Question")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
          Text(result.question)
            .font(.subheadline)
            .fontWeight(.medium)
        }
      }

      // Answer with enhanced styling and context menu
      HStack(alignment: .top, spacing: 10) {
        ZStack {
          Circle()
            .fill(Color.green.opacity(0.15))
            .frame(width: 32, height: 32)
          Image(systemName: "text.bubble.fill")
            .font(.system(size: 14))
            .foregroundStyle(.green)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Answer")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
          Text(result.answer)
            .font(.body)
            .textSelection(.enabled)
            .contextMenu {
              Button {
                PlatformClipboard.string = result.answer
              } label: {
                Label("Copy Answer", systemImage: "doc.on.doc")
              }

              Button {
                if let query = result.answer.prefix(100).addingPercentEncoding(
                  withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://www.google.com/search?q=\(query)")
                {
                  #if os(iOS)
                  UIApplication.shared.open(url)
                  #else
                  NSWorkspace.shared.open(url)
                  #endif
                }
              } label: {
                Label("Search Web", systemImage: "safari")
              }

              ShareLink(item: result.answer) {
                Label("Share", systemImage: "square.and.arrow.up")
              }
            }
        }
      }

      // Confidence badge
      if result.confidence != "unknown" {
        HStack(spacing: 6) {
          Image(systemName: confidenceIcon(result.confidence))
            .foregroundStyle(confidenceColor(result.confidence))
          Text("Confidence: \(result.confidence.capitalized)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(confidenceColor(result.confidence))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(confidenceColor(result.confidence).opacity(0.1))
        .clipShape(.rect(cornerRadius: 16))
      }

      // Related topics as chips
      if let topics = result.relatedTopics, !topics.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("Related Topics")
            .font(.caption)
            .foregroundStyle(.secondary)

          FlowLayout(spacing: 6) {
            ForEach(topics, id: \.self) { topic in
              Text(topic)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.1))
                .foregroundStyle(.purple)
                .clipShape(.rect(cornerRadius: 12))
            }
          }
        }
      }

      // Sources from transcript
      if let sources = result.sources, !sources.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Label("Sources from Transcript", systemImage: "quote.bubble")
            .font(.caption)
            .foregroundStyle(.secondary)

          ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
            Text("\"\(source)\"")
              .font(.caption)
              .italic()
              .foregroundStyle(.secondary)
              .padding(8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Color.platformSystemGray5)
              .clipShape(.rect(cornerRadius: 6))
          }
        }
      }

      Divider()

      // Metadata footer
      HStack {
        Label(result.provider.displayName, systemImage: result.provider.iconName)
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer()
        Text(result.model)
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text(result.timestamp.formatted(date: .abbreviated, time: .shortened))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .background(Color.platformSystemGray6)
    .clipShape(.rect(cornerRadius: 12))
  }

  /// Get icon for confidence level
  private func confidenceIcon(_ confidence: String) -> String {
    switch confidence.lowercased() {
    case "high": return "checkmark.seal.fill"
    case "medium": return "circle.lefthalf.filled"
    case "low": return "exclamationmark.circle"
    default: return "questionmark.circle"
    }
  }

  /// Get color for confidence level
  private func confidenceColor(_ confidence: String) -> Color {
    switch confidence.lowercased() {
    case "high": return .green
    case "medium": return .orange
    case "low": return .red
    default: return .gray
    }
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
        if let type, let streamingType = viewModel.currentStreamingType, type != streamingType {
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

            if progress >= 0 {
              Text("\(Int(progress * 100))% complete")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
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

// MARK: - Flow Layout (for tag chips)

struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let result = FlowResult(
      in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
    return result.size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
    for (index, subview) in subviews.enumerated() {
      subview.place(
        at: CGPoint(
          x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY),
        proposal: .unspecified)
    }
  }

  struct FlowResult {
    var frames: [CGRect] = []
    var size: CGSize = .zero

    init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
      var currentX: CGFloat = 0
      var currentY: CGFloat = 0
      var lineHeight: CGFloat = 0

      for subview in subviews {
        let size = subview.sizeThatFits(.unspecified)

        if currentX + size.width > maxWidth && currentX > 0 {
          currentX = 0
          currentY += lineHeight + spacing
          lineHeight = 0
        }

        frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
        lineHeight = max(lineHeight, size.height)
        currentX += size.width + spacing
      }

      self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
    }
  }
}

// MARK: - Prompt Preview Sheet

/// Shows the assembled (system + user) prompt before copying. Lets the user
/// see exactly what would be sent to an LLM and copy it for use in external tools.
private struct PromptPreviewSheet: View {
  let podcastTitle: String
  let episodeTitle: String
  let podcastLanguage: String?
  let transcript: String
  let formatHint: String?
  let onCopied: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var didCopy = false

  private var prompt: (system: String, user: String) {
    CloudAIService.shared.buildPrompt(
      type: .analysis,
      transcript: transcript,
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle,
      podcastLanguage: podcastLanguage,
      formatHint: formatHint
    )
  }

  private var combined: String {
    "## System\n\(prompt.system)\n\n## User\n\(prompt.user)"
  }

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
            Label("\(combined.count) chars", systemImage: "textformat.size")
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

          promptSection(title: "System", body: prompt.system)
          promptSection(title: "User", body: prompt.user)
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
          .background(didCopy ? Color.green : Color.blue)
          .foregroundStyle(.white)
          .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
    }
  }

  private func promptSection(title: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title.uppercased())
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .tracking(0.5)
      Text(body)
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.12))
        .clipShape(.rect(cornerRadius: 10))
    }
  }

  private func copy() {
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
