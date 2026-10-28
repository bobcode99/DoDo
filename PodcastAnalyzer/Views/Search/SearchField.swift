//
//  SearchField.swift
//  PodcastAnalyzer
//
//  The search bar under the Search title. A plain TextField rather than
//  `.searchable`, which on a search-role tab moves the field into the tab
//  bar. Voice input is the keyboard's own dictation key: it needs no
//  microphone permission, because the system records, not the app.
//

import SwiftUI

struct SearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .focused(isFocused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .glassEffect(Glass.regular, in: .capsule)
    }
}
