//
//  AddFeedView.swift
//  PodcastAnalyzer
//
//  Add-feed sheet for Settings.
//

import SwiftData
import SwiftUI

// MARK: - Add Feed Sheet View

struct AddFeedView: View {
  @Bindable var viewModel: SettingsViewModel
  var modelContext: ModelContext
  var onDismiss: () -> Void

  @FocusState private var isTextFieldFocused: Bool
  @State private var dismissTask: Task<Void, Never>?

  private var canAdd: Bool {
    !viewModel.rssUrlInput.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.isValidating
  }

  private var addButton: some View {
    Button(action: addFeed) {
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
      .background(canAdd ? Color.blue : Color.gray, in: .rect(cornerRadius: 14))
    }
    .disabled(!canAdd)
    .accessibilityLabel("Add Podcast")
  }

  private func addFeed() {
    viewModel.addRssLink(modelContext: modelContext) {
      // Dismiss on success after a short delay
      dismissTask?.cancel()
      dismissTask = Task {
        try? await Task.sleep(for: .seconds(1.5))
        if !Task.isCancelled { onDismiss() }
      }
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          // Icon
          Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: 60))
            .foregroundStyle(.blue)
            .padding(.top, 40)
            .accessibilityHidden(true)

          // Title and description
          VStack(spacing: 8) {
            Text("Add Podcast")
              .font(.title2)
              .bold()

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
            } else if let successMessage = viewModel.successMessage {
              Label {
                Text(successMessage)
                  .font(.caption)
                  .foregroundStyle(.green)
              } icon: {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
              }
            } else if let errorMessage = viewModel.errorMessage {
              Label {
                Text(errorMessage)
                  .font(.caption)
                  .foregroundStyle(.red)
              } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.red)
              }
            }
          }
          .padding(.horizontal, 24)
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .safeAreaInset(edge: .bottom) {
        addButton
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
