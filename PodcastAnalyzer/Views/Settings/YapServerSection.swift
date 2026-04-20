//
//  YapServerSection.swift
//  PodcastAnalyzer
//
//  Settings section for configuring the local yap transcription server.
//

import SwiftUI

struct YapServerSection: View {
    @Bindable private var settings = YapServerSettings.shared

    var body: some View {
        Section {
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
            .onChange(of: settings.serverURL) { settings.save() }

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
            .onChange(of: settings.apiKey) { settings.save() }
        } header: {
            Text("Yap Server")
        } footer: {
            Text("Enter the address of your running yap server. Leave API Key empty if started without --api-key.")
        }
    }
}
