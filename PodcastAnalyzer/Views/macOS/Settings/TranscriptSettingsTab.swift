//
//  TranscriptSettingsTab.swift
//  PodcastAnalyzer
//
//  Transcript pane of the macOS Preferences window.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct TranscriptSettingsTab: View {
  let viewModel: SettingsViewModel
  @State private var showAutoTranscribeManagement = false
  @State private var showTranscriptionContext = false

  var body: some View {
    @Bindable var viewModel = viewModel
    @Bindable var subtitleSettings = SubtitleSettingsManager.shared

    Form {
      // MARK: Engine selection
      Section {
        Picker("Engine", selection: $viewModel.selectedTranscriptEngine)  {
          ForEach(TranscriptEngine.allCases) { engine in
            Text(engine.displayName).tag(engine)
          }
        }
        .onChange(of: viewModel.selectedTranscriptEngine) { _, newValue in
          viewModel.setTranscriptEngine(newValue)
        }

        Picker("Language", selection: $viewModel.selectedTranscriptLocale) {
          ForEach(SettingsViewModel.availableTranscriptLocales) { locale in
            Text(locale.name).tag(locale.id)
          }
        }
        .onChange(of: viewModel.selectedTranscriptLocale) { _, newValue in
          viewModel.setSelectedTranscriptLocale(newValue)
        }

        // Apple Speech model status row
        if viewModel.selectedTranscriptEngine == .appleSpeech {
          LabeledContent("Speech Model Status") {
            AppleSpeechStatusView(viewModel: viewModel)
          }
        }
      } header: {
        Text("Transcript Settings")
      } footer: {
        Text(viewModel.selectedTranscriptEngine == .whisper
          ? "\(viewModel.selectedTranscriptEngine.description)"
          : "Download the Apple Speech model for your preferred language. Each podcast uses its own language from the RSS feed."
        )
      }

      // MARK: Translation
      Section {
        Picker("Default Translation Language", selection: $subtitleSettings.targetLanguage) {
          ForEach(TranslationTargetLanguage.allCases, id: \.self) { language in
            Text(language.displayName).tag(language)
          }
        }

        Toggle("Auto-Translate on Load", isOn: $subtitleSettings.autoTranslateOnLoad)
      } header: {
        Text("Translation")
      } footer: {
        Text("Default target language for translating transcripts and episode descriptions.")
      }

      // MARK: Auto-generate
      Section {
        // The global "transcribe every download" toggle lives inside
        // AutoTranscribeManagementView, next to the per-podcast list — the two
        // are only tellable apart when shown together.
        Toggle("Detect Music", isOn: $subtitleSettings.enableMusicDetection)
        if subtitleSettings.enableMusicDetection {
          Picker("Music Sensitivity", selection: $subtitleSettings.musicDetectionSensitivity) {
            ForEach(MusicDetectionSensitivity.allCases, id: \.self) { level in
              Text(level.displayName).tag(level)
            }
          }
        }

        Toggle("Split Long Audio", isOn: $subtitleSettings.splitLongAudio)

        Button {
          showTranscriptionContext = true
        } label: {
          HStack {
            Label("Transcription Context", systemImage: "character.book.closed")
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Button {
          showAutoTranscribeManagement = true
        } label: {
          HStack {
            Label("Automatic Transcription", systemImage: "waveform.badge.plus")
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      } header: {
        Text("Automation")
      } footer: {
        Text("Detect Music marks music ranges as [♪ Music] instead of transcribing them. Split Long Audio transcribes in parallel parts (faster on Apple Speech); turn off for one single-pass run. Transcription Context adds per-podcast names & jargon to improve accuracy. Automatic Transcription covers both what gets transcribed on download and which shows are followed.")
      }

      // MARK: Whisper models list
      if viewModel.selectedTranscriptEngine == .whisper {
        Section {
          ForEach(WhisperModelVariant.allCases) { variant in
            MacWhisperModelRow(variant: variant)
          }
        } header: {
          Text("Whisper Models")
        } footer: {
          Text("On macOS, Medium and Large v3 Turbo offer the best accuracy. Models are stored in ~/Library/Caches.")
        }
      }

      // MARK: YAP server config
      if viewModel.selectedTranscriptEngine == .yapServer {
        YapServerSection()
      }
    }
    .formStyle(.grouped)
    .padding()
    .frame(minHeight: minTranscriptTabHeight(for: viewModel.selectedTranscriptEngine))
    .onAppear {
      viewModel.checkTranscriptModelStatus()
      WhisperModelManager.shared.checkAllModelStatuses()
    }
    .sheet(isPresented: $showAutoTranscribeManagement) {
      NavigationStack {
        AutoTranscribeManagementView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Done") { showAutoTranscribeManagement = false }
            }
          }
      }
      .frame(minWidth: 520, minHeight: 480)
    }
    .sheet(isPresented: $showTranscriptionContext) {
      NavigationStack {
        TranscriptContextManagementView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Done") { showTranscriptionContext = false }
            }
          }
      }
      .frame(minWidth: 520, minHeight: 480)
    }
  }

  private func minTranscriptTabHeight(for engine: TranscriptEngine) -> CGFloat {
    switch engine {
    case .whisper: 500
    case .yapServer: 360
    default: 300
    }
  }
}


#endif
