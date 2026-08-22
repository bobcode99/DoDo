//
//  EpisodeAIAnalysisView.swift
//  PodcastAnalyzer
//
//  Cloud-based AI analysis view using user-provided API keys (BYOK)
//  Uses CloudAIService for transcript analysis
//

import SwiftUI

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

  @State private var uiState = AIAnalysisUIState()

  private let settings = AISettingsManager.shared

  private var cloudQuestionIsAnalyzing: Bool {
    if case .analyzing = viewModel.aiAnalysis.cloudQuestionState { return true }
    return false
  }

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

      ScrollViewReader { proxy in
        ScrollView {
          aiContentView
        }
        .onChange(of: viewModel.aiAnalysis.cloudAnalysisCache.questionAnswers.count) { _, _ in
          scrollChatToBottom(proxy: proxy)
        }
        .onChange(of: cloudQuestionIsAnalyzing) { _, isAnalyzing in
          if isAnalyzing { scrollChatToBottom(proxy: proxy) }
        }
      }
    }
    .onAppear {
      uiState.formatHintDraft = settings.formatHint(for: viewModel.podcastTitle)
      uiState.isRegenerating = false
    }
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: toolbarPlacement) {
        Button(action: { uiState.showSettingsSheet = true }) {
          Image(systemName: "gear")
        }
      }
    }
    .sheet(isPresented: $uiState.showSettingsSheet) {
      NavigationStack {
        AISettingsView()
          #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
          #endif
          .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
              Button("Done") { uiState.showSettingsSheet = false }
            }
          }
      }
    }
    .sheet(isPresented: $uiState.showPromptPreview) {
      PromptPreviewSheet(
        podcastTitle: viewModel.podcastTitle,
        episodeTitle: viewModel.episode.title,
        podcastLanguage: viewModel.podcastLanguage,
        transcript: viewModel.transcript.transcriptText,
        formatHint: uiState.formatHintDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : uiState.formatHintDraft,
        onCopied: {
          uiState.promptCopied = true
          Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            uiState.promptCopied = false
          }
        }
      )
    }
  }

  // MARK: - AI Content View (shared between scrolled and non-scrolled modes)

  @ViewBuilder
  private var aiContentView: some View {
    VStack(alignment: .leading, spacing: 16) {
      switch uiState.selectedTab {
      case .analysis:
        AnalysisTabView(viewModel: viewModel, uiState: uiState)
      case .askQuestion:
        QuestionAnswerTabView(viewModel: viewModel, uiState: uiState)
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
          uiState.showSettingsSheet = true
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
      uiState.selectedTab = tab
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
          .fill(uiState.selectedTab == tab ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear))
      )
      .foregroundStyle(uiState.selectedTab == tab ? .white : .primary)
    }
    #if os(macOS)
    .buttonStyle(.plain)      // 🔑 THIS fixes the weird macOS behavior
    #endif
  }

  private func scrollChatToBottom(proxy: ScrollViewProxy) {
    withAnimation(.easeOut(duration: 0.25)) {
      proxy.scrollTo("qa-bottom-anchor", anchor: .bottom)
    }
  }
}
