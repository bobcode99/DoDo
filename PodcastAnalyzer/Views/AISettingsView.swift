//
//  AISettingsView.swift
//  PodcastAnalyzer
//
//  Settings UI for configuring Cloud AI providers (BYOK)
//

import SwiftUI

struct AISettingsView: View {
    @Bindable private var settings = AISettingsManager.shared
    @State private var modelState = AIModelFetchState()

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - macOS Body
    #if os(macOS)
    private var macOSBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                formContent
            }
            .padding(20)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(minWidth: 500, minHeight: 400)
        .navigationTitle("AI Settings")
        .alert(modelState.testResultSuccess ? "Success" : "Error", isPresented: $modelState.showingTestResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(modelState.testResultMessage)
        }
        .onAppear { modelState.autoFetchIfNeeded(for: settings.selectedProvider) }
    }
    #endif

    // MARK: - iOS Body
    private var iOSBody: some View {
        Form {
            formContent
        }
        .formStyle(.grouped)
        .navigationTitle("AI Settings")
        .alert(modelState.testResultSuccess ? "Success" : "Error", isPresented: $modelState.showingTestResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(modelState.testResultMessage)
        }
        .onAppear { modelState.autoFetchIfNeeded(for: settings.selectedProvider) }
    }

    // MARK: - Shared Form Content
    @ViewBuilder
    private var formContent: some View {
        AISettingsProviderSection(modelState: modelState)

        if settings.selectedProvider.requiresAPIKey {
            AISettingsAPIKeySection(modelState: modelState)
        }

        if settings.selectedProvider.usesLocalServer {
            AISettingsLocalServerSection(modelState: modelState)
        }

        if settings.selectedProvider == .applePCC {
            AISettingsShortcutsSections()
        }

        AISettingsLanguageSection()
        AISettingsOtherProvidersSection(modelState: modelState)
        AISettingsOnDeviceSection()
        AISettingsContextWindowSection()
    }
}

#Preview {
    #if os(macOS)
    AISettingsView()
        .frame(width: 600, height: 500)
    #else
    NavigationStack {
        AISettingsView()
    }
    #endif
}
