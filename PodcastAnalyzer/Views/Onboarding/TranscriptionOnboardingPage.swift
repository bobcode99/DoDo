//
//  TranscriptionOnboardingPage.swift
//  PodcastAnalyzer
//
//  Optional onboarding step: point DoDo at a Yap server for faster, higher
//  quality transcripts than on-device Apple Speech.
//

#if os(iOS)
import SwiftUI

struct TranscriptionOnboardingPage: View {
  let onNext: () -> Void

  var body: some View {
    Form {
      Section {
        VStack(spacing: 10) {
          Image(systemName: "text.bubble.fill")
            .font(.system(size: 52))
            .foregroundStyle(.purple.gradient)
          Text("Transcription")
            .font(.largeTitle)
            .bold()
          Text("Apple Speech transcribes on-device with no setup. For faster, higher-quality transcripts, point DoDo at a Yap server on your network.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
      }

      // Reuse the Settings section: URL, optional API key, Test Connection.
      YapServerSection()

      Section {
        Button(action: onNext) {
          Text("Continue")
            .bold()
            .frame(maxWidth: .infinity)
        }
      } footer: {
        Text("Optional — you can set this up anytime in Settings. Swipe to skip.")
      }
    }
  }
}

#Preview {
  TranscriptionOnboardingPage(onNext: {})
}

#endif
