//
//  YapServerSection.swift
//  PodcastAnalyzer
//
//  Settings section for configuring the local yap transcription server.
//

import SwiftUI

struct YapServerSection: View {
    /// Setup guide for running a yap server. Linked first in the section: this
    /// is the one control someone who hasn't installed yap yet can actually use,
    /// and it is reached from onboarding where that is the common case.
    private let wikiLink = URL(string: "https://github.com/bobcode99/yap/wiki")!

    @Bindable private var settings = YapServerSettings.shared
    @State private var testState: TestState = .idle
    @State private var testTask: Task<Void, Never>?

    enum TestState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        Section {
            Link(destination: wikiLink) {
                HStack {
                    Image(systemName: "book")
                        .foregroundStyle(.purple)
                        .frame(width: 24)
                    Text("Setup Guide")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Image(systemName: "network")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                TextField("Server URL", text: $settings.serverURL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            .onChange(of: settings.serverURL) {
                settings.save()
                testState = .idle
            }

            HStack {
                Image(systemName: "key.horizontal")
                    .foregroundStyle(.orange)
                    .frame(width: 24)
                SecureField("API Key (optional)", text: $settings.apiKey)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            .onChange(of: settings.apiKey) {
                settings.save()
                testState = .idle
            }

            Button(action: runTest) {
                HStack {
                    Image(systemName: "bolt.horizontal.circle")
                        .foregroundStyle(.green)
                        .frame(width: 24)
                    Text("Test Connection")
                    Spacer()
                    if case .testing = testState {
                        ProgressView().scaleEffect(0.7)
                    }
                }
            }
            .disabled(settings.serverURL.isEmpty || testState == .testing)

            switch testState {
            case .idle:
                EmptyView()
            case .testing:
                EmptyView()
            case .success(let summary):
                Label(summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        } header: {
            Text("Yap Server")
        } footer: {
            Text("Don't have one yet? The Setup Guide walks through installing and running yap. Leave API Key empty if started without --api-key.")
        }
    }

    private func runTest() {
        testTask?.cancel()
        let serverURL = settings.serverURL
        let apiKey = settings.apiKey.isEmpty ? nil : settings.apiKey
        testState = .testing
        testTask = Task {
            let service = YapTranscriptService()
            do {
                let result = try await service.checkHealth(serverURL: serverURL, apiKey: apiKey)
                let backendList = result.backends.isEmpty
                    ? "no backends"
                    : "\(result.backends.count) backend\(result.backends.count == 1 ? "" : "s") · default: \(result.defaultBackend)"
                testState = .success("Connected (\(result.healthStatus)) · \(backendList)")
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }
}
