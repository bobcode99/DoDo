//
//  AddFeedView.swift
//  PodcastAnalyzer
//
//  Feed row and add-feed sheet for Settings.
//

import SwiftData
import SwiftUI

// MARK: - Feed Row View

struct FeedRowView: View {
  let feed: PodcastInfoModel

  var body: some View {
    HStack(spacing: 12) {
      // Podcast artwork
      if let urlString = feed.imageURL.isEmpty ? nil : feed.imageURL,
        let url = URL(string: urlString)
      {
        AsyncImage(url: url) { phase in
          switch phase {
          case .empty:
            ZStack {
              Color.gray.opacity(0.2)
              ProgressView().scaleEffect(0.5)
            }
          case .success(let image):
            image.resizable().scaledToFill()
          case .failure:
            Image(systemName: "mic.fill")
              .foregroundStyle(.purple)
          @unknown default:
            EmptyView()
          }
        }
        .frame(width: 50, height: 50)
        .clipShape(.rect(cornerRadius: 8))
      } else {
        Color.purple.opacity(0.2)
          .clipShape(.rect(cornerRadius: 8))
          .frame(width: 50, height: 50)
          .overlay(
            Image(systemName: "mic.fill")
              .foregroundStyle(.purple)
          )
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(feed.title)
          .font(.body)
          .fontWeight(.medium)
          .lineLimit(1)

        Text("\(feed.episodeCount) episodes")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Add Feed Sheet View

struct AddFeedView: View {
  @Bindable var viewModel: SettingsViewModel
  var modelContext: ModelContext
  var onDismiss: () -> Void

  @FocusState private var isTextFieldFocused: Bool
  @State private var dismissTask: Task<Void, Never>?

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        // Icon
        Image(systemName: "antenna.radiowaves.left.and.right")
          .font(.system(size: 60))
          .foregroundStyle(.blue)
          .padding(.top, 40)

        // Title and description
        VStack(spacing: 8) {
          Text("Add Podcast")
            .font(.title2)
            .fontWeight(.bold)

          Text("Enter the RSS feed URL to subscribe")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        // Input field
        VStack(spacing: 12) {
          TextField("https://example.com/feed.xml", text: $viewModel.rssUrlInput)
            .textFieldStyle(.plain)
            .padding(16)
            .background(Color.platformSystemGray6)
            .clipShape(.rect(cornerRadius: 12))
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .disabled(viewModel.isValidating)
            .focused($isTextFieldFocused)

          // Status messages
          if viewModel.isValidating {
            HStack(spacing: 8) {
              ProgressView()
                .scaleEffect(0.8)
              Text("Validating feed...")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } else if !viewModel.successMessage.isEmpty {
            HStack(spacing: 6) {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
              Text(viewModel.successMessage)
                .font(.caption)
                .foregroundStyle(.green)
            }
          } else if !viewModel.errorMessage.isEmpty {
            HStack(spacing: 6) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
              Text(viewModel.errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
            }
          }
        }
        .padding(.horizontal, 24)

        Spacer()

        // Add button
        Button(action: {
          viewModel.addRssLink(modelContext: modelContext) {
            // Dismiss on success after a short delay
            dismissTask?.cancel()
            dismissTask = Task {
              try? await Task.sleep(for: .seconds(1.5))
              if !Task.isCancelled { onDismiss() }
            }
          }
        }) {
          HStack {
            if viewModel.isValidating {
              ProgressView()
                .tint(.white)
            } else {
              Image(systemName: "plus.circle.fill")
              Text("Add Podcast")
            }
          }
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(
            RoundedRectangle(cornerRadius: 14)
              .fill(
                viewModel.rssUrlInput.trimmingCharacters(in: .whitespaces).isEmpty
                  || viewModel.isValidating ? Color.gray : Color.blue)
          )
        }
        .disabled(
          viewModel.rssUrlInput.trimmingCharacters(in: .whitespaces).isEmpty
            || viewModel.isValidating
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            viewModel.clearMessages()
            onDismiss()
          }
        }
      }
      .onAppear {
        isTextFieldFocused = true
      }
      .onDisappear {
        dismissTask?.cancel()
        viewModel.clearMessages()
      }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
  }
}
