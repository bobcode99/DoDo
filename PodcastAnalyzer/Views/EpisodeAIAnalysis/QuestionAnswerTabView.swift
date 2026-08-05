//
//  QuestionAnswerTabView.swift
//  PodcastAnalyzer
//
//  "Ask Question" tab of EpisodeAIAnalysisView: free-form Q&A chat over the
//  episode transcript.
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

struct QuestionAnswerTabView: View {
  let viewModel: EpisodeDetailViewModel
  @Bindable var uiState: AIAnalysisUIState

  private let settings = AISettingsManager.shared

  private var canAnalyze: Bool {
    settings.hasConfiguredProvider && viewModel.hasTranscript
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      AIAnalysisTabHeader(
        title: "Ask Questions",
        description: "Ask any question about the episode content"
      )

      // Question input with X button and Enter to send
      HStack(spacing: 8) {
        HStack {
          TextField(
            viewModel.hasTranscript
              ? "Enter your question..."
              : "Transcribe this episode first to ask questions",
            text: $uiState.questionInput
          )
          .textFieldStyle(.plain)
          .disabled(!viewModel.hasTranscript)
          .onSubmit {
            submitQuestion()
          }

          // X button to clear input
          if !uiState.questionInput.isEmpty {
            Button(action: {
              uiState.questionInput = ""
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
        .opacity(viewModel.hasTranscript ? 1 : 0.55)

        Button(action: submitQuestion) {
          Image(systemName: "paperplane.fill")
            .font(.system(size: 18))
        }
        .disabled(
          uiState.questionInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !canAnalyze)
      }
      #if os(iOS)
      .submitLabel(.send)
      #endif

      // Q&A error — show above history so it's immediately visible
      if case .error(let errorMsg) = viewModel.aiAnalysis.cloudQuestionState {
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

      // Chat-style conversation: oldest at top, newest at bottom,
      // followed by a typing indicator while a new answer is in flight.
      let conversation = viewModel.aiAnalysis.cloudAnalysisCache.questionAnswers
      if !conversation.isEmpty || cloudQuestionIsAnalyzing {
        VStack(alignment: .leading, spacing: 12) {
          if !conversation.isEmpty {
            Text("Conversation")
              .font(.headline)
          }

          ForEach(Array(conversation.enumerated()), id: \.offset) { _, qa in
            userQuestionBubble(qa.question)
            aiAnswerBubble(qa)
          }

          if cloudQuestionIsAnalyzing {
            typingIndicatorBubble
          }
        }
      }

      // Bottom anchor used by ScrollViewReader to auto-scroll on new messages.
      Color.clear
        .frame(height: 1)
        .id("qa-bottom-anchor")
    }
  }

  var cloudQuestionIsAnalyzing: Bool {
    if case .analyzing = viewModel.aiAnalysis.cloudQuestionState { return true }
    return false
  }

  private func submitQuestion() {
    let trimmed = uiState.questionInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, canAnalyze else { return }
    viewModel.aiAnalysis.askCloudQuestion(uiState.questionInput)
    uiState.questionInput = ""
    #if os(iOS)
    // Hide keyboard after submitting
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
  }

  /// Right-aligned user question bubble.
  private func userQuestionBubble(_ question: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Spacer(minLength: 40)
      Text(question)
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor, in: .rect(cornerRadius: 16))
        .textSelection(.enabled)
      ZStack {
        Circle()
          .fill(Color.accentColor.opacity(0.15))
          .frame(width: 28, height: 28)
        Image(systemName: "person.fill")
          .font(.system(size: 13))
          .foregroundStyle(Color.accentColor)
      }
    }
  }

  /// Left-aligned AI answer bubble with confidence, topics, sources, and footer.
  private func aiAnswerBubble(_ result: CloudQAResult) -> some View {
    HStack(alignment: .top, spacing: 8) {
      ZStack {
        Circle()
          .fill(Color.green.opacity(0.15))
          .frame(width: 28, height: 28)
        Image(systemName: "sparkles")
          .font(.system(size: 13))
          .foregroundStyle(.green)
      }

      VStack(alignment: .leading, spacing: 10) {
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

        HStack {
          Label(result.provider.displayName, systemImage: result.provider.iconName)
            .font(.caption2)
            .foregroundStyle(.secondary)
          Spacer()
          Text(result.model)
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text(Formatters.formatDate(result.timestamp, time: .shortened))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .padding(14)
      .background(Color.platformSystemGray6, in: .rect(cornerRadius: 16))

      Spacer(minLength: 40)
    }
  }

  /// Animated three-dot "typing" indicator shown while an answer is in flight.
  private var typingIndicatorBubble: some View {
    HStack(alignment: .top, spacing: 8) {
      ZStack {
        Circle()
          .fill(Color.green.opacity(0.15))
          .frame(width: 28, height: 28)
        Image(systemName: "sparkles")
          .font(.system(size: 13))
          .foregroundStyle(.green)
      }
      TypingDotsView()
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.platformSystemGray6, in: .rect(cornerRadius: 16))
      Spacer(minLength: 40)
    }
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
}
