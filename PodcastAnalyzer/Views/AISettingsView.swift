//
//  AISettingsView.swift
//  PodcastAnalyzer
//
//  Settings UI for configuring Cloud AI providers (BYOK)
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

struct AISettingsView: View {
    @Bindable private var settings = AISettingsManager.shared
    @State private var showingTestResult = false
    @State private var testResultMessage = ""
    @State private var testResultSuccess = false
    @State private var isTesting = false

    // Dynamic model fetching
    @State private var fetchedModels: [CloudAIProvider: [String]] = [:]
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?

    // On-device AI availability
    @State private var onDeviceAvailability: FoundationModelsAvailability = .unavailable(reason: "Checking...")

    // Local server URL editing
    @State private var lmstudioURLText: String = ""
    @State private var ollamaURLText: String = ""

    // Shortcut name list management
    @State private var newShortcutName: String = ""
    @State private var isAddingShortcut: Bool = false

    private let shortcuts = ShortcutsAIService.shared

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
        .alert(testResultSuccess ? "Success" : "Error", isPresented: $showingTestResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testResultMessage)
        }
        .onAppear(perform: onAppearActions)
    }
    #endif

    // MARK: - iOS Body
    private var iOSBody: some View {
        Form {
            formContent
        }
        .formStyle(.grouped)
        .navigationTitle("AI Settings")
        .alert(testResultSuccess ? "Success" : "Error", isPresented: $showingTestResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testResultMessage)
        }
        .onAppear(perform: onAppearActions)
    }

    // MARK: - Shared Form Content
    @ViewBuilder
    private var formContent: some View {
            // MARK: - Provider Selection
            Section {
                Picker("AI Provider", selection: $settings.selectedProvider) {
                    ForEach(CloudAIProvider.allCases, id: \.self) { provider in
                        Label(provider.displayName, systemImage: provider.iconName)
                            .tag(provider)
                    }
                }
                .onChange(of: settings.selectedProvider) { _, newProvider in
                    // Auto-fetch models when provider changes
                    if newProvider.usesLocalServer {
                        // Local providers: always try to fetch
                        if fetchedModels[newProvider] == nil {
                            fetchModels(for: newProvider)
                        }
                    } else {
                        let apiKey = settings.apiKey(for: newProvider)
                        if !apiKey.isEmpty && fetchedModels[newProvider] == nil {
                            fetchModels(for: newProvider)
                        }
                    }
                }

                if let url = settings.selectedProvider.apiKeyURL {
                    Link(destination: url) {
                        HStack {
                            Text("Get \(settings.selectedProvider.displayName) API Key")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }

                Text(settings.selectedProvider.pricingNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Cloud AI Provider")
            } footer: {
                Text("Cloud AI is used for full transcript analysis. You provide your own API key (BYOK).")
            }

            // MARK: - API Key Input (for providers that need it)
            if settings.selectedProvider.requiresAPIKey {
                Section {
                    apiKeyField(for: settings.selectedProvider)

                    // Model selection with refresh button
                    HStack {
                        modelPicker(for: settings.selectedProvider)

                        // Refresh models button
                        Button(action: { fetchModels(for: settings.selectedProvider) }) {
                            if isFetchingModels {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(settings.currentAPIKey.isEmpty || isFetchingModels)
                        .buttonStyle(.borderless)
                    }

                    modelFetchStatusView

                    // Test connection button
                    testConnectionButton
                } header: {
                    Text("\(settings.selectedProvider.displayName) Configuration")
                } footer: {
                    Text("Tap the refresh button to fetch the latest available models from the API.")
                }
            }

            // MARK: - Local Server Configuration (LMStudio / Ollama)
            if settings.selectedProvider.usesLocalServer {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("No API key needed!")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        Text("Runs locally on your machine. Make sure \(settings.selectedProvider.displayName) is running before connecting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Base URL configuration
                    HStack {
                        Text("Server URL")
                        Spacer()
                        TextField("http://localhost:1234", text: localURLBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                    }

                    // Model selection with refresh button
                    HStack {
                        modelPicker(for: settings.selectedProvider)

                        Button(action: { fetchModels(for: settings.selectedProvider) }) {
                            if isFetchingModels {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(isFetchingModels)
                        .buttonStyle(.borderless)
                    }

                    modelFetchStatusView

                    Toggle(isOn: $settings.disableThinkingForLocalModels) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Disable Thinking")
                            Text("Skips chain-of-thought reasoning for faster responses. Best for DeepSeek-R1 and other reasoning models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Test connection button
                    testConnectionButton
                } header: {
                    Text("\(settings.selectedProvider.displayName) Configuration")
                } footer: {
                    if settings.selectedProvider == .lmstudio {
                        Text("Default: http://localhost:1234 — Load a model in LM Studio first, then tap refresh.")
                    } else {
                        Text("Default: http://localhost:11434 — Run 'ollama serve' and pull a model first.")
                    }
                }
            }

            // MARK: - Apple PCC Configuration
            if settings.selectedProvider == .applePCC {
                // Section 1: info
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("No API key needed!")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("Shortcuts calls your configured shortcut to process AI requests. You can use any AI provider (Apple Intelligence, ChatGPT, Gemini, etc.) inside your shortcut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Shortcut Configuration")
                }

                // Section 2: shortcut names list — ForEach as direct Section children
                Section {
                    ForEach(shortcuts.shortcutNames, id: \.self) { name in
                        HStack(spacing: 12) {
                            Image(systemName: shortcuts.shortcutName == name ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(shortcuts.shortcutName == name ? .blue : .secondary)
                                .font(.system(size: 18))
                                .animation(.easeInOut(duration: 0.15), value: shortcuts.shortcutName)
                            Text(name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if shortcuts.shortcutNames.count > 1 {
                                Button(role: .destructive) {
                                    shortcuts.removeShortcutName(name)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            shortcuts.shortcutName = name
                        }
                    }

                    if isAddingShortcut {
                        HStack(spacing: 10) {
                            TextField("Shortcut name", text: $newShortcutName)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .onSubmit { commitAddShortcut() }
                                #endif
                            Button("Add") { commitAddShortcut() }
                                .disabled(newShortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.blue)
                            Button("Cancel") {
                                newShortcutName = ""
                                isAddingShortcut = false
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            newShortcutName = ""
                            isAddingShortcut = true
                        } label: {
                            Label("Add Shortcut", systemImage: "plus.circle.fill")
                        }
                    }
                } header: {
                    Text("Shortcuts")
                } footer: {
                    Text("Tap a shortcut to make it active. Add as many as you need to switch between providers quickly.")
                }

                // Section 3: open shortcuts + timeout
                Section {
                    Button(action: {
                        ShortcutsAIService.shared.openShortcutsApp()
                    }) {
                        HStack {
                            Image(systemName: "square.on.square")
                            Text("Open Shortcuts App")
                        }
                    }

                    HStack {
                        Text("Timeout")
                        Spacer()
                        Picker("Timeout", selection: $settings.shortcutsTimeout) {
                            Text("60s").tag(60.0 as TimeInterval)
                            Text("120s").tag(120.0 as TimeInterval)
                            Text("180s").tag(180.0 as TimeInterval)
                            Text("300s").tag(300.0 as TimeInterval)
                        }
                        .pickerStyle(.menu)
                    }
                } footer: {
                    Text("How long to wait for Shortcuts to return a result before timing out.")
                }

                // Section 4: setup instructions
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Setup Instructions:")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        VStack(alignment: .leading, spacing: 4) {
                            instructionRow(number: 1, text: "Open the Shortcuts app")
                            instructionRow(number: 2, text: "Create a new shortcut")
                            instructionRow(number: 3, text: "Add 'Get Clipboard' action")
                            instructionRow(number: 4, text: "Add 'Summarize' or 'Ask ChatGPT' action")
                            instructionRow(number: 5, text: "Set output to 'Text'")
                            instructionRow(number: 6, text: "Add 'Copy to Clipboard' action")
                            instructionRow(number: 7, text: "Name it exactly as configured above")
                        }
                    }

                    // Tip about Ask Every Time
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                            Text("Pro Tip")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        Text("Use 'Ask Every Time' for the Model parameter to choose between ChatGPT, Apple Intelligence, Gemini, or other models each time you run the shortcut.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 8))

                    // How it works
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("How It Works")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        Text("When you analyze a transcript, the app will automatically run your shortcut, wait for it to complete, and display the result. No manual copy/paste needed!")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 8))
                } header: {
                    Text("Setup Instructions")
                }
            }

            // MARK: - Analysis Language
            Section {
                Picker("Response Language", selection: $settings.analysisLanguage) {
                    Section("Behavior") {
                        ForEach(AnalysisLanguage.behaviorCases, id: \.self) { language in
                            languagePickerRow(language)
                        }
                    }
                    Section("Popular Languages") {
                        ForEach(AnalysisLanguage.popularLanguageCases, id: \.self) { language in
                            languagePickerRow(language)
                        }
                    }
                    Section("Custom") {
                        languagePickerRow(.custom)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #else
                .pickerStyle(.menu)
                #endif

                // Custom language entry field (only when Custom selected)
                if settings.analysisLanguage == .custom {
                    HStack(spacing: 8) {
                        Text(AnalysisLanguage.custom.emoji)
                        TextField(
                            "Language name (e.g. Italian, Swahili)",
                            text: $settings.customAnalysisLanguageName
                        )
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        #endif
                        .submitLabel(.done)
                    }
                }

                // Show current language preview with resolved language
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.analysisLanguage.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Show resolved language
                        Text(resolvedLanguageText)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                Text("Analysis Language")
            } footer: {
                Text("Controls the language of AI-generated summaries, highlights, and other analysis results.")
            }

            // MARK: - Transcript Format
            Section {
                Picker("Transcript Format", selection: $settings.transcriptFormat) {
                    ForEach(TranscriptFormatForAI.allCases, id: \.self) { format in
                        Label {
                            VStack(alignment: .leading) {
                                Text(format.displayName)
                            }
                        } icon: {
                            Image(systemName: format.icon)
                        }
                        .tag(format)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #else
                .pickerStyle(.menu)
                #endif

                // Show format description
                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text(settings.transcriptFormat.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Transcript Format")
            } footer: {
                Text("Sentence-based format is recommended for better AI analysis quality and lower token costs.")
            }

            // MARK: - Other Provider Keys (Collapsed)
            Section {
                DisclosureGroup("Configure Other Providers") {
                    ForEach(CloudAIProvider.allCases.filter { $0 != settings.selectedProvider && $0.requiresAPIKey }, id: \.self) { provider in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(provider.displayName, systemImage: provider.iconName)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            apiKeyField(for: provider)

                            if !settings.apiKey(for: provider).isEmpty {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Key configured")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Divider()
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Additional Providers")
            }

            // MARK: - On-Device AI Info
            Section {
                HStack {
                    Image(systemName: "apple.intelligence")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading) {
                        Text("Apple Foundation Models")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Used for quick tags, listening history summary & episode recommendations (no API key needed)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Show actual availability status
                HStack {
                    if onDeviceAvailability.isAvailable {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Available and ready")
                            .font(.caption)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(onDeviceAvailability.message ?? "Not available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // On-device feature list
                VStack(alignment: .leading, spacing: 6) {
                    onDeviceFeatureRow(icon: "tag", title: "Quick Tags", description: "Auto-generate tags from episode metadata")
                    onDeviceFeatureRow(icon: "clock.arrow.circlepath", title: "Listening History Summary", description: "Summarize your listening habits and patterns")
                    onDeviceFeatureRow(icon: "star.leadinghalf.filled", title: "Episode Recommendations", description: "Get personalized episode suggestions")
                }
            } header: {
                Text("On-Device AI")
            } footer: {
                Text("On-device AI runs completely on your device. No internet required, completely private.")
            }

            // MARK: - Context Window Info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("On-Device")
                        Spacer()
                        Text("~4,096 tokens")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(settings.selectedProvider.displayName)
                        Spacer()
                        Text("\(formatNumber(settings.selectedProvider.contextWindowSize)) tokens")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            } header: {
                Text("Context Window Comparison")
            } footer: {
                Text("Larger context windows allow analyzing longer transcripts in a single request, resulting in better quality summaries.")
            }
    }

    // MARK: - Reusable Subviews

    @ViewBuilder
    private var modelFetchStatusView: some View {
        if isFetchingModels {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Fetching available models...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let error = modelFetchError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else if let models = fetchedModels[settings.selectedProvider], !models.isEmpty {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(models.count) models available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var testConnectionButton: some View {
        Button(action: testConnection) {
            HStack {
                if isTesting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "checkmark.circle")
                }
                Text("Test Connection")
            }
        }
        .disabled(
            (settings.selectedProvider.requiresAPIKey && settings.currentAPIKey.isEmpty)
            || isTesting
        )
    }

    /// Binding for the local server URL text field (LMStudio or Ollama)
    private var localURLBinding: Binding<String> {
        switch settings.selectedProvider {
        case .lmstudio:
            return Binding(
                get: { lmstudioURLText },
                set: { newValue in
                    lmstudioURLText = newValue
                    if let url = URL(string: newValue), !newValue.isEmpty {
                        settings.lmstudioBaseURL = url
                    }
                }
            )
        case .ollama:
            return Binding(
                get: { ollamaURLText },
                set: { newValue in
                    ollamaURLText = newValue
                    if let url = URL(string: newValue), !newValue.isEmpty {
                        settings.ollamaBaseURL = url
                    }
                }
            )
        default:
            return .constant("")
        }
    }

    // MARK: - Actions

    private func onAppearActions() {
        // Initialize local URL text fields
        lmstudioURLText = settings.lmstudioBaseURL.absoluteString
        ollamaURLText = settings.ollamaBaseURL.absoluteString

        // Auto-fetch models
        let provider = settings.selectedProvider
        if provider.usesLocalServer {
            if fetchedModels[provider] == nil {
                fetchModels(for: provider)
            }
        } else {
            let apiKey = settings.apiKey(for: provider)
            if !apiKey.isEmpty && fetchedModels[provider] == nil {
                fetchModels(for: provider)
            }
        }

        // Check on-device AI availability
        checkOnDeviceAvailability()
    }

    private func commitAddShortcut() {
        let name = newShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        shortcuts.addShortcutName(name)
        newShortcutName = ""
        isAddingShortcut = false
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func apiKeyField(for provider: CloudAIProvider) -> some View {
        let binding = Binding<String>(
            get: { settings.apiKey(for: provider) },
            set: { newValue in
                settings.setAPIKey(newValue, for: provider)
                // Auto-fetch models when API key is entered
                if !newValue.isEmpty && provider == settings.selectedProvider {
                    fetchModels(for: provider)
                }
            }
        )

        SecureField("\(provider.displayName) API Key", text: binding)
            .textContentType(.password)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }

    @ViewBuilder
    private func modelPicker(for provider: CloudAIProvider) -> some View {
        let binding: Binding<String> = {
            switch provider {
            case .applePCC:
                return .constant("Shortcuts")
            case .openai:
                return $settings.selectedOpenAIModel
            case .claude:
                return $settings.selectedClaudeModel
            case .gemini:
                return $settings.selectedGeminiModel
            case .groq:
                return $settings.selectedGroqModel
            case .grok:
                return $settings.selectedGrokModel
            case .lmstudio:
                return $settings.selectedLMStudioModel
            case .ollama:
                return $settings.selectedOllamaModel
            }
        }()

        // Use fetched models if available, otherwise use hardcoded defaults
        let models = fetchedModels[provider] ?? provider.availableModels

        if models.isEmpty && provider.usesLocalServer {
            HStack {
                Text("Model")
                Spacer()
                TextField("e.g. llama3.2", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
        } else if models.isEmpty {
            HStack {
                Text("Model")
                Spacer()
                Text("No models loaded")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } else {
            Picker("Model", selection: binding) {
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
    }

    // MARK: - Actions

    private func fetchModels(for provider: CloudAIProvider) {
        let apiKey = settings.apiKey(for: provider)

        // For local providers, don't require API key
        if provider.requiresAPIKey && apiKey.isEmpty {
            return
        }

        isFetchingModels = true
        modelFetchError = nil

        Task {
            do {
                let service = CloudAIService.shared
                let models = try await service.fetchAvailableModels(for: provider, apiKey: apiKey)

                fetchedModels[provider] = models
                isFetchingModels = false

                // If current model is not in the list, select the first available
                let currentModel: String
                switch provider {
                case .applePCC: currentModel = "Shortcuts"
                case .openai: currentModel = settings.selectedOpenAIModel
                case .claude: currentModel = settings.selectedClaudeModel
                case .gemini: currentModel = settings.selectedGeminiModel
                case .groq: currentModel = settings.selectedGroqModel
                case .grok: currentModel = settings.selectedGrokModel
                case .lmstudio: currentModel = settings.selectedLMStudioModel
                case .ollama: currentModel = settings.selectedOllamaModel
                }

                if !models.contains(currentModel), let firstModel = models.first {
                    switch provider {
                    case .applePCC: break
                    case .openai: settings.selectedOpenAIModel = firstModel
                    case .claude: settings.selectedClaudeModel = firstModel
                    case .gemini: settings.selectedGeminiModel = firstModel
                    case .groq: settings.selectedGroqModel = firstModel
                    case .grok: settings.selectedGrokModel = firstModel
                    case .lmstudio: settings.selectedLMStudioModel = firstModel
                    case .ollama: settings.selectedOllamaModel = firstModel
                    }
                }
            } catch {
                let fallback = provider.availableModels
                if provider.usesLocalServer {
                    modelFetchError = "Cannot connect to \(provider.displayName). Is it running?"
                    fetchedModels[provider] = nil
                } else {
                    modelFetchError = "Could not fetch models. Using defaults."
                    fetchedModels[provider] = fallback
                }
                isFetchingModels = false
            }
        }
    }

    private func testConnection() {
        isTesting = true

        Task {
            do {
                let service = CloudAIService.shared
                _ = try await service.testConnection()

                testResultSuccess = true
                testResultMessage = "Connection successful!\n\nProvider: \(settings.selectedProvider.displayName)\nModel: \(settings.currentModel)"
                showingTestResult = true
                isTesting = false
            } catch {
                testResultSuccess = false
                testResultMessage = "Connection failed: \(error.localizedDescription)"
                showingTestResult = true
                isTesting = false
            }
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// Row used by every section of the Response Language picker.
    @ViewBuilder
    private func languagePickerRow(_ language: AnalysisLanguage) -> some View {
        Label {
            Text(language.displayName)
        } icon: {
            Text(language.emoji)
        }
        .tag(language)
    }

    /// Computed property to show the resolved language based on the current setting
    private var resolvedLanguageText: String {
        switch settings.analysisLanguage {
        case .deviceLanguage:
            let preferredLanguage = Locale.preferredLanguages.first ?? "en"
            let languageName = Locale.current.localizedString(forLanguageCode: preferredLanguage) ?? "English"
            return "Will respond in: \(languageName)"
        case .matchPodcast:
            return "Will respond in: Same as podcast language"
        case .custom:
            let trimmed = settings.customAnalysisLanguageName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Will respond in: (no custom language set — no instruction sent)"
            }
            return "Will respond in: \(trimmed)"
        default:
            return "Will respond in: \(settings.analysisLanguage.rawValue)"
        }
    }

    private func onDeviceFeatureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func checkOnDeviceAvailability() {
        if #available(iOS 26.0, macOS 26.0, *) {
            Task {
                let service = AppleFoundationModelsService()
                let availability = await service.checkAvailability()

                onDeviceAvailability = availability
            }
        } else {
            onDeviceAvailability = .unavailable(reason: "Requires iOS 26+ / macOS 26+")
        }
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
