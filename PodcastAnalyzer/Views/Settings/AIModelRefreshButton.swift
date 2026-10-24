//
//  AIModelRefreshButton.swift
//  PodcastAnalyzer
//
//  Icon-only button beside the model picker that re-fetches the provider's models.
//

import SwiftUI

struct AIModelRefreshButton: View {
    let provider: CloudAIProvider
    let modelState: AIModelFetchState
    var isDisabled = false

    var body: some View {
        Button {
            modelState.fetchModels(for: provider)
        } label: {
            Group {
                if modelState.isFetchingModels {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Label("Refresh Models", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .disabled(isDisabled || modelState.isFetchingModels)
        .buttonStyle(.borderless)
    }
}
